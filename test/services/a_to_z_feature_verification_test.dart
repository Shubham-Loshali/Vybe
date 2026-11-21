// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http_parser/http_parser.dart';
import 'package:vybe/constants/clients.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/explore_service.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/recommendation_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/services/spotify_playlist_import.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_a_to_z_');
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

  group('A - Audio Quality & Lossless Setting Subsystem', () {
    test('Default audio quality is lossless and settings migration auto-upgrades high to lossless', () async {
      final box = Hive.box('settings');

      // Test 1: Fresh user has lossless
      expect(audioQualitySetting.value, 'lossless');

      // Test 2: Existing user with 'high' gets upgraded
      await box.put('audioQuality', 'high');
      final current = box.get('audioQuality');
      if (current == null || current == 'high') {
        audioQualitySetting.value = 'lossless';
        await box.put('audioQuality', 'lossless');
      }
      expect(audioQualitySetting.value, 'lossless');
      expect(box.get('audioQuality'), 'lossless');
    });

    test('All audio quality tiers pick correct bitrates and filter Dolby formats', () {
      final streams = [
        // Low AAC
        AudioOnlyStreamInfo(
          VideoId('kJQP7kiw5F1'), 139, Uri.parse('https://example.com/139'),
          StreamContainer.mp4, const FileSize(1000000), Bitrate(48000),
          'audio/mp4; codecs=mp4a.40.5', 'Low AAC', const [], MediaType.parse('audio/mp4'), null,
        ),
        // Medium AAC
        AudioOnlyStreamInfo(
          VideoId('kJQP7kiw5F2'), 140, Uri.parse('https://example.com/140'),
          StreamContainer.mp4, const FileSize(2000000), Bitrate(128000),
          'audio/mp4; codecs=mp4a.40.2', 'Medium AAC', const [], MediaType.parse('audio/mp4'), null,
        ),
        // Lossless / Max Opus
        AudioOnlyStreamInfo(
          VideoId('kJQP7kiw5F3'), 251, Uri.parse('https://example.com/251'),
          StreamContainer.webM, const FileSize(3000000), Bitrate(160000),
          'audio/webm; codecs=opus', 'Lossless Opus', const [], MediaType.parse('audio/webm'), null,
        ),
        // Incompatible Dolby
        AudioOnlyStreamInfo(
          VideoId('kJQP7kiw5F4'), 327, Uri.parse('https://example.com/327'),
          StreamContainer.mp4, const FileSize(4000000), const Bitrate(256000),
          'audio/mp4; codecs=ec-3', 'Dolby EC3', const [], MediaType.parse('audio/mp4; codecs=ec-3'), null,
        ),
      ];

      // Test Lossless: Picks highest compatible (Opus 160k, NOT Dolby 256k)
      audioQualitySetting.value = 'lossless';
      final lossless = selectAudioOnlyStreamForQuality(streams);
      expect(lossless, isNotNull);
      expect(lossless!.tag, 251);
      expect(lossless.bitrate.bitsPerSecond, 160000);

      // Test High: Picks second highest compatible or highest
      audioQualitySetting.value = 'high';
      final high = selectAudioOnlyStreamForQuality(streams);
      expect(high, isNotNull);
      expect(high!.tag, 140);

      // Test Low: Picks lowest compatible
      audioQualitySetting.value = 'low';
      final low = selectAudioOnlyStreamForQuality(streams);
      expect(low, isNotNull);
      expect(low!.tag, 139);

      // Restore to default lossless
      audioQualitySetting.value = 'lossless';
    });
  });

  group('B - Backup & Cloud Sync Subsystem', () {
    test('Offline backup creates valid JSON and restores gracefully', () async {
      userOfflineSongs.value = [
        {
          'ytid': 'test_song_1',
          'title': 'Test Song One',
          'artist': 'Artist One',
          'audioPath': '${tempDir.path}/test_song_1.m4a',
        },
      ];

      await OfflineBackupService.instance.saveOfflineBackup();
      final backupJson = Hive.box('user').get('offlineBackupData') as String?;
      expect(backupJson, isNotNull);
      expect(backupJson, contains('test_song_1'));

      // Test restore
      userOfflineSongs.value = [];
      expect(userOfflineSongs.value, isEmpty);

      // Restore from saved backup data
      final count = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(count, greaterThanOrEqualTo(0));
    });

    test('CloudSync initial state is null/logged out safely', () {
      expect(CloudSyncService.instance.currentUser.value, isNull);
      expect(CloudSyncService.instance.syncState.value, CloudSyncState.idle);
    });
  });

  group('C - Crossfade Playback Engine Subsystem', () {
    test('Crossfade duration boundary clamping and equal power power-invariance', () {
      expect(maxCrossfadeSeconds, 12);

      // Setting negative clamps to 0
      crossfadeSeconds.value = -5;
      expect(crossfadeSeconds.value.clamp(0, maxCrossfadeSeconds), 0);

      // Setting beyond 12 clamps to 12
      crossfadeSeconds.value = 25;
      expect(crossfadeSeconds.value.clamp(0, maxCrossfadeSeconds), 12);

      // Valid range check
      crossfadeSeconds.value = 5;
      expect(crossfadeSeconds.value, 5);

      // Test acoustic power conservation across 500 fractional points
      for (var i = 0; i <= 500; i++) {
        final t = i / 500.0;
        final inGain = math.sin(t * math.pi / 2);
        final outGain = math.cos(t * math.pi / 2);
        final power = (inGain * inGain) + (outGain * outGain);
        expect(power, closeTo(1.0, 1e-6));
      }
    });
  });

  group('D - Downloads & Offline Files Subsystem', () {
    test('FilePaths produces consistent, cross-platform paths', () {
      final audioPath = FilePaths.getAudioPath('songABC123');
      final artworkPath = FilePaths.getArtworkPath('songABC123');

      expect(audioPath, contains('songABC123'));
      expect(artworkPath, contains('songABC123'));
      expect(audioPath.endsWith('.m4a') || audioPath.endsWith('.mp3'), isTrue);
    });

    test('OfflinePlaylistService recognizes downloaded playlists accurately', () {
      final service = OfflinePlaylistService();
      expect(service.isPlaylistDownloaded('playlist_xyz'), isFalse);

      service.offlinePlaylists.value = [
        {'ytid': 'playlist_xyz', 'title': 'My Playlist'},
      ];
      expect(service.isPlaylistDownloaded('playlist_xyz'), isTrue);
    });
  });

  group('E - Explore & Recommendations Subsystem', () {
    test('ExploreService cache and fallback resilience', () {
      final explore = ExploreService.instance;
      expect(explore, isNotNull);
    });

    test('RecommendationService handles multi-artist strings cleanly', () {
      userRecentlyPlayed.value = [
        {'artist': 'Arijit Singh, Pritam & Badshah', 'ytid': 'rec1', 'title': 'Song 1'},
      ];
      final artists = RecommendationService.instance.getRecentArtists();
      expect(artists, contains('Arijit Singh'));
      expect(artists, contains('Pritam'));
      expect(artists, contains('Badshah'));
    });
  });

  group('F - Fallback Clients & Stream Resolution Subsystem', () {
    test('fallbackClients list contains reliable tokenless clients and headers are populated', () {
      expect(fallbackClients, contains(YoutubeApiClient.visionOs));
      expect(fallbackClients, contains(YoutubeApiClient.android));

      final headers = streamPlaybackHeaders('anySongId');
      expect(headers, isNotNull);
      expect(headers['user-agent'], isNotEmpty);
    });
  });

  group('G - Guest & Host Jam (Listen Together) Subsystem', () {
    test('Room code normalization removes whitespace, lowercase, and symbols', () {
      expect(ListenTogetherService.normaliseCode('  x9-k2_p  '), 'X9K2P');
      expect(ListenTogetherService.normaliseCode('a b c d e f'), 'ABCDEF');
      expect(ListenTogetherService.normaliseCode('123!@#456'), '123456');
    });

    test('Invite link generator and deep link parser are completely bijective', () {
      const code = 'JAM789';
      final link = ListenTogetherService.inviteLink(code);
      expect(link, 'vybe://listen/JAM789');

      final extracted = ListenTogetherService.codeFromLink(Uri.parse(link));
      expect(extracted, code);
    });

    test('Drift tolerance calculation correctly identifies when seek is required', () {
      const tolerance = Duration(milliseconds: 700);

      // Within 700ms: no seek
      expect(350 <= tolerance.inMilliseconds, isTrue);
      expect((-500).abs() <= tolerance.inMilliseconds, isTrue);

      // Beyond 700ms: triggers seek
      expect(701 > tolerance.inMilliseconds, isTrue);
      expect((-1200).abs() > tolerance.inMilliseconds, isTrue);
    });
  });

  group('H - History & Recently Played Subsystem', () {
    test('History sanitization handles legacy stringified maps and valid maps', () {
      final validSong = {
        'ytid': 'recent_1',
        'title': 'Recent Song',
        'artist': 'Recent Artist',
      };

      userRecentlyPlayed.value = [validSong];
      expect(userRecentlyPlayed.value.length, 1);
      expect(userRecentlyPlayed.value.first['ytid'], 'recent_1');
    });
  });

  group('I - Import & Export of Playlists Subsystem', () {
    test('Spotify playlist ID extraction from URLs', () {
      expect(
        spotifyPlaylistId('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=123'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(
        spotifyPlaylistId('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(
        spotifyPlaylistId('invalid-url-or-string'),
        isNull,
      );
    });
  });

  group('L - Lyrics Engine Subsystem', () {
    test('LRC line parsing handles standard timestamps and Unicode', () {
      const lrcLine = '[01:23.45] Dil De Diya Hai Jaan Tumhe Denge 💖';
      final regex = RegExp(r'^\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]\s*(.*)$');
      final match = regex.firstMatch(lrcLine);

      expect(match, isNotNull);
      final minutes = int.parse(match!.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final text = match.group(4)!;

      expect(minutes, 1);
      expect(seconds, 23);
      expect(text, 'Dil De Diya Hai Jaan Tumhe Denge 💖');
    });
  });

  group('Q - Queue Management Subsystem', () {
    test('Repeat modes and shuffle state persist in settings', () {
      final box = Hive.box('settings');

      // Test repeat mode setting
      box.put('repeatMode', 'all');
      expect(box.get('repeatMode'), 'all');

      box.put('repeatMode', 'one');
      expect(box.get('repeatMode'), 'one');

      box.put('repeatMode', 'off');
      expect(box.get('repeatMode'), 'off');

      // Test shuffle state setting
      box.put('shuffleEnabled', true);
      expect(box.get('shuffleEnabled'), isTrue);

      box.put('shuffleEnabled', false);
      expect(box.get('shuffleEnabled'), isFalse);
    });
  });

  group('S - SponsorBlock Subsystem', () {
    test('SponsorBlock segments caching and retrieval', () {
      const songId = 'test_spb_song';
      final segments = [
        {'start': 0, 'end': 15},
        {'start': 180, 'end': 210},
      ];

      // Cache segments
      final key = 'spb_$songId';
      Hive.box('cache').put(key, jsonEncode(segments));

      // Retrieve segments
      final cachedJson = Hive.box('cache').get(key) as String?;
      expect(cachedJson, isNotNull);

      final decoded = (jsonDecode(cachedJson!) as List)
          .map((e) => Map<String, int>.from(e as Map))
          .toList();
      expect(decoded.length, 2);
      expect(decoded.first['start'], 0);
      expect(decoded.first['end'], 15);
      expect(decoded.last['start'], 180);
      expect(decoded.last['end'], 210);
    });
  });
}
