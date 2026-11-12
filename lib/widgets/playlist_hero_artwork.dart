import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/widgets/playlist_cube.dart';

class PlaylistHeroArtwork extends StatelessWidget {
  const PlaylistHeroArtwork(
    this.playlist, {
    super.key,
    this.cubeIcon = FluentIcons.text_bullet_list_24_filled,
    this.isArtist = false,
  });

  final Map playlist;
  final IconData cubeIcon;

  /// Artists get a round picture, everything else a square cover.
  final bool isArtist;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final preferredSize = screenSize.width > screenSize.height
            ? 240.0
            : screenSize.width / (commonPlaylistArtworkDivision - 0.1);
        final size = preferredSize
            .clamp(0.0, min(constraints.maxWidth, constraints.maxHeight))
            .toDouble();
        final radius = isArtist ? size / 2 : 4.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: PlaylistCube(
            playlist,
            size: size,
            cubeIcon: cubeIcon,
            borderRadius: radius,
            showTypeLabel: false,
          ),
        );
      },
    );
  }
}
