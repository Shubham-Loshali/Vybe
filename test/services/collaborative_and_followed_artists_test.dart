// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations, deprecated_member_use

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/playlists_manager.dart';

void main() {
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
      final res = await CollaborativePlaylistService.instance.createCollaborativePlaylist(
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

    test('addSong and removeSong in collaborative playlist with collaborator attribution', () async {
      final res = await CollaborativePlaylistService.instance.createCollaborativePlaylist(
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
      final addSuccess = await CollaborativePlaylistService.instance.addSong(playlistId, song);
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
      final removeSuccess = await CollaborativePlaylistService.instance.removeSong(playlistId, 'song_track_101');
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

      final res = await CollaborativePlaylistService.instance.makePlaylistCollaborative(customId);
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
