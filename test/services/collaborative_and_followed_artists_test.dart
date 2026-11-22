// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/playlists_manager.dart';

import '../support/test_account_user.dart';

void main() {
  final collaborative = CollaborativePlaylistService.withPublisher(
    (_, __) async {},
    editSongs: (_, edit) async => edit([]),
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_collab_artists_test_');
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

  group('Followed Artists Service Tests', () {
    test('Initialise, follow, isFollowing, unfollow, and toggle', () async {
      final userBox = Hive.box('user');
      await userBox.put('followedArtists', <dynamic>[]);
      FollowedArtistsService.instance.followedArtists.value = [];

      await FollowedArtistsService.instance.initialise();

      expect(FollowedArtistsService.instance.isFollowing('artist_123'), isFalse);

      // Follow artist
      await FollowedArtistsService.instance.followArtist({
        'ytid': 'artist_123',
        'title': 'Arijit Singh',
        'image': 'https://example.com/arijit.jpg',
      });

      expect(FollowedArtistsService.instance.isFollowing('artist_123'), isTrue);
      expect(FollowedArtistsService.instance.followedArtists.value.length, 1);
      final artist = FollowedArtistsService.instance.followedArtists.value.first;
      expect(artist['title'], 'Arijit Singh');
      expect(artist['ytid'], 'artist_123');
      expect(artist['source'], 'youtube-artist');

      // Check persistence in Hive
      final stored = userBox.get('followedArtists') as List;
      expect(stored.length, 1);
      expect(stored.first['ytid'], 'artist_123');

      // Unfollow
      await FollowedArtistsService.instance.unfollowArtist('artist_123');
      expect(FollowedArtistsService.instance.isFollowing('artist_123'), isFalse);
      expect(FollowedArtistsService.instance.followedArtists.value.isEmpty, isTrue);

      // Toggle follow on
      final followStatusOn = await FollowedArtistsService.instance.toggleFollow({
        'ytid': 'artist_456',
        'title': 'Taylor Swift',
        'image': 'https://example.com/taylor.jpg',
      });
      expect(followStatusOn, isTrue);
      expect(FollowedArtistsService.instance.isFollowing('artist_456'), isTrue);

      // Toggle follow off
      final followStatusOff = await FollowedArtistsService.instance.toggleFollow({
        'ytid': 'artist_456',
        'title': 'Taylor Swift',
        'image': 'https://example.com/taylor.jpg',
      });
      expect(followStatusOff, isFalse);
      expect(FollowedArtistsService.instance.isFollowing('artist_456'), isFalse);
    });

    test('getFollowedArtists returns list and respects offlineMode filter', () async {
      await FollowedArtistsService.instance.followArtist({
        'ytid': 'art_1',
        'title': 'The Weeknd',
        'image': 'https://example.com/theweeknd.jpg',
      });

      final allFollowed = FollowedArtistsService.instance.getFollowedArtists();
      expect(allFollowed.length, 1);
      expect(allFollowed.first['title'], 'The Weeknd');

      // In offlineOnly mode, only artists with local songs appear
      final offlineFollowed = FollowedArtistsService.instance.getFollowedArtists(offlineOnly: true);
      expect(offlineFollowed.isEmpty, isTrue);

      // Cleanup
      await FollowedArtistsService.instance.unfollowArtist('art_1');
    });

    test('Migrate legacy liked playlists with source == youtube-artist', () async {
      FollowedArtistsService.instance.resetForTesting();
      final userBox = Hive.box('user');
      await userBox.put('followedArtists', <dynamic>[]);
      FollowedArtistsService.instance.followedArtists.value = [];

      // Simulate legacy liked playlist
      userLikedPlaylists.value = [
        {
          'ytid': 'legacy_art_99',
          'id': 'legacy_art_99',
          'title': 'Coldplay',
          'image': 'https://example.com/coldplay.jpg',
          'source': 'youtube-artist',
        },
      ];

      await FollowedArtistsService.instance.initialise();

      expect(FollowedArtistsService.instance.isFollowing('legacy_art_99'), isTrue);
      expect(FollowedArtistsService.instance.followedArtists.value.length, 1);
      expect(FollowedArtistsService.instance.followedArtists.value.first['title'], 'Coldplay');

      // Cleanup
      await FollowedArtistsService.instance.unfollowArtist('legacy_art_99');
      userLikedPlaylists.value = [];
    });
  });

  group('Collaborative Playlists Service Tests', () {
    test('a failed invitation leaves a new or converted playlist usable locally', () async {
      final rejecting = CollaborativePlaylistService.withPublisher(
        (_, __) async => throw StateError('Server rejected the invite'),
      );
      final result = await rejecting.createCollaborativePlaylist('Local copy');
      expect(result.success, isFalse);
      expect(result.inviteCode, isNull);
      final local = userCustomPlaylists.value.singleWhere((p) => p['ytid'] == result.playlistId);
      expect(local['title'], 'Local copy');
      expect(local['isCollaborative'], isNot(true));
      final conversion = await rejecting.makePlaylistCollaborative(result.playlistId!);
      expect(conversion.success, isFalse);
      expect(conversion.inviteCode, isNull);
      expect(userCustomPlaylists.value.singleWhere((p) => p['ytid'] == result.playlistId), same(local));

      final retry = await collaborative.makePlaylistCollaborative(result.playlistId!);
      expect(retry.success, isTrue);
      expect(retry.inviteCode, isNotEmpty);
    });

    test('conversion preserves edits and rejects duplicate publish attempts', () async {
      final publishing = Completer<void>();
      final started = Completer<void>();
      final service = CollaborativePlaylistService.withPublisher((_, __) {
        started.complete();
        return publishing.future;
      });
      const id = 'customId-publish-race-qa';
      userCustomPlaylists.value = [
        ...userCustomPlaylists.value,
        {'ytid': id, 'title': 'Original', 'list': <Map>[]},
      ];
      final conversion = service.makePlaylistCollaborative(id);
      await started.future;
      for (var i = 0; i < 10; i++) {
        final duplicate = await service.makePlaylistCollaborative(id);
        expect(duplicate.success, isFalse);
        expect(duplicate.inviteCode, isNull);
      }
      updateStoredCustomPlaylist(id, {'title': 'Renamed during upload'});
      publishing.complete();
      expect((await conversion).success, isFalse);
      final stored = userCustomPlaylists.value.singleWhere((p) => p['ytid'] == id);
      expect(stored['title'], 'Renamed during upload');
      expect(stored['isCollaborative'], isNot(true));
    });
    test('large uploads are resized proportionally for the shared document', () async {
      const width = 640;
      const height = 320;
      final random = Random(7);
      final pixels = Uint8List.fromList(
        List<int>.generate(width * height * 4, (index) =>
            index % 4 == 3 ? 255 : random.nextInt(256)),
      );
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final image = (await codec.getNextFrame()).image;
      addTearDown(() {
        image.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      });
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final uploaded = 'data:image/png;base64,${base64Encode(bytes!.buffer.asUint8List())}';
      expect(uploaded.length, greaterThan(350000));
      final shared = (await CollaborativePlaylistService.prepareSharedArtwork(uploaded))!;
      expect(shared.length, lessThan(uploaded.length));
      final sharedCodec = await ui.instantiateImageCodec(base64Decode(shared.split(',').last));
      final sharedImage = (await sharedCodec.getNextFrame()).image;
      addTearDown(() {
        sharedImage.dispose();
        sharedCodec.dispose();
      });
      expect((sharedImage.width, sharedImage.height), (320, 160));
    });

    test(
      'owner replaces and clears the remote cover without changing songs',
      () async {
        final user = CloudSyncService.instance.currentUser;
        final previous = user.value;
        addTearDown(() => user.value = previous);
        user.value = TestAccountUser(uid: 'test-owner');
        final updates = <Map<String, dynamic>>[];
        final service = CollaborativePlaylistService.withArtworkWriter((
          code,
          change,
        ) async {
          expect(code, 'ABC123');
          updates.add(change);
        });
        final playlist = {'ownerUid': 'test-owner', 'collabId': 'ABC123'};
        const url = 'https://example.com/shared-cover.jpg';
        final changed = await service.updateOwnerArtwork(playlist, url);
        final removed = await service.updateOwnerArtwork(playlist, null);
        expect(changed, (image: url, error: null));
        expect(removed, (image: null, error: null));
        expect(updates, [
          {'image': url},
          {'image': null},
        ]);
        user.value = TestAccountUser(uid: 'another-user');
        expect(
          (await service.updateOwnerArtwork(playlist, url)).error,
          isNotNull,
        );
        expect(updates, hasLength(2));
      },
    );

    test(
      'shared artwork snapshots replace and clear covers stored in folders',
      () async {
        final oldFolders = userPlaylistFolders.value;
        addTearDown(() => userPlaylistFolders.value = oldFolders);
        const id = 'customId-folder-cover';
        final originalSongs = [
          {'ytid': 'song-1'},
          {'ytid': 'song-2'},
        ];
        userPlaylistFolders.value = [
          {
            'id': 'cover-folder',
            'playlists': [
              {'ytid': id, 'image': 'old', 'list': originalSongs},
            ],
          },
        ];
        expect(CollaborativePlaylistService.artworkChanges({}), isEmpty);
        final update = updateStoredCustomPlaylist(
          id,
          CollaborativePlaylistService.artworkChanges({'image': 'new'}),
        );
        expect(update?['image'], 'new');
        expect(update?['list'], originalSongs);
        final cleared = updateStoredCustomPlaylist(
          id,
          CollaborativePlaylistService.artworkChanges({'image': null}),
        );
        expect(cleared?['image'], isNull);
        expect(
          storedCustomPlaylists.singleWhere((p) => p['ytid'] == id),
          cleared,
        );
      },
    );

    test('a guest cannot replace a shared playlist owner’s artwork', () async {
      final result = await CollaborativePlaylistService.instance
          .updateOwnerArtwork({
            'collabId': 'ABC123',
            'ownerUid': 'an-owner',
          }, 'https://example.com/cover.jpg');
      expect(result.error, contains('playlist owner'));
    });

    test('normaliseCode and inviteLink formatting', () {
      expect(CollaborativePlaylistService.normaliseCode('vybe://collab/abc123'), 'ABC123');
      expect(CollaborativePlaylistService.normaliseCode('ABC-123'), 'ABC123');
      expect(CollaborativePlaylistService.normaliseCode('  xy789z  '), 'XY789Z');
      expect(
        CollaborativePlaylistService.inviteLink('ABC123'),
        'vybe://collab/ABC123',
      );
    });

    test('createCollaborativePlaylist sets attributes and adds to userCustomPlaylists', () async {
      final res = await collaborative.createCollaborativePlaylist(
        'Chill Vibes with Friends',
        image: 'https://example.com/cover.jpg',
      );

      expect(res.success, isTrue);
      expect(res.playlistId, isNotNull);
      expect(res.inviteCode, isNotNull);
      expect(res.inviteCode!.length, 6);

      final created = userCustomPlaylists.value.firstWhere(
        (p) => p['ytid'] == res.playlistId,
      );

      expect(created['title'], 'Chill Vibes with Friends');
      expect(created['isCollaborative'], isTrue);
      expect(created['collabId'], res.inviteCode);
      expect(created['inviteCode'], res.inviteCode);
      expect(created['source'], 'user-created');
      expect(created['collaborators'], isNotEmpty);
      expect(created['collaborators'].first['isOwner'], isTrue);
      expect(created['list'], isEmpty);
    });

    test('a guest can retry a failed shared add without losing host songs', () async {
      const guestPlaylistId = 'customId-guest-copy';
      final account = CloudSyncService.instance.currentUser;
      final previousAccount = account.value;
      final previousFolders = userPlaylistFolders.value;
      addTearDown(() {
        account.value = previousAccount;
        userPlaylistFolders.value = previousFolders;
      });
      account.value = TestAccountUser(uid: 'guest', displayName: 'Deepak');
      userPlaylistFolders.value = [
        {
          'playlists': [
            {
              'ytid': guestPlaylistId,
              'collabId': 'ABC123',
              'ownerUid': 'host',
              'isCollaborative': true,
              'list': <Map>[],
            },
          ],
        },
      ];
      var remoteSongs = <Map>[{'ytid': 'host-track'}];
      final firstWrite = Completer<void>();
      final shared = CollaborativePlaylistService.withPublisher(
        (_, __) async {},
        editSongs: (code, edit) async {
          expect(code, 'ABC123');
          await firstWrite.future;
          final result = edit(remoteSongs);
          remoteSongs = result.songs;
          return result;
        },
      );
      List localSongs() => storedCustomPlaylists.singleWhere(
        (playlist) => playlist['ytid'] == guestPlaylistId,
      )['list'] as List;

      final pending = shared.addSongs(guestPlaylistId, [{'id': 'guest-track'}]);
      expect(localSongs(), isEmpty);
      firstWrite.completeError(StateError('Write rejected'));
      expect(await pending, isNull);
      expect(localSongs(), isEmpty);

      final retry = CollaborativePlaylistService.withPublisher(
        (_, __) async {},
        editSongs: (code, edit) async {
          expect(code, 'ABC123');
          final result = edit(remoteSongs);
          remoteSongs = result.songs;
          return result;
        },
      );
      expect(
        await retry.addSongs(guestPlaylistId, [
          {'id': 'guest-track'},
          {'ytid': 'guest-track'},
          {'ytid': 'host-track'},
        ]),
        1,
      );
      expect(
        remoteSongs.map((song) => song['ytid']),
        ['host-track', 'guest-track'],
      );
      expect(remoteSongs.last['addedByUid'], 'guest');
      expect(remoteSongs.last['addedByName'], 'Deepak');
      expect(localSongs().single, remoteSongs.last);
    });

    test('addSong and removeSong in collaborative playlist with collaborator attribution', () async {
      final res = await collaborative.createCollaborativePlaylist(
        'Road Trip Beats',
      );
      final playlistId = res.playlistId!;

      final song = {
        'ytid': 'song_track_101',
        'title': 'Blinding Lights',
        'artist': 'The Weeknd',
        'image': 'https://example.com/blinding.jpg',
      };

      // Add song through CollaborativePlaylistService
      final addSuccess = await collaborative.addSong(playlistId, song);
      expect(addSuccess, isTrue);

      final playlistWithSong = userCustomPlaylists.value.firstWhere(
        (p) => p['ytid'] == playlistId,
      );
      final songList = playlistWithSong['list'] as List;
      expect(songList.length, 1);

      final addedSong = songList.first as Map;
      expect(addedSong['ytid'], 'song_track_101');
      expect(addedSong['addedByName'], isNotNull);
      expect(addedSong['addedAt'], isNotNull);

      // Remove song
      final removeSuccess = await collaborative.removeSong(playlistId, 'song_track_101');
      expect(removeSuccess, isTrue);

      final playlistEmpty = userCustomPlaylists.value.firstWhere(
        (p) => p['ytid'] == playlistId,
      );
      expect((playlistEmpty['list'] as List).isEmpty, isTrue);
    });

    test('makePlaylistCollaborative upgrades an existing normal custom playlist', () async {
      // Create a standard non-collaborative playlist
      final customId = 'customId-test-upgrade-123';
      userCustomPlaylists.value = [
        ...userCustomPlaylists.value,
        {
          'ytid': customId,
          'id': customId,
          'title': 'Workout Mix',
          'source': 'user-created',
          'isCollaborative': false,
          'list': <dynamic>[],
        },
      ];

      final res = await collaborative.makePlaylistCollaborative(customId);
      expect(res.success, isTrue);
      expect(res.inviteCode, isNotNull);
      expect(res.inviteCode!.length, 6);

      final upgraded = userCustomPlaylists.value.firstWhere(
        (p) => p['ytid'] == customId,
      );
      expect(upgraded['isCollaborative'], isTrue);
      expect(upgraded['inviteCode'], res.inviteCode);
      expect(upgraded['collaborators'], isNotEmpty);
    });
  });
}
