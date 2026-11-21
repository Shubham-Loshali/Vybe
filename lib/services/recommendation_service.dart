import 'dart:async';

import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/artist_service.dart';
import 'package:vybe/services/common_services.dart' as common_services;
import 'package:vybe/services/common_services.dart'
    show userLikedSongsList, userRecentlyPlayed;
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/explore_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/utilities/app_utils.dart';

class RecommendationService {
  RecommendationService._internal();
  static final RecommendationService instance =
      RecommendationService._internal();

  /// Extracts recently listened unique artist names in recency order.
  List<String> getRecentArtists({int limit = 6}) {
    final seedPool = userRecentlyPlayed.value.isNotEmpty
        ? userRecentlyPlayed.value
        : userLikedSongsList.value;

    final artists = <String>[];
    final seen = <String>{};

    for (final song in seedPool.whereType<Map>()) {
      final raw = (song['artist'] ?? song['author'])?.toString().trim() ?? '';
      if (raw.isEmpty || raw.toLowerCase() == 'unknown artist') continue;

      // Handle songs with multiple artists separated by commas, &, feat, ft
      final split = raw.split(
        RegExp(r',|\s+(?:feat\.?|ft\.?)\s+|&|/|;', caseSensitive: false),
      );
      for (final part in split) {
        final clean = part
            .trim()
            .replaceAll(RegExp(r'^[\s\.\-]+|[\s\.\-]+$'), '')
            .trim();
        if (clean.length > 1 &&
            clean.toLowerCase() != 'unknown artist' &&
            seen.add(clean.toLowerCase())) {
          artists.add(clean);
          if (artists.length >= limit) return artists;
        }
      }
    }

    return artists;
  }

  /// Dynamically suggests artists similar to the user's recently played music.
  /// E.g. If listening to Arijit Singh -> suggests Arijit Singh, Vishal Mishra, Atif Aslam, etc.
  /// If listening to English music -> suggests related English artists.
  /// Falls back to trending artists if no history is present (cold start).
  Future<List<Map<String, dynamic>>> getSuggestedArtists({
    bool forceRefresh = false,
  }) async {
    try {
      final recentArtists = getRecentArtists(limit: 3);

      if (recentArtists.isNotEmpty) {
        final primaryArtist = recentArtists.first;
        final cacheKey =
            'dynamic_rec_artists_v1_${primaryArtist.toLowerCase()}';

        if (!forceRefresh) {
          final cached = await getData(
            'cache',
            cacheKey,
            cachingDuration: const Duration(hours: 6),
          );
          if (cached is List && cached.isNotEmpty) {
            return asMapList(cached);
          }
        }

        final dynamicArtists = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        void addArtistItem(Map? artist) {
          if (artist == null) return;
          final id = artist['ytid']?.toString().trim() ?? '';
          final title = artist['title']?.toString().trim() ?? '';
          if (id.isNotEmpty && title.isNotEmpty && seenIds.add(id)) {
            dynamicArtists.add({
              'ytid': id,
              'title': title,
              'image': artist['image']?.toString(),
              'source': 'youtube-artist',
              'isArtist': true,
              'list': [],
            });
          }
        }

        // 1. Fetch profile of the primary recent artist to get related artists
        for (final artistName in recentArtists.take(2)) {
          try {
            final profile = await getArtistProfile(
              artistName,
              forceRefresh: forceRefresh,
            );
            if (profile != null) {
              // Add the artist themselves
              addArtistItem({
                'ytid': profile['ytid'],
                'title': profile['title'],
                'image': profile['image'],
              });

              // Add all related artists
              final related = asMapList(profile['relatedArtists']);
              for (final rel in related) {
                addArtistItem(rel);
              }
            }
          } catch (e) {
            logger.log(
              'Error getting profile for recommended artist $artistName: $e',
            );
          }
        }

        if (dynamicArtists.isNotEmpty) {
          unawaited(
            addOrUpdateData<List>('cache', cacheKey, dynamicArtists),
          );
          return dynamicArtists;
        }
      }
    } catch (e, st) {
      logger.log(
        'Error in getSuggestedArtists dynamic resolution',
        error: e,
        stackTrace: st,
      );
    }

    // Fallback for cold start or when offline
    return ExploreService.instance.fetchTrendingArtists(
      forceRefresh: forceRefresh,
    );
  }

  /// Dynamically suggests playlists tailored to the user's listened artists and genres.
  /// (e.g. "${Artist} Hits", "${Artist} Mix", explore charts, and regional playlists).
  Future<List<Map<String, dynamic>>> getSuggestedPlaylists({
    bool forceRefresh = false,
  }) async {
    try {
      final recentArtists = getRecentArtists(limit: 3);

      if (recentArtists.isNotEmpty) {
        final primaryArtist = recentArtists.first;
        final cacheKey =
            'dynamic_rec_playlists_v2_${primaryArtist.toLowerCase()}';

        if (!forceRefresh) {
          final cached = await getData(
            'cache',
            cacheKey,
            cachingDuration: const Duration(hours: 6),
          );
          if (cached is List && cached.isNotEmpty) {
            return asMapList(cached);
          }
        }

        final dynamicPlaylists = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        void addPlaylistItem(Map? playlist) {
          if (playlist == null) return;
          final id = playlist['ytid']?.toString().trim() ?? '';
          final title = playlist['title']?.toString().trim() ?? '';
          if (id.isNotEmpty && title.isNotEmpty && seenIds.add(id)) {
            dynamicPlaylists.add(Map<String, dynamic>.from(playlist));
          }
        }

        // 1. Search YouTube for artist mix & hits playlists
        for (final artist in recentArtists.take(2)) {
          try {
            final artistMixes = await getPlaylists(
              query: '$artist Mix',
              playlistsNum: 4,
            );
            for (final item in artistMixes) {
              if (item is Map) addPlaylistItem(item);
            }
          } catch (_) {}

          try {
            final artistBest = await getPlaylists(
              query: '$artist Best Songs',
              playlistsNum: 3,
            );
            for (final item in artistBest) {
              if (item is Map) addPlaylistItem(item);
            }
          } catch (_) {}
        }

        // 2. Add top releases/albums from the primary artist profile
        try {
          final profile = await getArtistProfile(
            primaryArtist,
            forceRefresh: forceRefresh,
          );
          if (profile != null) {
            final releases = asMapList(profile['releases']);
            for (final rel in releases.take(3)) {
              addPlaylistItem({
                'ytid': rel['ytid'],
                'title': rel['title'],
                'image': rel['image'],
                'isAlbum': true,
                'source': 'youtube',
              });
            }
          }
        } catch (_) {}

        // 3. Blend in Explore charts
        try {
          final exploreCharts = await ExploreService.instance
              .fetchExplorePlaylists(forceRefresh: forceRefresh);
          for (final item in exploreCharts.take(4)) {
            addPlaylistItem(item);
          }
        } catch (_) {}

        if (dynamicPlaylists.isNotEmpty) {
          unawaited(
            addOrUpdateData<List>('cache', cacheKey, dynamicPlaylists),
          );
          return dynamicPlaylists;
        }
      }
    } catch (e, st) {
      logger.log(
        'Error in getSuggestedPlaylists dynamic resolution',
        error: e,
        stackTrace: st,
      );
    }

    // Cold start fallback: explore playlists, with static database fallback
    final explore = await ExploreService.instance.fetchExplorePlaylists(
      forceRefresh: forceRefresh,
    );
    if (explore.isNotEmpty) return explore;

    final fallback = await getPlaylists(playlistsNum: recommendedCubesNumber);
    return asMapList(fallback);
  }

  /// Delegates to the recency-weighted recommended songs provider.
  Future<List> getRecommendedSongs() async {
    return common_services.getRecommendedSongs();
  }
}
