import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

typedef SpotifyPlaylistTrack = ({String title, String artist});
typedef SpotifyPlaylist = ({
  String title,
  List<SpotifyPlaylistTrack> tracks,
  bool mayBeIncomplete,
  int? totalEntries,
});

final _playlistId = RegExp(r'^[a-zA-Z0-9]{22}$');
typedef _PlaylistPreview = ({
  String title,
  List<SpotifyPlaylistTrack> tracks,
  int entryCount,
  int? totalEntries,
});

const _timeout = Duration(seconds: 12);

String? spotifyPlaylistId(String input) {
  final link = input.trim();
  if (link.startsWith('spotify:playlist:')) {
    final id = link.substring('spotify:playlist:'.length);
    return _playlistId.hasMatch(id) ? id : null;
  }

  final uri = Uri.tryParse(link);
  if (uri == null || !_isSpotifyUrl(uri) || uri.host != 'open.spotify.com') {
    return null;
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.length == 3 &&
      (segments.first == 'embed' ||
          RegExp(r'^intl-[a-zA-Z-]+$').hasMatch(segments.first))) {
    segments.removeAt(0);
  }
  if (segments.length != 2 || segments.first != 'playlist') return null;
  return _playlistId.hasMatch(segments.last) ? segments.last : null;
}

bool _isSpotifyUrl(Uri uri) =>
    uri.scheme == 'https' && uri.userInfo.isEmpty && uri.port == 443;

/// Combines the public playlist page's total with the larger available preview.
Future<SpotifyPlaylist> loadSpotifyPlaylist(
  String input, {
  http.Client? client,
}) async {
  final requestClient = client ?? http.Client();
  try {
    var id = spotifyPlaylistId(input);
    var shortLink = Uri.tryParse(input.trim());
    for (var i = 0; id == null && i < 4; i++) {
      final uri = shortLink;
      if (uri == null || !_isSpotifyUrl(uri) || uri.host != 'spotify.link') {
        break;
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await requestClient.send(request).timeout(_timeout);
      final location = response.headers['location'];
      final subscription = response.stream.listen(null);
      await subscription.cancel();
      if (location == null ||
          response.statusCode < 300 ||
          response.statusCode >= 400) {
        break;
      }
      shortLink = uri.resolve(location);
      id = spotifyPlaylistId(shortLink.toString());
    }

    if (id == null)
      throw const FormatException('Invalid Spotify playlist link');
    final previews = await Future.wait([
      _readPreview(requestClient, '/embed/playlist/$id', id, _parseEmbed),
      _readPreview(requestClient, '/playlist/$id', id, _parsePlaylistPage),
    ]);
    final [embed, page] = previews;
    if (embed == null && page == null) throw const SpotifyPlaylistUnavailable();

    final preview = switch ((embed, page)) {
      (final embed?, final page?) when embed.entryCount >= page.entryCount =>
        embed,
      (_, final page?) => page,
      (final embed?, null) => embed,
      _ => throw const SpotifyPlaylistUnavailable(),
    };
    final total = page?.totalEntries;
    return (
      title: preview.title,
      tracks: preview.tracks,
      mayBeIncomplete: total != null
          ? preview.entryCount < total
          : preview.entryCount >= 100,
      totalEntries: total,
    );
  } finally {
    if (client == null) requestClient.close();
  }
}

class SpotifyPlaylistUnavailable implements Exception {
  const SpotifyPlaylistUnavailable();
}

Future<_PlaylistPreview?> _readPreview(
  http.Client client,
  String path,
  String id,
  _PlaylistPreview? Function(String page, String id) parse,
) async {
  try {
    final response = await client
        .get(Uri.https('open.spotify.com', path))
        .timeout(_timeout);
    if (response.statusCode != 200) return null;
    return parse(utf8.decode(response.bodyBytes, allowMalformed: true), id);
  } on Exception {
    return null;
  }
}

Object? _at(Object? data, List<String> keys) {
  for (final key in keys) {
    data = data is Map ? data[key] : null;
  }
  return data;
}

_PlaylistPreview? _parseEmbed(String page, String id) {
  final script = html.parse(page).querySelector('script#__NEXT_DATA__');
  if (script == null) return null;
  final data = _at(jsonDecode(script.text), [
    'props',
    'pageProps',
    'state',
    'data',
    'entity',
  ]);
  if (data is! Map || data['type'] != 'playlist' || data['id'] != id) {
    return null;
  }
  final entries = data['trackList'];
  if (entries is! List) return null;

  return (
    title: _text(data['name'] ?? data['title']),
    tracks: [
      for (final entry in entries.whereType<Map>())
        if (_track(entry['uri'], entry['title'], entry['subtitle'])
            case final track?)
          track,
    ],
    entryCount: entries.length,
    totalEntries: null,
  );
}

_PlaylistPreview? _parsePlaylistPage(String page, String id) {
  final script = html.parse(page).querySelector('script#initialState');
  if (script == null) return null;
  final state = jsonDecode(utf8.decode(base64Decode(script.text.trim())));
  final playlist = _at(state, ['entities', 'items', 'spotify:playlist:$id']);
  final entries = _at(playlist, ['content', 'items']);
  final count = _at(playlist, ['content', 'totalCount']);
  if (playlist is! Map || entries is! List) return null;

  final tracks = <SpotifyPlaylistTrack>[];
  for (final entry in entries) {
    final track = _at(entry, ['itemV2', 'data']);
    if (track is! Map) continue;
    final artists = _at(track, ['artists', 'items']);
    final credit = artists is List
        ? artists
              .map((artist) => _text(_at(artist, ['profile', 'name'])))
              .where((name) => name.isNotEmpty)
              .join(', ')
        : '';
    final item = _track(track['uri'], track['name'], credit);
    if (item != null) tracks.add(item);
  }
  return (
    title: _text(playlist['name']),
    tracks: tracks,
    entryCount: entries.length,
    totalEntries: count is int && count >= entries.length ? count : null,
  );
}

String _text(Object? input) => input is String ? input.trim() : '';

SpotifyPlaylistTrack? _track(Object? uri, Object? name, Object? credit) {
  final title = _text(name);
  final artist = _text(credit);
  if (uri is! String ||
      !uri.startsWith('spotify:track:') ||
      title.isEmpty ||
      artist.isEmpty)
    return null;
  return (title: title, artist: artist);
}
