import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/main.dart' show logger;

/// Local collection history. Song history continues to use recentlyPlayedSongs.
class HomePlaybackHistory {
  static const _key = 'homeRecentCollections';
  static final changed = ValueNotifier<int>(0);

  static List<Map> get collections {
    if (!Hive.isBoxOpen('user')) return [];
    final stored = Hive.box('user').get(_key);
    return stored is List ? stored.whereType<Map>().toList() : [];
  }

  static Future<void> record(Map collection, Map song) async {
    final id = collection['ytid']?.toString().trim() ?? '';
    final title = collection['title']?.toString().trim() ?? '';
    final songId = (song['ytid'] ?? song['id'])?.toString();
    if (id.isEmpty ||
        title.isEmpty ||
        songId == null ||
        id.startsWith('system-') ||
        id.startsWith('UC') ||
        collection['isArtist'] == true ||
        !Hive.isBoxOpen('user')) {
      return;
    }

    final isAlbum = collection['isAlbum'] == true || id.startsWith('MPRE');
    try {
      final cover =
          collection['image'] ??
          collection['highResImage'] ??
          song['highResImage'] ??
          song['lowResImage'];
      final entry = {
        'ytid': id,
        'title': title,
        'isAlbum': isAlbum,
        'artist': collection['artist']?.toString(),
        if (cover is String && cover.length <= 2048) 'image': cover,
        'songId': songId,
        'lastPlayed': DateTime.now().millisecondsSinceEpoch,
      };
      await Hive.box('user').put(_key, [
        entry,
        ...collections
            .where((item) => item['ytid'] != id || item['isAlbum'] != isAlbum)
            .take(19),
      ]);
      changed.value++;
    } catch (error, stackTrace) {
      logger.log(
        'Could not save Home collection history',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> clear() async {
    if (!Hive.isBoxOpen('user')) return;
    try {
      await Hive.box('user').delete(_key);
      changed.value++;
    } catch (error, stackTrace) {
      logger.log(
        'Could not clear Home collection history',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
