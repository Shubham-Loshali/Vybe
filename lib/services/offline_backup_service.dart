import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/playlist_download_service.dart';

class OfflineBackupService {
  OfflineBackupService._internal();
  static final OfflineBackupService instance =
      OfflineBackupService._internal();

  Timer? _debounceTimer;
  bool _isRestoring = false;
  static const String backupFileName = 'vybe_offline_backup.json';

  void initialise() {
    userOfflineSongs.addListener(_onOfflineDataChanged);
    OfflinePlaylistService()
        .offlinePlaylists
        .addListener(_onOfflineDataChanged);
  }

  void _onOfflineDataChanged() {
    if (_isRestoring) return;
    scheduleBackup();
  }

  void scheduleBackup() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      unawaited(saveOfflineBackup());
    });
  }

  Future<void> flushBackup() async {
    _debounceTimer?.cancel();
    await saveOfflineBackup();
  }

  /// Automatically creates a backup in multiple safe storage locations.
  Future<void> saveOfflineBackup() async {
    if (_isRestoring) return;
    try {
      final songs = userOfflineSongs.value.whereType<Map>().map((s) {
        final ytid = (s['ytid'] ?? '').toString();
        return {
          'ytid': ytid,
          'title': (s['title'] ?? '').toString(),
          'artist': (s['artist'] ?? '').toString(),
          'image': s['image']?.toString(),
          'highResImage': s['highResImage']?.toString(),
          'lowResImage': s['lowResImage']?.toString(),
          'duration': s['duration'],
          'audioBitrateKbps': s['audioBitrateKbps'],
          'audioCodec': s['audioCodec']?.toString(),
          'dateAdded': s['dateAdded'] ?? DateTime.now().millisecondsSinceEpoch,
          'listeningCount': s['listeningCount'] ?? 0,
        };
      }).toList();

      final playlists = OfflinePlaylistService().offlinePlaylists.value;

      final backupData = {
        'version': 1,
        'appVersion': appVersion,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'songsCount': songs.length,
        'playlistsCount': playlists.length,
        'songs': songs,
        'playlists': playlists,
      };

      final jsonString = jsonEncode(backupData);

      // 1. Save in Hive 'user' box (which persists across normal updates)
      if (Hive.isBoxOpen('user')) {
        await Hive.box('user').put('offlineBackupData', jsonString);
      }

      // 2. Save in internal app tracks directory ($applicationDirPath/tracks/vybe_offline_backup.json)
      final tracksBackup = File(
        '$applicationDirPath/${FilePaths.tracksDir}/$backupFileName',
      );
      await tracksBackup.parent.create(recursive: true);
      await tracksBackup.writeAsString(jsonString);

      // 3. Save in internal app root ($applicationDirPath/vybe_offline_backup.json)
      final internalBackup = File('$applicationDirPath/$backupFileName');
      await internalBackup.writeAsString(jsonString);

      // 4. Save in external app storage (survives app updates & reinstalls on Android)
      if (Platform.isAndroid) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final extBackup = File('${extDir.path}/$backupFileName');
            await extBackup.parent.create(recursive: true);
            await extBackup.writeAsString(jsonString);
          }
        } catch (e) {
          logger.log('Could not write external backup file', error: e);
        }
      }

      logger.log(
        'Auto-backup saved: ${songs.length} songs, ${playlists.length} playlists',
      );
    } catch (e, stack) {
      logger.log('Error creating offline backup', error: e, stackTrace: stack);
    }
  }

  /// Clears backups when user deliberately deletes all downloads.
  Future<void> clearAllBackups() async {
    try {
      if (Hive.isBoxOpen('user')) {
        await Hive.box('user').delete('offlineBackupData');
      }

      final filesToDelete = <File>[
        File('$applicationDirPath/${FilePaths.tracksDir}/$backupFileName'),
        File('$applicationDirPath/$backupFileName'),
      ];

      if (Platform.isAndroid) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            filesToDelete.add(File('${extDir.path}/$backupFileName'));
          }
        } catch (_) {}
      }

      for (final file in filesToDelete) {
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e, stack) {
      logger.log('Error clearing offline backups', error: e, stackTrace: stack);
    }
  }

  /// Checks if a new version or missing offline songs are detected, and auto-restores.
  Future<int> initialiseAndRestoreIfNeeded() async {
    try {
      final settingsBox = Hive.isBoxOpen('settings')
          ? Hive.box('settings')
          : await Hive.openBox('settings');
      final lastVersion =
          settingsBox.get('lastInstalledAppVersion')?.toString();
      final isNewVersion = lastVersion == null || lastVersion != appVersion;
      final hasNoOfflineSongs = userOfflineSongs.value.isEmpty;

      logger.log(
        'Checking offline backup: lastVersion=$lastVersion, current=$appVersion, isNew=$isNewVersion, songsCount=${userOfflineSongs.value.length}',
      );

      // Auto-restore on new version or when songs are empty
      if (isNewVersion || hasNoOfflineSongs) {
        final restored = await restoreOfflineBackup();
        await settingsBox.put('lastInstalledAppVersion', appVersion);
        return restored;
      } else {
        // Self-heal file paths for current songs
        await _selfHealAudioPaths();
        await settingsBox.put('lastInstalledAppVersion', appVersion);
        scheduleBackup();
        return 0;
      }
    } catch (e, stack) {
      logger.log(
        'Error in initialiseAndRestoreIfNeeded',
        error: e,
        stackTrace: stack,
      );
      return 0;
    }
  }

  /// Restores songs and playlists from the best available backup file or disk scan.
  Future<int> restoreOfflineBackup() async {
    _isRestoring = true;
    try {
      Map<String, dynamic>? backupData;

      // 1. Try external storage first (most persistent across reinstalls)
      if (Platform.isAndroid) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final extFile = File('${extDir.path}/$backupFileName');
            if (await extFile.exists()) {
              final content = await extFile.readAsString();
              backupData = jsonDecode(content) as Map<String, dynamic>;
              logger.log('Found offline backup in external storage');
            }
          }
        } catch (_) {}
      }

      // 2. Try tracks directory backup
      if (backupData == null) {
        try {
          final tracksFile = File(
            '$applicationDirPath/${FilePaths.tracksDir}/$backupFileName',
          );
          if (await tracksFile.exists()) {
            final content = await tracksFile.readAsString();
            backupData = jsonDecode(content) as Map<String, dynamic>;
            logger.log('Found offline backup in tracks directory');
          }
        } catch (_) {}
      }

      // 3. Try app directory root backup
      if (backupData == null) {
        try {
          final rootFile = File('$applicationDirPath/$backupFileName');
          if (await rootFile.exists()) {
            final content = await rootFile.readAsString();
            backupData = jsonDecode(content) as Map<String, dynamic>;
            logger.log('Found offline backup in app root directory');
          }
        } catch (_) {}
      }

      // 4. Try Hive 'user' box backup
      if (backupData == null && Hive.isBoxOpen('user')) {
        try {
          final savedJson =
              Hive.box('user').get('offlineBackupData')?.toString();
          if (savedJson != null && savedJson.isNotEmpty) {
            backupData = jsonDecode(savedJson) as Map<String, dynamic>;
            logger.log('Found offline backup in Hive user box');
          }
        } catch (_) {}
      }

      final restoredSongs = <Map<String, dynamic>>[];
      final existingIds = userOfflineSongs.value
          .whereType<Map>()
          .map((s) => s['ytid']?.toString())
          .whereType<String>()
          .toSet();

      // Add existing songs first (with self-healed paths)
      for (final song in userOfflineSongs.value) {
        if (song is Map) {
          final healed = Map<String, dynamic>.from(song);
          final ytid = healed['ytid']?.toString() ?? '';
          if (ytid.isNotEmpty) {
            healed['audioPath'] = FilePaths.getAudioPath(ytid);
            healed['artworkPath'] = FilePaths.getArtworkPath(ytid);
            restoredSongs.add(healed);
          }
        }
      }

      // Restore from backup manifest
      if (backupData != null && backupData['songs'] is List) {
        final backupSongs = (backupData['songs'] as List).whereType<Map>();
        for (final item in backupSongs) {
          final songMap = Map<String, dynamic>.from(item);
          final ytid = songMap['ytid']?.toString() ?? '';
          if (ytid.isEmpty) continue;

          // Check if audio file exists on disk
          final currentAudioPath = FilePaths.getAudioPath(ytid);
          final audioExists = await File(currentAudioPath).exists();

          if (audioExists) {
            songMap['audioPath'] = currentAudioPath;
            songMap['artworkPath'] = FilePaths.getArtworkPath(ytid);

            if (!existingIds.contains(ytid)) {
              restoredSongs.add(songMap);
              existingIds.add(ytid);
            }
          }
        }
      }

      // 5. Disk scanner fallback: find any .m4a files in tracks directory that weren't in backup
      try {
        final tracksDir = Directory(
          '$applicationDirPath/${FilePaths.tracksDir}',
        );
        if (await tracksDir.exists()) {
          final files = tracksDir.listSync().whereType<File>();
          for (final file in files) {
            if (file.path.endsWith(FilePaths.audioExtension)) {
              final fileName = file.uri.pathSegments.last;
              final ytid = fileName.substring(
                0,
                fileName.length - FilePaths.audioExtension.length,
              );
              if (ytid.isNotEmpty && !existingIds.contains(ytid)) {
                final meta = _findCachedMetadata(ytid);
                restoredSongs.add({
                  'ytid': ytid,
                  'title': meta?['title'] ?? 'Downloaded Song',
                  'artist': meta?['artist'] ?? 'Unknown Artist',
                  'image': meta?['image'],
                  'highResImage': meta?['highResImage'],
                  'lowResImage': meta?['lowResImage'],
                  'audioPath': file.path,
                  'artworkPath': FilePaths.getArtworkPath(ytid),
                  'duration': meta?['duration'],
                  'dateAdded': DateTime.now().millisecondsSinceEpoch,
                  'listeningCount': 0,
                });
                existingIds.add(ytid);
              }
            }
          }
        }
      } catch (e) {
        logger.log('Error during disk scan fallback', error: e);
      }

      // If songs were restored or updated, save to Hive
      var hasChanges = restoredSongs.length != userOfflineSongs.value.length;
      if (!hasChanges) {
        for (var i = 0; i < restoredSongs.length; i++) {
          final oldSong = userOfflineSongs.value[i];
          final newSong = restoredSongs[i];
          if (oldSong is! Map ||
              oldSong['audioPath'] != newSong['audioPath'] ||
              oldSong['ytid'] != newSong['ytid']) {
            hasChanges = true;
            break;
          }
        }
      }

      if (hasChanges) {
        userOfflineSongs.value = restoredSongs;
        await addOrUpdateData<List>(
          'userNoBackup',
          'offlineSongs',
          restoredSongs,
        );
        logger.log(
          'Restoration complete: ${restoredSongs.length} songs restored/offline',
        );
      }

      // Restore offline playlists if present
      if (backupData != null && backupData['playlists'] is List) {
        final backupPlaylists = List<dynamic>.from(
          backupData['playlists'] as List,
        );
        if (backupPlaylists.isNotEmpty) {
          OfflinePlaylistService().offlinePlaylists.value = backupPlaylists;
          await addOrUpdateData<List>(
            'userNoBackup',
            'offlinePlaylists',
            backupPlaylists,
          );
        }
      }

      _isRestoring = false;
      await saveOfflineBackup();

      return restoredSongs.length;
    } catch (e, stack) {
      logger.log('Error restoring offline backup', error: e, stackTrace: stack);
      return 0;
    } finally {
      _isRestoring = false;
    }
  }

  Map<String, dynamic>? _findCachedMetadata(String ytid) {
    try {
      if (Hive.isBoxOpen('cache')) {
        final cacheBox = Hive.box('cache');
        final raw = cacheBox.get('song_$ytid') ?? cacheBox.get('meta_$ytid');
        if (raw is Map) return Map<String, dynamic>.from(raw);
      }
      if (Hive.isBoxOpen('user')) {
        final liked = Hive.box('user').get('likedSongsList', defaultValue: []);
        if (liked is List) {
          final found = liked.firstWhere(
            (s) => s is Map && s['ytid'] == ytid,
            orElse: () => null,
          );
          if (found is Map) return Map<String, dynamic>.from(found);
        }
        final recent =
            Hive.box('user').get('recentlyPlayedSongs', defaultValue: []);
        if (recent is List) {
          final found = recent.firstWhere(
            (s) => s is Map && s['ytid'] == ytid,
            orElse: () => null,
          );
          if (found is Map) return Map<String, dynamic>.from(found);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _selfHealAudioPaths() async {
    var changed = false;
    final updated = <Map<String, dynamic>>[];
    for (final song in userOfflineSongs.value) {
      if (song is Map) {
        final map = Map<String, dynamic>.from(song);
        final ytid = map['ytid']?.toString() ?? '';
        if (ytid.isNotEmpty) {
          final currentPath = FilePaths.getAudioPath(ytid);
          if (map['audioPath'] != currentPath) {
            map['audioPath'] = currentPath;
            map['artworkPath'] = FilePaths.getArtworkPath(ytid);
            changed = true;
          }
          updated.add(map);
        } else {
          changed = true;
        }
      } else {
        changed = true;
      }
    }
    if (changed) {
      userOfflineSongs.value = updated;
      await addOrUpdateData<List>('userNoBackup', 'offlineSongs', updated);
      logger.log('Self-healed offline audio paths');
    }
  }
}
