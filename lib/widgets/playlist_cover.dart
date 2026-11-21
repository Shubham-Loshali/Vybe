import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/widgets/no_artwork_cube.dart';
import 'package:vybe/widgets/playlist_artwork.dart';

/// The same cover on Home, in the library, and on the playlist itself.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    this.size = 220,
    this.fallbackIcon = FluentIcons.text_bullet_list_24_filled,
    this.fallback,
  });

  final Map playlist;
  final double size;
  final IconData fallbackIcon;
  final Widget? fallback;

  static List<List<String>> songArtwork(Map playlist) {
    final result = <List<String>>[];
    final seen = <String>{};
    final shared = playlist['isCollaborative'] == true;
    var hasMissingArtwork = false;
    final songs = playlist['list'];
    if (songs is! List) return result;
    for (final song in songs.whereType<Map>()) {
      final candidates =
          [
                song['artworkPath'],
                song['artWorkPath'],
                song['highResImage'],
                song['lowResImage'],
                song['image'],
              ]
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && s != 'null')
              // Shared covers cannot depend on files available on one phone.
              .where(
                (s) =>
                    !shared ||
                    s.startsWith('https://') ||
                    s.startsWith('http://') ||
                    s.startsWith('data:image/'),
              )
              .toSet()
              .toList();
      if (candidates.isEmpty) {
        hasMissingArtwork = true;
        continue;
      }
      if (!seen.add(candidates.first)) continue;
      result.add(candidates);
      if (result.length == 4) break;
    }
    if (hasMissingArtwork && result.isNotEmpty && result.length < 4) {
      result.add(const []);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (playlist['isLikedSongs'] == true) return LikedSongsCover(size: size);
    final image = playlist['image']?.toString().trim();
    final isArtist =
        playlist['isArtist'] == true || playlist['source'] == 'youtube-artist';
    final songs = songArtwork(playlist);
    final defaultCover = songs.isEmpty || isArtist
        ? fallback ??
              PlaylistArtwork(
                playlistArtwork: null,
                size: size,
                cubeIcon: isArtist
                    ? FluentIcons.person_24_filled
                    : fallbackIcon,
              )
        : songs.length == 1
        ? _SongCover(candidates: songs.first, size: size)
        : SizedBox(
            width: size,
            height: size,
            child: Column(
              children: [
                for (var row = 0; row < 2; row++)
                  Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      for (var column = 0; column < 2; column++)
                        _SongCover(
                          candidates:
                              songs[songs.length == 2
                                  ? (row + column) % 2
                                  : (row * 2 + column) % songs.length],
                          size: size / 2,
                        ),
                    ],
                  ),
              ],
            ),
          );
    final cover = image == null || image.isEmpty || image == 'null'
        ? defaultCover
        : PlaylistArtwork(
            playlistArtwork: image,
            size: size,
            fallback: defaultCover,
          );
    return isArtist ? ClipOval(child: cover) : cover;
  }
}

class LikedSongsCover extends StatelessWidget {
  const LikedSongsCover({super.key, this.size = 220});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)],
        ),
      ),
      child: Center(
        child: Icon(
          FluentIcons.heart_24_filled,
          color: Colors.white,
          size: size * 0.42,
        ),
      ),
    ),
  );
}

class _SongCover extends StatelessWidget {
  const _SongCover({required this.candidates, required this.size});
  final List<String> candidates;
  final double size;

  @override
  Widget build(BuildContext context) => PlaylistArtwork(
    playlistArtwork: candidates.isEmpty ? null : candidates.first,
    size: size,
    fallback: candidates.length > 1
        ? _SongCover(candidates: candidates.sublist(1), size: size)
        : NullArtworkWidget(size: size, borderRadius: 0),
  );
}
