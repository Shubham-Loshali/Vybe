// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/utilities/flutter_toast.dart';

class OfflinePlaylistService {
  factory OfflinePlaylistService() => _instance;
  OfflinePlaylistService._internal();
  static final OfflinePlaylistService _instance =
      OfflinePlaylistService._internal();

  // Playlist download state notifiers
  final Map<String, ValueNotifier<DownloadProgress>> downloadProgressNotifiers =
      {};
  final List<String> activeDownloads = [];

  // List of playlists that are fully available offline
  final offlinePlaylists = ValueNotifier<List<dynamic>>(
    Hive.box('userNoBackup').get('offlinePlaylists', defaultValue: []),
  );

  ValueNotifier<DownloadProgress> getProgressNotifier(String playlistId) {
    if (!downloadProgressNotifiers.containsKey(playlistId)) {
      downloadProgressNotifiers[playlistId] = ValueNotifier<DownloadProgress>(
        DownloadProgress(total: 0),
      );
    }
    return downloadProgressNotifiers[playlistId]!;
  }

  bool isPlaylistDownloaded(String playlistId) {
    return offlinePlaylists.value.any(
      (playlist) =>
          playlist is Map &&
          (playlist['ytid'] ?? playlist['id'])?.toString() == playlistId,
    );
  }

  Map? getOfflinePlaylist(String playlistId) {
    for (final playlist in offlinePlaylists.value) {
      if (playlist is Map &&
          (playlist['ytid'] ?? playlist['id'])?.toString() == playlistId) {
        return playlist;
      }
    }
    return null;
  }

  bool isPlaylistDownloading(String playlistId) {
    return activeDownloads.contains(playlistId);
  }

  /// Marks [playlist] offline when all of its songs are available locally.
  void checkAndAutoMarkOffline(Map playlist) {
    final id = (playlist['ytid'] ?? playlist['id'])?.toString();
    final pList = playlist['list'] as List?;
    if (id == null || pList == null || pList.isEmpty) return;
    if (isPlaylistDownloaded(id)) return;

    final offlineSongIds = userOfflineSongs.value
        .map((s) => (s is Map ? (s['ytid'] ?? s['id']) : null)?.toString())
        .whereType<String>()
        .toSet();
    if (!pList.every((s) =>
        s is Map &&
        offlineSongIds.contains((s['ytid'] ?? s['id'])?.toString()))) {
      return;
    }

    offlinePlaylists.value = [
      ...offlinePlaylists.value,
      {
        ...playlist,
        'ytid': id,
        'id': id,
        'list': pList,
        'downloadedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ];
    unawaited(
      addOrUpdateData<List>(
        'userNoBackup',
        'offlinePlaylists',
        offlinePlaylists.value,
      ),
    );
  }

  Future<void> downloadPlaylist(BuildContext context, Map playlist) async {
    final playlistId = (playlist['ytid'] ?? playlist['id'])?.toString() ?? playlist['title']?.toString();

    if (playlistId == null || playlistId.isEmpty) {
      showToast(context, context.l10n!.error);
      return;
    }

    // Check if already downloading
    if (isPlaylistDownloading(playlistId)) {
      showToast(context, context.l10n!.alreadyDownloading);
      return;
    }

    // Initialize download state
    final songsList = playlist['list'];
    if (songsList is! List || songsList.isEmpty) {
      showToast(context, context.l10n!.playlistEmpty);
      return;
    }

    // Set up progress tracking
    final progressNotifier = getProgressNotifier(playlistId);
    final progress = DownloadProgress(total: songsList.length);
    activeDownloads.add(playlistId);
    progressNotifier.value = progress;

    final deadline = Timer(Duration(minutes: songsList.length * 2), () {
      logger.log('Download timeout for playlist $playlistId');
      progress.isCancelled = true;
      progressNotifier.notifyListeners();
    });
    try {
      final songQueue = Queue<dynamic>.from(songsList);
      const maxConcurrent = 3;
      final workerCount = songsList.length < maxConcurrent
          ? songsList.length
          : maxConcurrent;

      await Future.wait([
        for (var i = 0; i < workerCount; i++)
          _processDownloadQueue(songQueue, progressNotifier),
      ]);
      deadline.cancel();

      // Handle completion
      await _handleDownloadCompletion(
        context,
        playlistId,
        playlist,
        progressNotifier,
      );
    } catch (e, stackTrace) {
      logger.log(
        'Error during playlist download',
        error: e,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        showToast(context, '${context.l10n!.error}: $e');
      }
    } finally {
      deadline.cancel();
      activeDownloads.remove(playlistId);
      cleanupProgressNotifier(playlistId);
    }
  }

  Future<void> _handleDownloadCompletion(
    BuildContext context,
    String playlistId,
    Map playlist,
    ValueNotifier<DownloadProgress> progressNotifier,
  ) async {
    try {
      final songsList = playlist['list'] as List<dynamic>;

      // Keep successful tracks, but advertise the full playlist only when
      // every track is available offline.
      if (!progressNotifier.value.isCancelled &&
          progressNotifier.value.completed == songsList.length) {
        // Create an offline version of the playlist
        final offlinePlaylist = {
          ...playlist,
          'ytid': playlistId,
          'title': playlist['title'],
          'image': playlist['image'],
          'source': playlist['source'],
          'list': songsList,
          'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        };

        // Add to offline playlists
        final updatedPlaylists = List<dynamic>.from(offlinePlaylists.value);

        final existingIndex = updatedPlaylists.indexWhere(
          (p) =>
              p is Map &&
              (p['ytid'] ?? p['id'])?.toString() == playlistId,
        );

        if (existingIndex != -1) {
          updatedPlaylists[existingIndex] = offlinePlaylist;
        } else {
          updatedPlaylists.add(offlinePlaylist);
        }

        // Also mark albums/playlists whose songs are now fully offline
        final offlineSongIds = userOfflineSongs.value
            .map((s) => (s is Map ? (s['ytid'] ?? s['id']) : null)?.toString())
            .whereType<String>()
            .toSet();

        final seenIds = <String>{};
        final userPlaylistSources =
            <Map>[
              ...userCustomPlaylists.value,
              ...userLikedPlaylists.value,
              for (final folder in userPlaylistFolders.value)
                ...List<Map>.from(folder['playlists'] ?? []),
              ...playlists,
            ].where((p) {
              final id = (p['ytid'] ?? p['id'])?.toString();
              return id != null && seenIds.add(id);
            }).toList();
        for (final p in userPlaylistSources) {
          final pList = p['list'] as List?;
          final pId = (p['ytid'] ?? p['id'])?.toString();
          if (pList == null ||
              pList.isEmpty ||
              pId == playlistId ||
              isPlaylistDownloaded(pId ?? '')) {
            continue;
          }
          if (pList.every((s) =>
              s is Map &&
              offlineSongIds.contains((s['ytid'] ?? s['id'])?.toString()))) {
            updatedPlaylists.add({
              ...p,
              'list': pList,
              'downloadedAt': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }

        offlinePlaylists.value = updatedPlaylists;
        unawaited(
          addOrUpdateData<List>(
            'userNoBackup',
            'offlinePlaylists',
            offlinePlaylists.value,
          ),
        );

        if (context.mounted) {
          showToast(
            context,
            '${context.l10n!.playlistDownloaded}: ${progressNotifier.value.completed}/${songsList.length}',
          );
        }
      } else if (!progressNotifier.value.isCancelled) {
        // Cancelled toast is shown by cancelDownload, only show failure toast here.
        if (context.mounted) {
          showToast(
            context,
            '${context.l10n!.downloadFailed}: ${progressNotifier.value.failed}/${songsList.length}',
          );
        }
      }
    } catch (e, stackTrace) {
      logger.log(
        'Error handling download completion',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> cancelDownload(BuildContext context, String playlistId) async {
    if (!isPlaylistDownloading(playlistId)) return;

    try {
      final progressNotifier = getProgressNotifier(playlistId);
      final progress = progressNotifier.value;
      if (progress.isCancelled) return;
      progress.isCancelled = true;
      progressNotifier.notifyListeners();

      // Immediate visual feedback
      showToast(context, context.l10n!.cancellingDownload);

      const maxWaitTime = Duration(seconds: 30);
      final startTime = DateTime.now();

      // Wait for the ongoing tasks to complete with timeout
      while (identical(progressNotifier.value, progress) &&
          isPlaylistDownloading(playlistId)) {
        await Future.delayed(const Duration(milliseconds: 100));

        if (DateTime.now().difference(startTime) > maxWaitTime) {
          logger.log('Timeout waiting for download cancellation');
          return;
        }
      }

      if (context.mounted) showToast(context, context.l10n!.downloadCancelled);
    } catch (e, stackTrace) {
      logger.log('Error cancelling download', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> removeOfflinePlaylist(String playlistId) async {
    try {
      final normalizedPlaylistId = playlistId.trim();
      if (normalizedPlaylistId.isEmpty) {
        logger.log('Invalid playlistId for removal');
        return;
      }

      // Find the playlist
      final currentPlaylists = offlinePlaylists.value;
      final playlistIndex = currentPlaylists.indexWhere(
        (playlist) =>
            playlist is Map &&
            (playlist['ytid'] ?? playlist['id'])?.toString() == normalizedPlaylistId,
      );

      if (playlistIndex == -1) {
        logger.log('Playlist not found for removal: $normalizedPlaylistId');
        return;
      }

      final playlist = currentPlaylists[playlistIndex] as Map;

      // Get songs that are only in this playlist
      final songsInPlaylist = playlist['list'] as List<dynamic>? ?? [];
      final songIdsUsedElsewhere = _getSongIdsUsedElsewhere(
        normalizedPlaylistId,
      );

      for (final song in songsInPlaylist) {
        try {
          if (song is! Map) continue;
          final songId = (song['ytid'] ?? song['id'])?.toString();

          if (songId == null || songId.isEmpty) {
            continue;
          }

          // Only remove if not used elsewhere.
          if (!songIdsUsedElsewhere.contains(songId)) {
            await removeSongFromOffline(songId);
          }
        } catch (e, stackTrace) {
          logger.log(
            'Error removing song from offline',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      // Remove playlist from offline playlists
      final latestPlaylists = offlinePlaylists.value;
      final updatedPlaylists = List<dynamic>.from(latestPlaylists)
        ..removeWhere(
          (p) =>
              p is Map &&
              (p['ytid'] ?? p['id'])?.toString() == normalizedPlaylistId,
        );
      offlinePlaylists.value = updatedPlaylists;
      unawaited(
        addOrUpdateData<List>(
          'userNoBackup',
          'offlinePlaylists',
          offlinePlaylists.value,
        ),
      );
    } catch (e, stackTrace) {
      logger.log(
        'Error removing offline playlist',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Removes [songId] from offline storage and updates offline playlist flags.
  Future<bool> removeSongFromOfflineAndResync(String songId) async {
    final success = await removeSongFromOffline(songId);
    if (success) {
      unawaited(_resyncOfflinePlaylistFlags());
    }
    return success;
  }

  /// Removes stale entries from [offlinePlaylists].
  Future<void> _resyncOfflinePlaylistFlags() async {
    final current = offlinePlaylists.value;
    final stillFullyOffline = <dynamic>[];
    var changed = false;

    for (final playlist in current) {
      if (playlist is! Map) {
        stillFullyOffline.add(playlist);
        continue;
      }

      final songs = playlist['list'] as List<dynamic>? ?? [];
      if (isPlaylistFullyOffline(songs)) {
        stillFullyOffline.add(playlist);
      } else {
        changed = true;
        logger.log(
          'Dropping stale offline flag for playlist '
          '${playlist['ytid']}: no longer fully offline',
        );
      }
    }

    if (!changed) return;

    offlinePlaylists.value = stillFullyOffline;
    unawaited(
      addOrUpdateData<List>(
        'userNoBackup',
        'offlinePlaylists',
        offlinePlaylists.value,
      ),
    );
  }

  // Returns a set of song IDs that are used in other playlists or liked songs,
  Set<String> _getSongIdsUsedElsewhere(String excludedPlaylistId) {
    final songIds = <String>{
      for (final playlist in offlinePlaylists.value)
        if (playlist is Map &&
            (playlist['ytid'] ?? playlist['id'])?.toString() != excludedPlaylistId)
          for (final song in playlist['list'] as List<dynamic>? ?? [])
            if (song is Map && (song['ytid'] ?? song['id']) != null)
              (song['ytid'] ?? song['id']).toString(),
      for (final song in userLikedSongsList.value)
        if (song is Map && (song['ytid'] ?? song['id']) != null)
          (song['ytid'] ?? song['id']).toString(),
      for (final playlist in getUserCustomPlaylists())
        if ((playlist['ytid'] ?? playlist['id'])?.toString() != excludedPlaylistId)
          for (final song in playlist['list'] as List<dynamic>? ?? [])
            if (song is Map && (song['ytid'] ?? song['id']) != null)
              (song['ytid'] ?? song['id']).toString(),
    };

    return songIds;
  }

  Future<void> deleteAllDownloads() async {
    // Cancel all active downloads first and wait for them to stop
    final activeIds = List<String>.from(activeDownloads);
    for (final id in activeIds) {
      final notifier = downloadProgressNotifiers[id];
      if (notifier != null) {
        notifier.value.isCancelled = true;
        notifier.notifyListeners();
      }
    }

    const maxWaitTime = Duration(seconds: 30);
    final startTime = DateTime.now();
    while (activeDownloads.isNotEmpty) {
      if (DateTime.now().difference(startTime) > maxWaitTime) {
        logger.log('Timeout waiting for downloads to cancel before delete');
        throw StateError('Downloads are still cancelling. Try again shortly.');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    try {
      final tracksDir = Directory('$applicationDirPath/${FilePaths.tracksDir}');
      final artworksDir = Directory(
        '$applicationDirPath/${FilePaths.artworksDir}',
      );

      if (await tracksDir.exists()) {
        await tracksDir.delete(recursive: true);
      }
      if (await artworksDir.exists()) {
        await artworksDir.delete(recursive: true);
      }

      await FilePaths.ensureDirectoriesExist();

      userOfflineSongs.value = [];

      offlinePlaylists.value = [];

      for (final id in downloadProgressNotifiers.keys.toList()) {
        cleanupProgressNotifier(id);
      }

      unawaited(addOrUpdateData<List>('userNoBackup', 'offlineSongs', []));
      unawaited(addOrUpdateData<List>('userNoBackup', 'offlinePlaylists', []));
      await OfflineBackupService.instance.clearAllBackups();

      logger.log('All downloads deleted successfully');
    } catch (e, stackTrace) {
      logger.log(
        'Error deleting all downloads',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void cleanupProgressNotifier(String playlistId) {
    if (isPlaylistDownloading(playlistId)) return;
    final notifier = downloadProgressNotifiers[playlistId];
    if (notifier == null) return;
    if (notifier.hasListeners) {
      notifier.value = DownloadProgress(total: 0);
    } else {
      downloadProgressNotifiers.remove(playlistId);
      notifier.dispose();
    }
  }

  Future<void> _processDownloadQueue(
    Queue<dynamic> songQueue,
    ValueNotifier<DownloadProgress> progressNotifier,
  ) async {
    while (songQueue.isNotEmpty && !progressNotifier.value.isCancelled) {
      final song = songQueue.removeFirst();

      try {
        if (song is Map) {
          song['ytid'] ??= song['id'];
        }
        final songYtid = (song is Map ? (song['ytid'] ?? song['id']) : null)?.toString();
        if (song == null ||
            songYtid == null ||
            songYtid.isEmpty) {
          logger.log('Invalid song data in playlist download');
          progressNotifier.value.failed++;
          progressNotifier.notifyListeners();
          continue;
        }

        // Skip if already offline
        if (isSongAlreadyOffline(songYtid)) {
          // Find the existing offline song to get the correct audioPath
          final offlineSong = getOfflineSongByYtid(songYtid);
          if (offlineSong.isNotEmpty) {
            // Update the song in the playlist with the correct offline properties
            song['audioPath'] = offlineSong['audioPath'];
            song['artworkPath'] = offlineSong['artworkPath'];
          }
          // Update progress
          progressNotifier.value.completed++;
          progressNotifier.notifyListeners();
        } else {
          final success = await makeSongOffline(song);
          if (success) {
            progressNotifier.value.completed++;
          } else {
            progressNotifier.value.failed++;
          }
          progressNotifier.notifyListeners();
        }
      } catch (e, stackTrace) {
        logger.log(
          'Failed to download song: ${song is Map ? song['title'] : null}',
          error: e,
          stackTrace: stackTrace,
        );
        progressNotifier.value.failed++;
        progressNotifier.notifyListeners();
      }
    }
  }
}

class DownloadProgress {
  DownloadProgress({
    required this.total,
    this.completed = 0,
    this.failed = 0,
    this.isCancelled = false,
  });

  final int total;
  int completed;
  int failed;
  bool isCancelled;

  double get progress {
    if (total <= 0) return 0;
    final totalProcessed = completed + failed;
    return totalProcessed > total ? 1.0 : totalProcessed / total;
  }

  @override
  String toString() {
    final percentage = (progress * 100).toStringAsFixed(1);
    return '$percentage% ($completed/$total)';
  }
}

// Global instance for easy access
final offlinePlaylistService = OfflinePlaylistService();
