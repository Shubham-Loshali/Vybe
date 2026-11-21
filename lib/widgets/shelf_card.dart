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
  });

  final Map playlist;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAlbum = playlist['isAlbum'] == true;
    final isArtist = playlist['isArtist'] == true ||
        playlist['source']?.toString() == 'youtube-artist';

    return SizedBox(
      width: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment:
              isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            PlaylistCube(
              playlist,
              size: size,
              borderRadius: isArtist ? size / 2 : 4,
              showTypeLabel: false,
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
              isArtist
                  ? (context.l10n?.artist ?? 'Artist')
                  : (isAlbum ? context.l10n!.album : context.l10n!.playlist),
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
