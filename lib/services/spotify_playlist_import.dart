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
  bool? complete,
});

const _timeout = Duration(seconds: 12);
const _exportTimeout = Duration(seconds: 48);
const _configuredExporter = String.fromEnvironment('SPOTIFY_CSV_EXPORT_URL');

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

/// Reads public previews and, when configured, fills gaps from a CSV exporter.
Future<SpotifyPlaylist> loadSpotifyPlaylist(
  String input, {
  http.Client? client,
  String exporterUrl = _configuredExporter,
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
    final preview = switch ((embed, page)) {
      (final embed?, final page?) when embed.entryCount >= page.entryCount =>
        embed,
      (_, final page?) => page,
      _ => embed,
    };
    final total = page?.totalEntries;
    final needsExport =
        preview == null || total == null || preview.entryCount < total;
    if (needsExport && exporterUrl.isNotEmpty) {
      final exported = await _readCsvExport(requestClient, exporterUrl, id);
      if (exported != null &&
          (preview == null ||
              exported.tracks.length >= preview.tracks.length)) {
        final reportedTotal = exported.totalEntries;
        final expected = total == null || (reportedTotal ?? 0) > total
            ? reportedTotal
            : total;
        return (
          title: exported.title.isEmpty ? preview?.title ?? '' : exported.title,
          tracks: exported.tracks,
          mayBeIncomplete:
              exported.complete == false ||
              expected == null ||
              exported.entryCount < expected,
          totalEntries: expected,
        );
      }
    }
    if (preview == null) throw const SpotifyPlaylistUnavailable();
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

Future<_PlaylistPreview?> _readCsvExport(
  http.Client client,
  String url,
  String playlistId,
) async {
  final endpoint = Uri.tryParse(url);
  if (endpoint == null ||
      !_isSpotifyUrl(endpoint) ||
      endpoint.host.isEmpty ||
      endpoint.hasFragment) {
    return null;
  }

  const maxBytes = 5 * 1024 * 1024;
  final uri = endpoint.replace(
    queryParameters: {...endpoint.queryParameters, 'id': playlistId},
  );
  try {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'text/csv';
    final response = await client.send(request).timeout(_exportTimeout);
    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (response.statusCode != 200 ||
        contentType != 'text/csv' ||
        (response.contentLength ?? 0) > maxBytes) {
      await response.stream.listen(null).cancel();
      return null;
    }

    // Bound both the time and size of the response, including chunked CSV.
    var bytesRead = 0;
    final bytes = await http.ByteStream(
      response.stream.map((chunk) {
        bytesRead += chunk.length;
        if (bytesRead > maxBytes)
          throw const FormatException('CSV export is too large');
        return chunk;
      }),
    ).toBytes().timeout(_timeout);
    final rows = _parseCsv(
      utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), ''),
    );
    if (rows.length < 2) return null;
    final headings = rows.first
        .map((name) => name.toLowerCase().replaceAll(RegExp('[^a-z]'), ''))
        .toList();
    const titleHeadings = {
      'trackname',
      'track',
      'title',
      'songname',
      'song',
      'tracktitle',
      'songtitle',
    };
    const artistHeadings = {
      'artist',
      'artists',
      'artistname',
      'artistnames',
      'trackartist',
      'trackartists',
      'trackartistname',
      'trackartistnames',
    };
    final titleIndex = headings.indexWhere(titleHeadings.contains);
    final artistIndex = headings.indexWhere(artistHeadings.contains);
    if (titleIndex < 0 || artistIndex < 0) return null;

    final tracks = <SpotifyPlaylistTrack>[];
    for (final row in rows.skip(1)) {
      if (row.length <= titleIndex || row.length <= artistIndex) continue;
      final title = row[titleIndex].trim();
      final artist = row[artistIndex].trim();
      if (title.isNotEmpty && artist.isNotEmpty) {
        tracks.add((title: title, artist: artist));
      }
    }
    if (tracks.isEmpty) return null;
    final total = int.tryParse(response.headers['x-playlist-total'] ?? '');
    return (
      title: _exportTitle(response.headers),
      complete: switch (response.headers['x-playlist-complete']) {
        'true' => true,
        'false' => false,
        _ => null,
      },
      tracks: tracks,
      entryCount: tracks.length,
      totalEntries: total != null && total >= tracks.length ? total : null,
    );
  } on Exception {
    return null;
  }
}

String _exportTitle(Map<String, String> headers) {
  final encoded = headers['x-playlist-name-encoded'];
  if (encoded != null) {
    try {
      return Uri.decodeComponent(encoded).trim();
    } on FormatException {
      // Fall back to the unencoded name or the Spotify preview.
    }
  }
  return _text(headers['x-playlist-name']);
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
    complete: null,
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
    complete: null,
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

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;

  for (var index = 0; index < input.length; index++) {
    final character = input[index];
    if (character == '"') {
      if (quoted && index + 1 < input.length && input[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((character == '\n' || character == '\r') && !quoted) {
      if (character == '\r' &&
          index + 1 < input.length &&
          input[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(character);
    }
  }
  if (quoted) throw const FormatException('Unclosed quoted CSV field');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}
