import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vybe/services/lyrics/youtube_music_lyrics.dart';
import 'package:vybe/services/lyrics_manager.dart';

const playing = TrackInfo(
  title: 'Sitaare Ikkis Agastya Nanda Simar Bhatia Arijit Singh',
  artist: 'Sony Music India',
  videoId: 'nDjloeIB3Pc',
  duration: Duration(seconds: 196),
);

Map<String, dynamic> nextResponse({bool withLyrics = true}) => {
  'contents': {
    'playlistPanelVideoRenderer': {
      'videoId': playing.videoId,
      'title': {
        'runs': [
          {'text': 'Sitaare'},
        ],
      },
      'longBylineText': {
        'runs': [
          {
            'text': 'Arijit Singh',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'UCartist'},
            },
          },
        ],
      },
    },
    'tabs': [
      {
        'tabRenderer': {
          if (withLyrics)
            'endpoint': {
              'browseEndpoint': {'browseId': 'MPLYt_test'},
            },
        },
      },
    ],
  },
};

Map<String, dynamic> lyricsResponse() => {
  'contents': {
    'sectionListRenderer': {
      'contents': [
        {
          'musicDescriptionShelfRenderer': {
            'description': {
              'runs': [
                {'text': 'पहली पंक्ति\n'},
                {'text': 'Second line'},
              ],
            },
            'footer': {
              'runs': [
                {'text': 'Source: LyricFind'},
              ],
            },
          },
        },
      ],
    },
  },
};

void main() {
  setUp(LyricsManager.clearCache);

  test(
    'uses the playing video and preserves Unicode words and credit',
    () async {
      final requests = <String>[];
      final provider = YouTubeMusicLyrics(
        client: MockClient((request) async {
          requests.add(request.url.path);
          final body = jsonDecode(request.body) as Map;
          expect(request.method, 'POST');
          if (request.url.path.endsWith('/next')) {
            expect(body['videoId'], playing.videoId);
            return http.Response(jsonEncode(nextResponse()), 200);
          }
          expect(body['browseId'], 'MPLYt_test');
          return http.Response.bytes(
            utf8.encode(jsonEncode(lyricsResponse())),
            200,
          );
        }),
      );
      final result = (await provider.lookup(playing))!;
      expect(result.track!.title, 'Sitaare');
      expect(result.track!.artist, 'Arijit Singh');
      expect(result.track!.duration, playing.duration);
      expect(result.track!.videoId, playing.videoId);
      expect(result.lyrics!.text, 'पहली पंक्ति\nSecond line');
      expect(result.lyrics!.source, 'YouTube Music · LyricFind');
      expect(result.lyrics!.isSynced, isFalse);
      expect(requests, hasLength(2));
    },
  );

  test('keeps canonical metadata when a video has no lyrics tab', () async {
    final provider = YouTubeMusicLyrics(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode(nextResponse(withLyrics: false)), 200),
      ),
    );
    final result = (await provider.lookup(playing))!;
    expect(result.track!.artist, 'Arijit Singh');
    expect(result.lyrics, isNull);
  });

  test('does not use a recommendation as current song metadata', () async {
    final response = nextResponse(withLyrics: false);
    (response['contents']['playlistPanelVideoRenderer'] as Map)['videoId'] =
        'otherSongId';
    final provider = YouTubeMusicLyrics(
      client: MockClient((_) async => http.Response(jsonEncode(response), 200)),
    );
    expect(await provider.lookup(playing), isNull);
  });

  test(
    'skips invalid identifiers and handles secondary-source failures',
    () async {
      var calls = 0;
      final provider = YouTubeMusicLyrics(
        client: MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      );
      expect(
        await provider.lookup(const TrackInfo(title: 'Song', artist: 'Artist')),
        isNull,
      );
      expect(calls, 0);
      expect(await provider.lookup(playing), isNull);
      expect(calls, 1);
    },
  );

  test(
    'canonical singer and title recover timed lyrics for an upload',
    () async {
      var searchedCanonical = false;
      final manager = LyricsManager(
        client: MockClient((request) async {
          if (request.url.host == 'music.youtube.com') {
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/next')
                    ? nextResponse(withLyrics: false)
                    : lyricsResponse(),
              ),
              200,
            );
          }
          if (request.url.queryParameters['track_name'] == 'Sitaare' &&
              request.url.queryParameters['artist_name'] == 'Arijit Singh') {
            searchedCanonical = true;
            return http.Response(
              jsonEncode([
                {
                  'trackName': 'Sitaare',
                  'artistName': 'Arijit Singh',
                  'duration': 196,
                  'plainLyrics': 'Recovered words',
                  'syncedLyrics': '[00:02]Recovered words',
                },
              ]),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final result = (await manager.fetchLyricsResult(playing))!;
      expect(searchedCanonical, isTrue);
      expect(result.isSynced, isTrue);
      expect(result.source, 'lrclib.net');
    },
  );

  test('retains YouTube words when no timed database record exists', () async {
    final manager = LyricsManager(
      client: MockClient((request) async {
        if (request.url.host == 'music.youtube.com') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(
                request.url.path.endsWith('/next')
                    ? nextResponse()
                    : lyricsResponse(),
              ),
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    final result = (await manager.fetchLyricsResult(playing))!;
    expect(result.text, 'पहली पंक्ति\nSecond line');
    expect(result.source, contains('YouTube Music'));
  });
}
