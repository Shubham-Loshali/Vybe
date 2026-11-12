import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vybe/services/lyrics/lrc_parser.dart';
import 'package:vybe/services/lyrics/lyrics_query.dart';
import 'package:vybe/services/lyrics_manager.dart';

Map<String, dynamic> record({
  String title = 'Dekh Lena',
  String artist = 'Arijit Singh',
  int duration = 281,
  String? synced = '[00:02.00]First line\n[00:05.00]Second line',
  String? plain = 'First line\nSecond line',
}) => {
  'trackName': title,
  'artistName': artist,
  'duration': duration,
  'plainLyrics': plain,
  'syncedLyrics': synced,
  'instrumental': false,
};

void main() {
  setUp(LyricsManager.clearCache);
  const track = TrackInfo(
    title: 'Dekh Lena',
    artist: 'Arijit Singh',
    duration: Duration(seconds: 281),
  );

  test(
    'parses late file-wide offsets and preserves Hindi and repeated timestamps',
    () {
      final lines = parseLrc(
        '[00:03.50]पहली पंक्ति\n[00:03.50]Translation\n'
        '[00:06][00:09]Repeat\n[offset:+500]',
      );
      expect(lines.first.start, const Duration(seconds: 3));
      expect(lines.first.text, 'पहली पंक्ति\nTranslation');
      expect(lines.map((l) => l.start.inMilliseconds), [3000, 5500, 8500]);
    },
  );

  test('supports BOM, CR line endings and enhanced LRC tags', () {
    final lines = parseLrc('\ufeff[00:01.5]<00:01.5>Hello\r[00:02.050]World');
    expect(lines.map((l) => l.text), ['Hello', 'World']);
    expect(lines.last.start.inMilliseconds, 2050);
  });

  test(
    'active lookup handles pre-roll, exact boundaries and backwards seeking',
    () {
      final lyrics = Lyrics(
        source: 'test',
        synced: parseLrc('[00:02]One\n[00:05]Two'),
      );
      expect(lyrics.lineIndexAt(Duration.zero), -1);
      expect(lyrics.lineIndexAt(const Duration(seconds: 5)), 1);
      expect(lyrics.lineIndexAt(const Duration(seconds: 3)), 0);
    },
  );

  test('offline cache round-trip keeps timestamps and Unicode', () {
    final lyrics = Lyrics(
      source: 'test',
      synced: parseLrc('[00:02]हिन्दी\n[00:03]日本語'),
    );
    final saved = Lyrics.fromJson(jsonDecode(jsonEncode(lyrics.toJson())))!;
    expect(saved.text, lyrics.text);
    expect(saved.lineIndexAt(const Duration(seconds: 3)), 1);
    expect(
      Lyrics.fromJson({
        'source': 'test',
        'synced': [
          {'start': 'bad'},
        ],
      }),
      isNull,
    );
    expect(Lyrics.fromJson({'source': 'test'}), isNull);
  });

  test('cleans video metadata and retains version distinctions', () {
    expect(
      cleanTitle('Dekh Lena (From "Tum Bin 2") [Official Video]'),
      'Dekh Lena',
    );
    expect(cleanTitle('Dekh Lena Full Video Song'), 'Dekh Lena');
    expect(
      cleanTitle('Dekh Lena Full Video Song Tum Bin 2 Arijit Singh'),
      'Dekh Lena',
    );
    expect(
      cleanTitle('O Saathi Lyrical Video Baaghi 2 Tiger Shroff'),
      'O Saathi',
    );
    expect(cleanTitle('O Saathi From "Baaghi 2"'), 'O Saathi');
    expect(cleanTitle('Dekh Lena (Live)'), 'Dekh Lena (Live)');
    expect(cleanArtist('Arijit Singh - Topic'), 'Arijit Singh');
    expect(cleanArtist('Unknown Artist'), isEmpty);
  });

  test('finds the song after a movie or upload prefix', () {
    final variants = buildSearchVariants(
      const TrackInfo(
        title: 'Full Song: Kaise Hua Kabir Singh',
        artist: 'T-Series',
      ),
    );
    expect(variants.map((v) => v.title), contains('Kaise Hua Kabir Singh'));
  });

  test('searches collaborators and title-only tracks', () {
    final variants = buildSearchVariants(
      const TrackInfo(title: 'Song', artist: 'Singer A, Singer B & Singer C'),
    );
    expect(
      variants.map((v) => v.artist),
      containsAll(['Singer A', 'Singer B', 'Singer C']),
    );
    expect(
      buildSearchVariants(const TrackInfo(title: 'Song', artist: ''))
          .first
          .title,
      'Song',
    );
  });

  test('rejects one shared title word and unrelated live versions', () {
    expect(selectBestLrclibMatch([record(title: 'Lena')], track), isNull);
    expect(
      selectBestLrclibMatch([record(title: 'Dekh Lena (Live)')], track),
      isNull,
    );
  });

  test('prefers the matching recording over a timed cover', () {
    final exact = record(synced: null);
    expect(
      selectBestLrclibMatch([
        record(artist: 'Cover Singer', duration: 279),
        exact,
      ], track),
      same(exact),
    );
  });

  test('fetches exact lyrics and shares concurrent lookups', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final manager = LyricsManager(
      client: MockClient((request) {
        requests++;
        expect(request.url.path, '/api/get');
        return response.future;
      }),
    );
    final first = manager.fetchLyricsResult(track);
    final second = manager.fetchLyricsResult(track);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    response.complete(http.Response(jsonEncode(record()), 200));
    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results.first!.isSynced, isTrue);
    expect(results.first, same(results.last));
    await manager.fetchLyricsResult(track);
    expect(requests, 1);
  });

  test('keeps searching for synced lyrics after a plain-only result', () async {
    final manager = LyricsManager(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path == '/api/get' ? record(synced: null) : [record()],
          ),
          200,
        ),
      ),
    );
    expect((await manager.fetchLyricsResult(track))!.isSynced, isTrue);
  });

  test(
    'broadens an irrelevant structured result to a title-only search',
    () async {
      var broadSearch = false;
      final manager = LyricsManager(
        client: MockClient((request) async {
          if (request.url.path == '/api/get') return http.Response('{}', 404);
          if (!request.url.queryParameters.containsKey('artist_name')) {
            broadSearch = true;
            return http.Response(jsonEncode([record()]), 200);
          }
          return http.Response(
            jsonEncode([record(title: 'Unrelated Song')]),
            200,
          );
        }),
      );
      expect((await manager.fetchLyricsResult(track))!.isSynced, isTrue);
      expect(broadSearch, isTrue);
    },
  );

  test('can find lyrics with no artist metadata', () async {
    final manager = LyricsManager(
      client: MockClient((request) async {
        expect(request.url.queryParameters.containsKey('artist_name'), isFalse);
        return http.Response(jsonEncode([record()]), 200);
      }),
    );
    expect(
      (await manager.fetchLyricsResult(track.copyWith(artist: '')))!.isSynced,
      isTrue,
    );
  });

  test(
    'different-length recordings use plain lyrics instead of a wrong timeline',
    () async {
      final manager = LyricsManager(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path == '/api/get'
                  ? record(duration: 220)
                  : [record(duration: 220)],
            ),
            200,
          ),
        ),
      );
      final result = (await manager.fetchLyricsResult(track))!;
      expect(result.isSynced, isFalse);
      expect(result.text, contains('First line'));
    },
  );

  test(
    'uses a longer video match as plain lyrics when the title is unique',
    () async {
      final upload = track.copyWith(artist: 'T-Series');
      final studio = record(duration: 251);
      expect(selectBestLrclibMatch([studio], upload), same(studio));
      expect(
        selectBestLrclibMatch([
          studio,
          record(artist: 'Another singer', duration: 254),
        ], upload),
        isNull,
      );
      final manager = LyricsManager(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(request.url.path == '/api/get' ? studio : [studio]),
            200,
          ),
        ),
      );
      final result = await manager.fetchLyricsResult(upload);
      expect(result?.text, 'First line\nSecond line');
      expect(result?.isSynced, isFalse);
    },
  );

  test('retry bypasses a cached miss', () async {
    var available = false;
    var requests = 0;
    final manager = LyricsManager(
      client: MockClient((request) async {
        requests++;
        if (available && request.url.host == 'lrclib.net') {
          return http.Response(jsonEncode(record()), 200);
        }
        return http.Response('[]', 404);
      }),
    );
    expect(await manager.fetchLyricsResult(track), isNull);
    final afterMiss = requests;
    available = true;
    expect(await manager.fetchLyricsResult(track), isNull);
    expect(requests, afterMiss);
    expect(
      (await manager.fetchLyricsResult(track, forceRefresh: true))!.isSynced,
      isTrue,
    );
  });

  test(
    'fast fallback is not held up by a slow higher-priority source',
    () async {
      final slow = Completer<http.Response>();
      final manager = LyricsManager(
        client: MockClient((request) async {
          if (request.url.host == 'api.lyrics.ovh') return slow.future;
          if (request.url.host == 'www.lyricsmania.com') {
            return http.Response(
              '<div class="lyrics-body">Fallback words</div>',
              200,
            );
          }
          return http.Response('[]', 404);
        }),
      );
      try {
        final result = await manager
            .fetchLyricsResult(track)
            .timeout(const Duration(seconds: 3));
        expect(result!.text, 'Fallback words');
      } finally {
        slow.complete(http.Response('{}', 404));
      }
    },
  );

  // Last: the global provider cooldown intentionally survives cache clearing.
  test('honors rate limits without hammering the provider on retry', () async {
    var lrclibRequests = 0;
    final manager = LyricsManager(
      client: MockClient((request) async {
        if (request.url.host == 'lrclib.net') {
          lrclibRequests++;
          return http.Response('{}', 429, headers: {'retry-after': '60'});
        }
        return http.Response('[]', 404);
      }),
    );
    expect(await manager.fetchLyricsResult(track), isNull);
    expect(await manager.fetchLyricsResult(track, forceRefresh: true), isNull);
    expect(lrclibRequests, 1);
  });
}
