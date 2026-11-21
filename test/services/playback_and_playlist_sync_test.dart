// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations, deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/playlist_utils.dart';
import 'package:vybe/utilities/sharing_intent.dart';

class _SharedSongAudioHandler extends Fake implements VybeAudioHandler {
  List<Map>? queuedSongs;
  bool? replacedQueue;

  @override
  Future<void> addPlaylistToQueue(
    List<Map> songs, {
    bool replace = false,
    int? startIndex,
    bool? shuffle,
  }) async {
    queuedSongs = songs;
    replacedQueue = replace;
  }
}

void main() {
  final collaborative = CollaborativePlaylistService.withPublisher(
    (_, __) async {},
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_playback_sync_test_');
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

  test('shared YouTube track starts through the queue playback path', () async {
    final audio = _SharedSongAudioHandler();
    const songId = 'dQw4w9WgXcQ';
    final errors = <Object>[];
    await handleYoutubeSharedTextIntent(
      'https://youtu.be/$songId',
      audioHandler: audio,
      getSong: (_, id) async => {'ytid': id, 'title': 'Shared track'},
      onError: (error, _) => errors.add(error),
    );
    expect(errors, isEmpty);
    expect(audio.queuedSongs, [
      {'ytid': songId, 'title': 'Shared track'},
    ]);
    expect(audio.replacedQueue, isTrue);
  });

  test('an older shared track cannot replace the latest share', () async {
    final audio = _SharedSongAudioHandler();
    final earlierSong = Completer<Map<String, dynamic>>();
    final errors = <Object>[];
    final earlier = handleYoutubeSharedTextIntent(
      'https://youtu.be/dQw4w9WgXcQ',
      audioHandler: audio,
      getSong: (_, _) => earlierSong.future,
      onError: (error, _) => errors.add(error),
    );
    await handleYoutubeSharedTextIntent(
      'https://youtu.be/M7lc1UVf-VE',
      audioHandler: audio,
      getSong: (_, id) async => {'ytid': id},
      onError: (error, _) => errors.add(error),
    );
    earlierSong.complete({'ytid': 'dQw4w9WgXcQ'});
    await earlier;
    expect(errors, isEmpty);
    expect(audio.queuedSongs, [
      {'ytid': 'M7lc1UVf-VE'},
    ]);
  });

  group('Song ID Normalization & Index Resolution Tests', () {
    test('findSongIndexByYtid finds songs with either ytid or id field', () {
      final playlist = {
        'title': 'Test Collab Playlist',
        'list': [
          {'id': 'song_1', 'title': 'First Song'},
          {'ytid': 'song_2', 'title': 'Second Song'},
          {'id': 'song_3', 'ytid': 'song_3', 'title': 'Third Song'},
        ],
      };

      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'song_1'), 0);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'song_2'), 1);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'song_3'), 2);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'non_existent'), -1);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, null), -1);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, ''), -1);
    });

    test('findSongIndexByYtid safely handles corrupted/non-map elements in list', () {
      final playlist = {
        'title': 'Corrupted Playlist',
        'list': [
          null,
          'not_a_map',
          12345,
          {'id': 'valid_song_id', 'title': 'Valid Song'},
        ],
      };

      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'valid_song_id'), 3);
      expect(PlaylistUtils.findSongIndexByYtid(playlist, 'unknown'), -1);
    });

    test('addSong in CollaborativePlaylist preserves and normalizes song fields', () async {
      final res = await collaborative.createCollaborativePlaylist('Collab Sync');
      final playlistId = res.playlistId!;

      final songWithOnlyId = {
        'id': 'yt_track_abc_1',
        'title': 'Song with ID only',
        'artist': 'Artist A',
        'image': 'https://example.com/art.jpg',
      };

      final addResult = await CollaborativePlaylistService.instance.addSong(playlistId, songWithOnlyId);
      expect(addResult, isTrue);

      final playlist = userCustomPlaylists.value.firstWhere(
        (p) => (p['ytid'] ?? p['id']) == playlistId,
      );
      final songs = List<Map>.from(playlist['list'] as List);
      expect(songs.length, 1);

      final song = songs.first;
      expect(song['id'], 'yt_track_abc_1');
      expect(song['addedByName'], isNotNull);
      expect(song['addedAt'], isNotNull);

      final index = PlaylistUtils.findSongIndexByYtid(playlist, 'yt_track_abc_1');
      expect(index, 0);
    });
  });

  group('Downloaded Playlist & Offline Song Fallback Tests', () {
    test('offline mode only opens locally available playlists', () async {
      final oldMode = offlineMode.value;
      final oldPlaylists = onlinePlaylists.value;
      final oldCustom = userCustomPlaylists.value;
      addTearDown(() {
        offlineMode.value = oldMode;
        onlinePlaylists.value = oldPlaylists;
        userCustomPlaylists.value = oldCustom;
      });
      final online = {
        'ytid': 'remote-playlist',
        'title': 'Online metadata',
        'list': [{'ytid': 'remote-track'}],
      };
      final local = {
        'ytid': 'customId-offline-qa',
        'title': 'Personal playlist',
        'list': <Map>[],
      };
      onlinePlaylists.value = [online];
      userCustomPlaylists.value = [local];
      offlineMode.value = false;
      expect(await getPlaylistInfoForWidget('remote-playlist'), same(online));
      offlineMode.value = true;
      expect(await getPlaylistInfoForWidget('remote-playlist'), isNull);
      expect(await getPlaylistInfoForWidget('customId-offline-qa'), local);
    });
    test('Downloaded playlist metadata preserves offline flags and paths', () async {
      final testYtid = 'offline_track_999';
      final testAudio = File(FilePaths.getAudioPath(testYtid));
      await testAudio.writeAsString('mock audio binary data');

      final offlineSong = {
        'ytid': testYtid,
        'title': 'Offline Hit',
        'artist': 'Offline Artist',
        'audioPath': testAudio.path,
        'isOffline': true,
      };

      userOfflineSongs.value = [offlineSong];

      final retrieved = getOfflineSongByYtid(testYtid);
      expect(retrieved, isNotEmpty);
      expect(retrieved['ytid'], testYtid);
      expect(retrieved['audioPath'], testAudio.path);
      expect(File(retrieved['audioPath'].toString()).existsSync(), isTrue);

      // Verify playlist offline detection
      final mockPlaylist = {
        'ytid': 'custom_pl_1',
        'title': 'Offline Collection',
        'list': [offlineSong],
      };
      expect(isPlaylistFullyOffline(mockPlaylist['list'] as List), isTrue);
    });

    test('isPlaylistFullyOffline returns false if any song is not downloaded', () {
      final songs = [
        {'ytid': 'offline_track_999'},
        {'ytid': 'online_only_track_000'},
      ];
      expect(isPlaylistFullyOffline(songs), isFalse);
    });
  });

  group('Rapid Song Switching & Index Robustness Stress Tests', () {
    test('100 iterations of rapid song indexing in large collaborative playlist', () {
      final testSongs = List.generate(100, (i) => {
        if (i.isEven) 'id': 'track_$i' else 'ytid': 'track_$i',
        'title': 'Track #$i',
        'artist': 'Artist ${i % 10}',
      });

      final playlist = {
        'title': '100 Song Collab Playlist',
        'list': testSongs,
      };

      for (var i = 0; i < 100; i++) {
        final targetId = 'track_$i';
        final foundIndex = PlaylistUtils.findSongIndexByYtid(playlist, targetId);
        expect(foundIndex, i);
      }
    });

    test('Duplicate song prevention in collaborative playlist works for both ytid and id', () async {
      final res = await collaborative.createCollaborativePlaylist('Deduplication Test');
      final playlistId = res.playlistId!;

      final song = {
        'id': 'unique_song_777',
        'title': 'Unique Song',
      };

      final firstAdd = await CollaborativePlaylistService.instance.addSong(playlistId, song);
      expect(firstAdd, isTrue);

      // Attempting to add the same song again with 'ytid' instead of 'id'
      final duplicateSongWithYtid = {
        'ytid': 'unique_song_777',
        'title': 'Unique Song',
      };
      final secondAdd = await CollaborativePlaylistService.instance.addSong(playlistId, duplicateSongWithYtid);
      expect(secondAdd, isFalse);

      final playlist = userCustomPlaylists.value.firstWhere(
        (p) => (p['ytid'] ?? p['id']) == playlistId,
      );
      expect((playlist['list'] as List).length, 1);
    });
  });
}
