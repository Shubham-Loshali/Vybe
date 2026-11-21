import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/widgets/playlist_cube.dart';

/// A square cover with its title and type underneath, as used in the
/// horizontal shelves of the home screen.
class ShelfCard extends StatelessWidget {
  const ShelfCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.size = 150,
    this.subtitle,
    this.onOpen,
    this.artwork,
  });

  final Map playlist;
  final VoidCallback onTap;
  final double size;
  final String? subtitle;
  final VoidCallback? onOpen;
  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAlbum = playlist['isAlbum'] == true;
    final isArtist =
        playlist['isArtist'] == true ||
        playlist['source']?.toString() == 'youtube-artist';

    return SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: isArtist
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                artwork ??
                    PlaylistCube(
                      playlist,
                      size: size,
                      borderRadius: isArtist ? size / 2 : 4,
                      showTypeLabel: false,
                    ),
                if (onOpen != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                      tooltip: playlist['title']?.toString(),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: onOpen,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              playlist['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: isArtist ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle ??
                  (isArtist
                      ? (context.l10n?.artist ?? 'Artist')
                      : (isAlbum
                            ? context.l10n!.album
                            : context.l10n!.playlist)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: isArtist ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
