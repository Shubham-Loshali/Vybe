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

    return SizedBox(
      width: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlaylistCube(
              playlist,
              size: size,
              borderRadius: 4,
              showTypeLabel: false,
            ),
            const SizedBox(height: 8),
            Text(
              playlist['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isAlbum ? context.l10n!.album : context.l10n!.playlist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
