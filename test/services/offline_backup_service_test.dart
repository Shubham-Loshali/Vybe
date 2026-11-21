import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/offline_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_backup_test_');
    applicationDirPath = tempDir.path;
    await FilePaths.ensureDirectoriesExist();

    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');

    userOfflineSongs.value = [];
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saving offline backup writes backup manifest file', () async {
    final testAudio = File(FilePaths.getAudioPath('test_song_1'));
    await testAudio.writeAsString('audio content');

    userOfflineSongs.value = [
      {
        'ytid': 'test_song_1',
        'title': 'Test Song',
        'artist': 'Test Artist',
        'audioPath': testAudio.path,
      },
    ];

    await OfflineBackupService.instance.saveOfflineBackup();

    final manifest = File(
      '$applicationDirPath/${FilePaths.tracksDir}/${OfflineBackupService.backupFileName}',
    );
    expect(await manifest.exists(), isTrue);

    final hiveBackup = Hive.box('user').get('offlineBackupData');
    expect(hiveBackup, isNotNull);
    expect(hiveBackup.toString(), contains('test_song_1'));
  });

  test('restoring offline backup recovers songs when files exist on disk', () async {
    // 1. Create a dummy audio file on disk
    final testAudio = File(FilePaths.getAudioPath('test_song_restore'));
    await testAudio.writeAsString('audio content');

    // 2. Put backup data in user box as if previous version saved it
    const backupJson = '''
    {
      "version": 1,
      "appVersion": "10.6.4",
      "updatedAt": 1000000,
      "songs": [
        {
          "ytid": "test_song_restore",
          "title": "Recovered Song",
          "artist": "Recovered Artist",
          "audioPath": "/old/path/tracks/test_song_restore.m4a"
        }
      ],
      "playlists": []
    }
    ''';
    await Hive.box('user').put('offlineBackupData', backupJson);

    // 3. userOfflineSongs is currently empty (as after update)
    expect(userOfflineSongs.value, isEmpty);

    // 4. Run restore
    final restoredCount = await OfflineBackupService.instance.restoreOfflineBackup();
    expect(restoredCount, 1);
    expect(userOfflineSongs.value.length, 1);
    expect(userOfflineSongs.value.first['title'], 'Recovered Song');
    expect(userOfflineSongs.value.first['audioPath'], testAudio.path);
  });
}
