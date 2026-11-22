import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_audit_test_');
    applicationDirPath = tempDir.path;
    await FilePaths.ensureDirectoriesExist();

    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');

    userOfflineSongs.value = [];
    OfflinePlaylistService().offlinePlaylists.value = [];
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Offline Backup & Restore Stress Tests', () {
    test('corrupted/malformed JSON in backup file is handled gracefully without crashing', () async {
      final tracksBackup = File(
        '$applicationDirPath/${FilePaths.tracksDir}/${OfflineBackupService.backupFileName}',
      );
      await tracksBackup.writeAsString('{{not_valid_json!@#\$%^');

      expect(userOfflineSongs.value, isEmpty);
      // Should not throw
      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(restored, 0);
      expect(userOfflineSongs.value, isEmpty);
    });

    test('empty backup file (0 bytes) is handled gracefully', () async {
      final tracksBackup = File(
        '$applicationDirPath/${FilePaths.tracksDir}/${OfflineBackupService.backupFileName}',
      );
      await tracksBackup.writeAsString('');

      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(restored, 0);
      expect(userOfflineSongs.value, isEmpty);
    });

    test('songs with missing fields in backup JSON are handled safely', () async {
      final testAudio = File(FilePaths.getAudioPath('missing_fields_song'));
      await testAudio.writeAsString('audio');

      final backupData = {
        'version': 1,
        'appVersion': '10.6.5',
        'updatedAt': 12345,
        'songs': [
          {
            'ytid': 'missing_fields_song',
            // title, artist, image, etc. are completely omitted!
          },
        ],
        'playlists': [],
      };
      await Hive.box('user').put('offlineBackupData', jsonEncode(backupData));

      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(restored, 1);
      expect(userOfflineSongs.value.first['ytid'], 'missing_fields_song');
    });

    test('backup songs whose audio files no longer exist on disk are skipped', () async {
      final backupData = {
        'version': 1,
        'appVersion': '10.6.5',
        'updatedAt': 12345,
        'songs': [
          {
            'ytid': 'ghost_file_does_not_exist',
            'title': 'Ghost Song',
          },
        ],
        'playlists': [],
      };
      await Hive.box('user').put('offlineBackupData', jsonEncode(backupData));

      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      // Should be 0 because ghost_file_does_not_exist.m4a does not exist on disk
      expect(restored, 0);
      expect(userOfflineSongs.value, isEmpty);
    });

    test('disk scanner fallback recovers .m4a files even if no backup JSON exists', () async {
      // Create audio files directly in tracks directory
      final audio1 = File(FilePaths.getAudioPath('orphan_song_1'));
      await audio1.writeAsString('audio1');
      final audio2 = File(FilePaths.getAudioPath('orphan_song_2'));
      await audio2.writeAsString('audio2');

      // Put metadata for one of them in cache
      await Hive.box('cache').put('song_orphan_song_1', {
        'title': 'Cached Title 1',
        'artist': 'Cached Artist 1',
      });

      // No backup manifest exists anywhere
      expect(userOfflineSongs.value, isEmpty);

      final restored = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(restored, 2);
      expect(userOfflineSongs.value.any((s) => s['ytid'] == 'orphan_song_1'), isTrue);
      expect(userOfflineSongs.value.any((s) => s['ytid'] == 'orphan_song_2'), isTrue);

      final song1 = userOfflineSongs.value.firstWhere((s) => s['ytid'] == 'orphan_song_1');
      expect(song1['title'], 'Cached Title 1');
      expect(song1['artist'], 'Cached Artist 1');
    });

    test('clearAllBackups removes manifest files and Hive backup', () async {
      final testAudio = File(FilePaths.getAudioPath('clear_test_song'));
      await testAudio.writeAsString('data');

      userOfflineSongs.value = [
        {'ytid': 'clear_test_song', 'title': 'Clear Test'},
      ];
      await OfflineBackupService.instance.saveOfflineBackup();

      final manifest = File('$applicationDirPath/${FilePaths.tracksDir}/${OfflineBackupService.backupFileName}');
      expect(await manifest.exists(), isTrue);
      expect(Hive.box('user').get('offlineBackupData'), isNotNull);

      await OfflineBackupService.instance.clearAllBackups();
      expect(await manifest.exists(), isFalse);
      expect(Hive.box('user').get('offlineBackupData'), isNull);
    });

    test('self-healing updates outdated sandbox paths to current active path', () async {
      final validAudio = File(FilePaths.getAudioPath('healed_song'));
      await validAudio.writeAsString('audio');

      userOfflineSongs.value = [
        {
          'ytid': 'healed_song',
          'title': 'Healed Song',
          'audioPath': '/outdated/sandbox/path/tracks/healed_song.m4a',
          'artworkPath': '/outdated/sandbox/path/artworks/healed_song.jpg',
        },
      ];

      await OfflineBackupService.instance.initialiseAndRestoreIfNeeded();

      expect(userOfflineSongs.value.first['audioPath'], validAudio.path);
      expect(userOfflineSongs.value.first['artworkPath'], FilePaths.getArtworkPath('healed_song'));
    });
  });

  group('Settings & Queue Behavior Tests', () {
    test('playNextSongAutomatically defaults to true', () {
      expect(playNextSongAutomatically.value, isTrue);
    });
  });
}
