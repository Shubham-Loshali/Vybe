import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/utilities/flutter_toast.dart';

class FollowedArtistsService {
  FollowedArtistsService._internal();
  static final FollowedArtistsService instance = FollowedArtistsService._internal();

  static const String _storageKey = 'followedArtists';

  final ValueNotifier<List<Map<String, dynamic>>> followedArtists =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  bool _initialised = false;

  @visibleForTesting
  void resetForTesting() {
    _initialised = false;
  }

  /// Loads saved followed artists from Hive and seamlessly migrates any legacy
  /// artist entries from [userLikedPlaylists].
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;

    try {
      final userBox = Hive.box('user');
      final saved = userBox.get(_storageKey, defaultValue: <dynamic>[]);

      final list = <Map<String, dynamic>>[];
      final seenIds = <String>{};

      if (saved is List) {
        for (final item in saved) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final id = (map['ytid'] ?? map['id'])?.toString();
            if (id != null && id.isNotEmpty && seenIds.add(id)) {
              list.add(map);
            }
          }
        }
      }

      // Merge any previously liked artist playlists
      for (final p in userLikedPlaylists.value) {
        if (p['source']?.toString() == 'youtube-artist' || isArtistPlaylist(p)) {
          final id = (p['ytid'] ?? p['id'])?.toString();
          if (id != null && id.isNotEmpty && seenIds.add(id)) {
            list.add({
              'ytid': id,
              'id': id,
              'title': p['title']?.toString() ?? 'Unknown Artist',
              'image': p['image']?.toString(),
              'source': 'youtube-artist',
              'followedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      }

      followedArtists.value = list;
    } catch (e, stackTrace) {
      logger.log('FollowedArtistsService.initialise failed', error: e, stackTrace: stackTrace);
    }
  }

  /// Whether an artist is currently followed.
  bool isFollowing(String? artistId) {
    if (artistId == null || artistId.isEmpty) return false;
    final normalized = artistId.trim().toLowerCase();
    return followedArtists.value.any((a) {
      final ytid = (a['ytid'] ?? a['id'])?.toString().trim().toLowerCase();
      final title = a['title']?.toString().trim().toLowerCase();
      return ytid == normalized || title == normalized;
    });
  }

  /// Follows an artist, saving to Hive and synchronizing with CloudSync.
  Future<bool> followArtist(Map<dynamic, dynamic> artistData, {BuildContext? context}) async {
    final rawId = (artistData['ytid'] ?? artistData['id'])?.toString().trim();
    final title = (artistData['title'] ?? artistData['name'])?.toString().trim() ?? 'Artist';
    final image = artistData['image']?.toString();

    if (rawId == null || rawId.isEmpty) return false;

    if (isFollowing(rawId)) return true;

    final entry = <String, dynamic>{
      'ytid': rawId,
      'id': rawId,
      'title': title,
      if (image != null && image.isNotEmpty) 'image': image,
      'source': 'youtube-artist',
      'followedAt': DateTime.now().millisecondsSinceEpoch,
    };

    final updated = [entry, ...followedArtists.value];
    followedArtists.value = updated;

    await _persist();

    // Mirror to liked playlists for backward-compatibility
    unawaited(updatePlaylistLikeStatus(rawId, true, playlistData: entry));

    if (context != null && context.mounted) {
      showToast(context, 'Following $title');
    }

    _triggerCloudSync();
    return true;
  }

  /// Unfollows an artist.
  Future<bool> unfollowArtist(String? artistId, {BuildContext? context, String? artistTitle}) async {
    if (artistId == null || artistId.isEmpty) return false;
    final normalized = artistId.trim().toLowerCase();

    final previous = followedArtists.value;
    final updated = previous.where((a) {
      final ytid = (a['ytid'] ?? a['id'])?.toString().trim().toLowerCase();
      final title = a['title']?.toString().trim().toLowerCase();
      return ytid != normalized && title != normalized;
    }).toList();

    if (updated.length != previous.length) {
      followedArtists.value = updated;
      await _persist();

      // Mirror to liked playlists
      unawaited(updatePlaylistLikeStatus(artistId, false));

      if (context != null && context.mounted) {
        final name = artistTitle ?? 'Artist';
        showToast(context, 'Unfollowed $name');
      }

      _triggerCloudSync();
    }

    return false;
  }

  /// Toggles follow status for an artist.
  Future<bool> toggleFollow(Map<dynamic, dynamic> artistData, {BuildContext? context}) async {
    final rawId = (artistData['ytid'] ?? artistData['id'])?.toString().trim();
    if (rawId == null || rawId.isEmpty) return false;

    if (isFollowing(rawId)) {
      await unfollowArtist(
        rawId,
        context: context,
        artistTitle: artistData['title']?.toString(),
      );
      return false;
    } else {
      await followArtist(artistData, context: context);
      return true;
    }
  }

  /// Returns the current list of followed artists, optionally filtered for offline mode.
  List<Map<String, dynamic>> getFollowedArtists({bool offlineOnly = false}) {
    if (!offlineOnly) return List.unmodifiable(followedArtists.value);

    // In offline mode, only show followed artists who have downloaded songs
    final offlineItems = getLikedArtistItems(offlineOnly: true);
    final offlineIds = offlineItems.map((a) => (a['ytid'] ?? a['id'])?.toString()).toSet();

    return followedArtists.value.where((a) {
      final id = (a['ytid'] ?? a['id'])?.toString();
      return id != null && offlineIds.contains(id);
    }).toList();
  }

  Future<void> _persist() async {
    try {
      final userBox = Hive.box('user');
      await userBox.put(_storageKey, followedArtists.value);
    } catch (e, stackTrace) {
      logger.log('Failed to persist followedArtists', error: e, stackTrace: stackTrace);
    }
  }

  void _triggerCloudSync() {
    if (CloudSyncService.instance.isFirebaseConfigured &&
        CloudSyncService.instance.currentUser.value != null) {
      unawaited(CloudSyncService.instance.syncToCloud());
    }
  }
}
