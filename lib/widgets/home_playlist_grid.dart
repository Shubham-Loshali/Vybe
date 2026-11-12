import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/widgets/playlist_cover.dart';

/// Compact library shortcuts, with Liked Songs always available first.
class HomePlaylistGrid extends StatelessWidget {
  const HomePlaylistGrid({
    super.key,
    required this.playlists,
    required this.onLikedSongsTap,
    required this.onPlaylistTap,
  });

  final List<Map> playlists;
  final VoidCallback onLikedSongsTap;
  final ValueChanged<Map> onPlaylistTap;

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final items = playlists
        .where((playlist) {
          final id = playlist['ytid']?.toString().trim() ?? '';
          return id.isNotEmpty && id != 'null' && seen.add(id);
        })
        .take(7)
        .toList();
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = math.max(64, 14 * scale * 1.25 * 2 + 16).toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: EdgeInsets.zero,
            primary: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length + 1,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: constraints.maxWidth >= 900 ? 4 : 2,
              mainAxisExtent: height,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _PlaylistShortcut(
                  title: context.l10n?.likedSongs ?? 'Liked songs',
                  artwork: const LikedSongsCover(size: 64),
                  onTap: onLikedSongsTap,
                );
              }
              final playlist = items[index - 1];
              return _PlaylistShortcut(
                title:
                    playlist['title']?.toString() ??
                    context.l10n?.playlist ??
                    'Playlist',
                artwork: PlaylistCover(playlist: playlist, size: 64),
                onTap: () => onPlaylistTap(playlist),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistShortcut extends StatelessWidget {
  const _PlaylistShortcut({
    required this.title,
    required this.artwork,
    required this.onTap,
  });

  final String title;
  final Widget artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: colors.brightness == Brightness.dark
            ? const Color(0xFF282828)
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(width: 64, height: 64, child: artwork),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
