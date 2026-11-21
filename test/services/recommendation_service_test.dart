import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/recommendation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_rec_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    userRecentlyPlayed.value = [];
    userLikedSongsList.value = [];
  });

  group('RecommendationService - getRecentArtists extraction & normalization', () {
    test('returns empty when no songs played', () {
      final artists = RecommendationService.instance.getRecentArtists();
      expect(artists, isEmpty);
    });

    test('extracts and splits multiple artists across delimiters', () {
      userRecentlyPlayed.value = [
        {
          'ytid': 'song_1',
          'title': 'Gehra Hua',
          'artist': 'Shashwat Sachdev, Arijit Singh, Armaan Malik',
        },
        {
          'ytid': 'song_2',
          'title': 'Industry Baby',
          'artist': 'Lil Nas X feat. Jack Harlow',
        },
        {
          'ytid': 'song_3',
          'title': 'Stay',
          'artist': 'The Kid LAROI & Justin Bieber',
        },
      ];

      final artists = RecommendationService.instance.getRecentArtists();
      expect(artists, contains('Shashwat Sachdev'));
      expect(artists, contains('Arijit Singh'));
      expect(artists, contains('Armaan Malik'));
      expect(artists, contains('Lil Nas X'));
      expect(artists, contains('Jack Harlow'));
      expect(artists, contains('The Kid LAROI'));
    });

    test('deduplicates artists appearing across multiple songs', () {
      userRecentlyPlayed.value = [
        {'ytid': 'song_1', 'title': 'Song 1', 'artist': 'Arijit Singh'},
        {'ytid': 'song_2', 'title': 'Song 2', 'artist': 'Arijit Singh, Mithoon'},
        {'ytid': 'song_3', 'title': 'Song 3', 'artist': 'Arijit Singh'},
      ];

      final artists = RecommendationService.instance.getRecentArtists();
      final arijitCount = artists.where((a) => a == 'Arijit Singh').length;
      expect(arijitCount, 1);
      expect(artists, contains('Mithoon'));
    });

    test('ignores unknown or empty artists', () {
      userRecentlyPlayed.value = [
        {'ytid': 'song_1', 'title': 'Song 1', 'artist': 'Unknown Artist'},
        {'ytid': 'song_2', 'title': 'Song 2', 'artist': ''},
        {'ytid': 'song_3', 'title': 'Song 3', 'artist': 'Adele'},
      ];

      final artists = RecommendationService.instance.getRecentArtists();
      expect(artists, ['Adele']);
    });
  });

  group('RecommendationService - Fallback & Cold Start Safety', () {
    test('getSuggestedArtists does not throw on cold start with empty history', () async {
      userRecentlyPlayed.value = [];
      userLikedSongsList.value = [];

      final artists = await RecommendationService.instance.getSuggestedArtists();
      expect(artists, isA<List<Map<String, dynamic>>>());
    });

    test('getSuggestedPlaylists does not throw on cold start with empty history', () async {
      userRecentlyPlayed.value = [];
      userLikedSongsList.value = [];

      final playlists = await RecommendationService.instance.getSuggestedPlaylists();
      expect(playlists, isA<List<Map<String, dynamic>>>());
    });
  });
}
