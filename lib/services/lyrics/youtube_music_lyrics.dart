import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vybe/services/lyrics/lyrics_models.dart';

class YouTubeLyricsResult {
  const YouTubeLyricsResult({this.track, this.lyrics});

  final TrackInfo? track;
  final Lyrics? lyrics;
}

/// Looks up the playing video itself, so label names and video headlines do
/// not have to match a lyrics database's artist/title fields.
class YouTubeMusicLyrics {
  const YouTubeMusicLyrics({this.client});

  final http.Client? client;

  static const _context = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240101.01.00',
      'hl': 'en',
    },
  };

  Future<YouTubeLyricsResult?> lookup(TrackInfo playing) async {
    final id = playing.videoId;
    if (id == null || !RegExp(r'^[\w-]{11}$').hasMatch(id)) return null;
    TrackInfo? canonical;
    try {
      final next = await _post('next', {
        'videoId': id,
        'playlistId': 'RDAMVM$id',
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
      });
      // Only use the requested item; adjacent recommendations are different
      // songs and must never supply the current song's metadata.
      for (final item in _renderers(next, 'playlistPanelVideoRenderer')) {
        if (item['videoId'] != id) continue;
        final title = _text(item['title']);
        final artists = <String>[];
        final byline = item['longBylineText'];
        if (byline is Map && byline['runs'] is List) {
          for (final run in byline['runs'] as List) {
            if (run is! Map) continue;
            final endpoint = run['navigationEndpoint'];
            final browse = endpoint is Map ? endpoint['browseEndpoint'] : null;
            if (browse is Map &&
                browse['browseId'] is String &&
                (browse['browseId'] as String).startsWith('UC')) {
              final name = run['text'];
              if (name is String && name.trim().isNotEmpty) artists.add(name);
            }
          }
        }
        if (title.isNotEmpty && artists.isNotEmpty) {
          canonical = playing.copyWith(
            title: title,
            artist: artists.join(', '),
          );
        }
        break;
      }

      String? browseId;
      for (final tab in _renderers(next, 'tabRenderer')) {
        if (tab['unselectable'] == true) continue;
        final endpoint = tab['endpoint'];
        final browse = endpoint is Map ? endpoint['browseEndpoint'] : null;
        final id = browse is Map ? browse['browseId'] : null;
        if (id is String && id.startsWith('MPLY')) {
          browseId = id;
          break;
        }
      }
      if (browseId != null) {
        final response = await _post('browse', {'browseId': browseId});
        for (final shelf in _renderers(
          response,
          'musicDescriptionShelfRenderer',
        )) {
          final text = _text(shelf['description']).trim();
          if (text.isEmpty) continue;
          final credit = _text(shelf['footer'])
              .replaceFirst(RegExp(r'^Source:\s*', caseSensitive: false), '')
              .trim();
          return YouTubeLyricsResult(
            track: canonical,
            lyrics: Lyrics(
              source: credit.isEmpty
                  ? 'YouTube Music'
                  : 'YouTube Music · $credit',
              plain: text,
            ),
          );
        }
      }
    } catch (_) {
      // A failed secondary source must not discard primary-provider results.
    }
    return canonical == null ? null : YouTubeLyricsResult(track: canonical);
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    final requestClient = client ?? http.Client();
    try {
      final response = await requestClient
          .post(
            Uri.https('music.youtube.com', '/youtubei/v1/$endpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
              'User-Agent': 'Mozilla/5.0',
              'X-Youtube-Client-Name': '67',
              'X-Youtube-Client-Version': '1.20240101.01.00',
            },
            body: jsonEncode({'context': _context, ...body}),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    } finally {
      if (client == null) requestClient.close();
    }
  }

  static String _text(dynamic value) {
    if (value is! Map) return '';
    if (value['simpleText'] is String) return value['simpleText'];
    final runs = value['runs'];
    if (runs is! List) return '';
    return runs.whereType<Map>().map((r) => r['text'] ?? '').join();
  }

  static Iterable<Map> _renderers(dynamic value, String key) sync* {
    if (value is Map) {
      if (value[key] is Map) yield value[key] as Map;
      for (final child in value.values) {
        yield* _renderers(child, key);
      }
    } else if (value is List) {
      for (final child in value) {
        yield* _renderers(child, key);
      }
    }
  }
}
