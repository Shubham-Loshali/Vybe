// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations, deprecated_member_use

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/utilities/map_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_extreme_qa_test_');
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

  group('Extreme QA - Song ID Normalization (map_utils)', () {
    test('songYtid correctly extracts from ytid, id, or both', () {
      expect(songYtid({'ytid': 'abc'}), 'abc');
      expect(songYtid({'id': 'def'}), 'def');
      expect(songYtid({'ytid': 'ghi', 'id': 'jkl'}), 'ghi');
      expect(songYtid({'ytid': '', 'id': 'mno'}), 'mno');
      expect(songYtid({'ytid': null, 'id': 'pqr'}), 'pqr');
      expect(songYtid({'title': 'No ID'}), isNull);
      expect(songYtid({'ytid': '', 'id': ''}), isNull);
    });

    test('findSongByYtid finds songs by either ytid or id', () {
      final list = [
        {'id': 'song_id_1', 'title': 'One'},
        {'ytid': 'song_ytid_2', 'title': 'Two'},
      ];

      expect(findSongByYtid(list, 'song_id_1')?['title'], 'One');
      expect(findSongByYtid(list, 'song_ytid_2')?['title'], 'Two');
      expect(findSongByYtid(list, 'missing'), isNull);
    });
  });

  group('Extreme QA - Common Services Offline & Liked Utilities', () {
    test('isPlaylistFullyOffline evaluates correctly with mixed id/ytid keys', () {
      userOfflineSongs.value = [
        {'id': 'offline_song_1', 'title': 'Song 1'},
        {'ytid': 'offline_song_2', 'title': 'Song 2'},
      ];

      final fullyOfflinePlaylist = [
        {'id': 'offline_song_1'},
        {'ytid': 'offline_song_2'},
      ];
      expect(isPlaylistFullyOffline(fullyOfflinePlaylist), isTrue);

      final partiallyOfflinePlaylist = [
        {'id': 'offline_song_1'},
        {'id': 'online_song_3'},
      ];
      expect(isPlaylistFullyOffline(partiallyOfflinePlaylist), isFalse);

      expect(isPlaylistFullyOffline([]), isFalse);
    });

    test('getOfflineSongByYtid retrieves song with id or ytid', () {
      userOfflineSongs.value = [
        {'id': 'offline_id_only', 'title': 'Song with ID'},
        {'ytid': 'offline_ytid_only', 'title': 'Song with YTID'},
      ];

      expect(getOfflineSongByYtid('offline_id_only')['title'], 'Song with ID');
      expect(getOfflineSongByYtid('offline_ytid_only')['title'], 'Song with YTID');
      expect(getOfflineSongByYtid('unknown'), isEmpty);
    });
  });

  group('Extreme QA - Offline Playlist Service Operations', () {
    test('isPlaylistDownloaded and getOfflinePlaylist identify by id or ytid', () {
      final service = offlinePlaylistService;
      service.offlinePlaylists.value = [
        {
          'id': 'collab_offline_1',
          'title': 'Collab Offline',
          'list': [{'id': 's1'}],
        },
        {
          'ytid': 'regular_offline_2',
          'title': 'Regular Offline',
          'list': [{'ytid': 's2'}],
        },
      ];

      expect(service.isPlaylistDownloaded('collab_offline_1'), isTrue);
      expect(service.isPlaylistDownloaded('regular_offline_2'), isTrue);
      expect(service.isPlaylistDownloaded('non_existent'), isFalse);

      expect(service.getOfflinePlaylist('collab_offline_1')?['title'], 'Collab Offline');
      expect(service.getOfflinePlaylist('regular_offline_2')?['title'], 'Regular Offline');
      expect(service.getOfflinePlaylist('non_existent'), isNull);
    });

    test('auto-mark offline works with mixed song keys', () {
      final service = offlinePlaylistService;
      userOfflineSongs.value = [
        {'id': 'song_a', 'title': 'Song A'},
        {'ytid': 'song_b', 'title': 'Song B'},
      ];

      final playlist = {
        'id': 'auto_mark_pl_1',
        'title': 'Auto Mark',
        'list': [
          {'id': 'song_a'},
          {'ytid': 'song_b'},
        ],
      };

      service.checkAndAutoMarkOffline(playlist);
      expect(service.isPlaylistDownloaded('auto_mark_pl_1'), isTrue);
    });
  });

  group('Extreme QA - 1000 Iteration Stress Test', () {
    test('1000 iterations of fuzzed songs normalization and offline check', () {
      final generatedSongs = <Map<String, dynamic>>[];
      for (var i = 0; i < 1000; i++) {
        final useYtid = i.isEven;
        final key = useYtid ? 'ytid' : 'id';
        generatedSongs.add({
          key: 'fuzz_track_$i',
          'title': 'Fuzz Track $i',
          'artist': 'Artist ${i % 20}',
        });
      }

      userOfflineSongs.value = generatedSongs.take(500).toList();

      for (var i = 0; i < 1000; i++) {
        final song = generatedSongs[i];
        final id = songYtid(song);
        expect(id, 'fuzz_track_$i');

        final isOffline = isSongAlreadyOffline(id);
        if (i < 500) {
          expect(isOffline, isTrue);
        } else {
          expect(isOffline, isFalse);
        }
      }
    });
  });
}
