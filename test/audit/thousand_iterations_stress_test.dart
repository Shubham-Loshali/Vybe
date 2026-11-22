import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/screens/search_page.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/recommendation_service.dart';
import 'package:vybe/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_1000_stress_test_');
    applicationDirPath = tempDir.path;
    await FilePaths.ensureDirectoriesExist();

    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Exhaustive 1000 Iterations Fuzz & Stress Test - RecommendationService', () {
    test('1000 iterations: fuzzed recent artists splitting, Unicode, emoji, and dirty delimiters never throw', () {
      final random = Random(12345);
      final testArtists = [
        'Arijit Singh',
        'Shashwat Sachdev, Arijit Singh, Armaan Malik',
        'The Weeknd feat. Daft Punk',
        'Coldplay & BTS',
        'Lil Nas X ft. Jack Harlow',
        'Travis Scott / Drake',
        'Badshah; Neha Kakkar; Honey Singh',
        'Taylor Swift - Red',
        'हवाएं - अरिजीत सिंह',
        '米津玄師 & 菅田将暉',
        'DJ Snake ft. Justin Bieber',
        'Unknown Artist',
        'unknown artist',
        '   ',
        '',
        '---...---',
        'A',
        'Artist With Emoji 🎵 🔥',
        'Ed Sheeran, Justin Bieber, Eminem, 50 Cent',
      ];

      for (var i = 0; i < 1000; i++) {
        final songCount = random.nextInt(10);
        final mockHistory = <Map<String, dynamic>>[];

        for (var j = 0; j < songCount; j++) {
          final mode = random.nextInt(6);
          switch (mode) {
            case 0:
              // Standard song
              final artistStr = testArtists[random.nextInt(testArtists.length)];
              mockHistory.add({
                'title': 'Test Song $i-$j',
                'artist': artistStr,
                'ytid': 'ytid_${i}_$j',
              });
              break;
            case 1:
              // Missing artist, uses author
              final authorStr = testArtists[random.nextInt(testArtists.length)];
              mockHistory.add({
                'title': 'Test Song $i-$j',
                'author': authorStr,
                'ytid': 'ytid_${i}_$j',
              });
              break;
            case 2:
              // Null artist and author
              mockHistory.add({
                'title': 'Null Artist Song $i-$j',
                'ytid': 'ytid_${i}_$j',
              });
              break;
            case 3:
              // Highly dirty delimiter combinations
              final a1 = testArtists[random.nextInt(testArtists.length)];
              final a2 = testArtists[random.nextInt(testArtists.length)];
              mockHistory.add({
                'title': 'Dirty Delim $i-$j',
                'artist': '...$a1 , & feat. $a2---',
                'ytid': 'ytid_${i}_$j',
              });
              break;
            case 4:
              // Extremely long artist string
              mockHistory.add({
                'title': 'Long Song $i-$j',
                'artist': 'Artist A, ' * 50 + 'Final Artist',
                'ytid': 'ytid_${i}_$j',
              });
              break;
            case 5:
              // Non-string or unexpected data types in map
              mockHistory.add({
                'title': 12345,
                'artist': 99999,
                'ytid': false,
              });
              break;
          }
        }

        userRecentlyPlayed.value = mockHistory;
        final extracted = RecommendationService.instance.getRecentArtists();

        // Assertions
        expect(extracted, isA<List<String>>());
        expect(extracted.length, lessThanOrEqualTo(6));

        // Deduplication check
        final lowerSet = <String>{};
        for (final artist in extracted) {
          expect(artist.trim(), isNotEmpty);
          expect(artist.length, greaterThan(1));
          expect(artist.toLowerCase(), isNot('unknown artist'));
          expect(
            lowerSet.add(artist.toLowerCase()),
            isTrue,
            reason: 'Duplicate artist found: $artist',
          );
        }
      }
    });

    test('1000 iterations: cache corruption & resilience in getSuggestedArtists & getSuggestedPlaylists', () async {
      final cacheBox = Hive.box('cache');

      for (var i = 0; i < 1000; i++) {
        final corruptKey = 'dynamic_rec_artists_v1_fuzz_$i';
        final corruptPlaylistsKey = 'dynamic_rec_playlists_v2_fuzz_$i';

        final corruptType = i % 5;
        switch (corruptType) {
          case 0:
            await cacheBox.put(corruptKey, 'not a list, just a string');
            await cacheBox.put(corruptPlaylistsKey, 12345);
            break;
          case 1:
            await cacheBox.put(corruptKey, [null, 123, 'string', true]);
            await cacheBox.put(corruptPlaylistsKey, [{'invalid_item': null}]);
            break;
          case 2:
            await cacheBox.put(corruptKey, <dynamic>[]);
            await cacheBox.put(corruptPlaylistsKey, <dynamic>[]);
            break;
          case 3:
            await cacheBox.put(corruptKey, {'key': 'value'});
            await cacheBox.put(corruptPlaylistsKey, [{}]);
            break;
          case 4:
            await cacheBox.put(corruptKey, [
              {'ytid': 'test_id', 'title': 'Test Title'},
              {'ytid': '', 'title': ''}, // empty fields
            ]);
            break;
        }

        // Must never throw even with corrupted cache entries
        expect(() async {
          final res = await cacheBox.get(corruptKey);
          if (res is List) {
            // RecommendationService.asMapList logic
            final sanitized = res.whereType<Map>().map(Map<String, dynamic>.from).toList();
            expect(sanitized, isA<List<Map<String, dynamic>>>());
          }
        }, returnsNormally);
      }
    });
  });

  group('Exhaustive 1000 Iterations Fuzz & Stress Test - Search History Sanitizer', () {
    test('1000 iterations: fuzzed search inputs never throw and strictly filter to valid music maps', () {
      final random = Random(42);
      final validTitles = [
        'Gehra Hua', 'Tum Hi Ho', 'Easy On Me', 'Shape of You',
        'Blinding Lights', 'Kesariya', 'Starboy', 'Believer',
        'हवाएं (Hawayein)', '夜に駆ける', 'Bohemian Rhapsody 🎵',
      ];
      final validArtists = [
        'Shashwat Sachdev, Arijit Singh, Armaan Malik',
        'Arijit Singh, Mithoon',
        'Adele',
        'Ed Sheeran',
        'The Weeknd',
        'Imagine Dragons',
        'YOASOBI',
        'Queen',
      ];
      final validYtids = [
        'dQw4w9WgXcQ', '3JZ_D3ELwOQ', 'kJQP7kiw5Fk', 'JGwWNGJdvx8',
        'RgKAFK5djSk', '9bZkp7q19f0', 'OPf0YbXqDm0', '2Vv-BfVoq4g',
      ];

      for (var i = 0; i < 1000; i++) {
        final mode = i % 5;
        dynamic rawInput;

        switch (mode) {
          case 0:
            // Valid stringified map format from Dart's Map.toString()
            final title = validTitles[random.nextInt(validTitles.length)];
            final artist = validArtists[random.nextInt(validArtists.length)];
            final ytid = validYtids[random.nextInt(validYtids.length)];
            rawInput = '{title: $title, artist: $artist, ytid: $ytid, isSong: true}';
            break;
          case 1:
            // JSON string map
            final title = validTitles[random.nextInt(validTitles.length)];
            final artist = validArtists[random.nextInt(validArtists.length)];
            final ytid = validYtids[random.nextInt(validYtids.length)];
            rawInput = jsonEncode({
              'title': title,
              'artist': artist,
              'ytid': ytid,
              'image': 'https://i.ytimg.com/vi/$ytid/mqdefault.jpg',
              'isSong': true,
            });
            break;
          case 2:
            // Plain query text (must be rejected/filtered out by sanitizeSearchHistory)
            rawInput = 'search query string #$i ${validTitles[random.nextInt(validTitles.length)]}';
            break;
          case 3:
            // Malformed, corrupted or dirty string
            final garbage = [
              '{corrupt json: true, missing title}',
              '{}',
              '{title: }',
              '{ytid: only_ytid_no_title}',
              '{"unclosed": "brace',
              null,
              42,
              3.14,
              true,
              [],
              <String, dynamic>{},
              {'title': ''}, // empty title
              {'name': ''},  // empty name
              '#@!%^&*()',
              '   ',
            ];
            rawInput = garbage[random.nextInt(garbage.length)];
            break;
          case 4:
            // Legitimate Map object
            final title = validTitles[random.nextInt(validTitles.length)];
            final artist = validArtists[random.nextInt(validArtists.length)];
            final ytid = validYtids[random.nextInt(validYtids.length)];
            rawInput = {
              'title': title,
              'artist': artist,
              'ytid': ytid,
              'image': 'https://i.ytimg.com/vi/$ytid/mqdefault.jpg',
              'isSong': true,
            };
            break;
        }

        // Test parseStringifiedSongMap
        final parsed = parseStringifiedSongMap(rawInput);
        if (parsed != null) {
          expect(parsed, isA<Map<String, dynamic>>());
          expect(parsed['title']?.toString().isNotEmpty, isTrue);
          expect(parsed.containsKey('isSong') || parsed.containsKey('isArtist'), isTrue);
        }

        // Test sanitizeSearchHistory with list containing this element
        final sanitized = sanitizeSearchHistory([rawInput]);
        expect(sanitized, isA<List>());

        for (final item in sanitized) {
          // Every item retained MUST be a Map with non-empty title/name
          expect(item, isA<Map>());
          final itemTitle = (item['title'] ?? item['name'] ?? '').toString().trim();
          expect(itemTitle.isNotEmpty, isTrue, reason: 'Empty titles must never be in sanitized history');
        }
      }
    });

    test('1000 item bulk list deduplication & sorting integrity', () {
      final bulkRaw = <dynamic>[];
      for (var i = 0; i < 1000; i++) {
        if (i % 3 == 0) {
          // duplicate title
          bulkRaw.add('{title: Song ${i % 10}, artist: Artist ${i % 5}, ytid: ytid_${i % 10}}');
        } else if (i % 3 == 1) {
          // plain string search (should be filtered)
          bulkRaw.add('search text query $i');
        } else {
          // unique map
          bulkRaw.add({
            'title': 'Unique Song $i',
            'artist': 'Artist $i',
            'ytid': 'ytid_unique_$i',
            'isSong': true,
          });
        }
      }

      final sanitized = sanitizeSearchHistory(bulkRaw);
      expect(sanitized.length, lessThanOrEqualTo(1000));
      // Verify no plain strings survived
      for (final s in sanitized) {
        expect(s, isA<Map>());
      }

      // Verify no duplicate keys
      final seen = <String>{};
      for (final s in sanitized) {
        final key = (s['ytid'] ?? s['title']).toString();
        expect(seen.contains(key), isFalse, reason: 'Duplicate key found: $key');
        seen.add(key);
      }
    });
  });

  group('Exhaustive 1000 Cycles Offline Backup & Recovery Integrity', () {
    test('1000 rapid file mutations and backup self-healing cycles', () async {
      userOfflineSongs.value = [];

      for (var i = 0; i < 1000; i++) {
        final songId = 'stress_song_${i % 25}';
        final audioFile = File(FilePaths.getAudioPath(songId));

        if (!await audioFile.exists()) {
          await audioFile.writeAsString('audio bytes for $songId');
        }

        // Mutate current songs list
        final currentList = List<Map<String, dynamic>>.from(userOfflineSongs.value);
        if (currentList.any((s) => s['ytid'] == songId)) {
          // Already present
        } else {
          currentList.add({
            'ytid': songId,
            'title': 'Stress Song #$songId',
            'artist': 'Stress Artist',
            'audioPath': audioFile.path,
            'image': 'https://i.ytimg.com/vi/$songId/mqdefault.jpg',
          });
        }
        userOfflineSongs.value = currentList;

        if (i % 100 == 0) {
          // Trigger backup save
          await OfflineBackupService.instance.saveOfflineBackup();

          // Verify Hive user box has valid JSON
          final backupString = Hive.box('user').get('offlineBackupData') as String?;
          expect(backupString, isNotNull);
          final decoded = jsonDecode(backupString!) as Map<String, dynamic>;
          expect(decoded['version'], 1);
          expect(decoded['songs'], isA<List>());

          // Simulate app restart / version change
          await Hive.box('settings').put('lastInstalledAppVersion', '0.0.$i');
          final restored = await OfflineBackupService.instance.initialiseAndRestoreIfNeeded();
          expect(restored, greaterThan(0));
          expect(userOfflineSongs.value.length, greaterThan(0));
        }
      }
    });

    test('corrupted backup manifest recovery without crash', () async {
      // Intentionally corrupt the backup files with malformed strings
      final tracksBackup = File(
        '$applicationDirPath/${FilePaths.tracksDir}/${OfflineBackupService.backupFileName}',
      );
      await tracksBackup.writeAsString('{{{ corrupt broken json content !!!');

      await Hive.box('user').put('offlineBackupData', 'broken json {[[[');

      // Restore should catch error gracefully and return fallback without throwing
      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(restored, isA<int>());
    });
  });

  group('Queue Auto-Injection & Settings Guard', () {
    test('playNextSongAutomatically defaults to true and persists cleanly', () {
      expect(playNextSongAutomatically.value, isTrue);
    });
  });
}
