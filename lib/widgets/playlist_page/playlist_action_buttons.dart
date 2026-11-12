import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';

/// Spotify's action row: secondary actions ([leading]) on the left, shuffle
/// and a large green play button on the right. Shared by the playlist and
/// the artist pages. While [isLoading] the songs are still being read, so
/// both buttons wait instead of playing an incomplete list.
class PlaylistActionButtons extends StatelessWidget {
  const PlaylistActionButtons({
    super.key,
    required this.onPlay,
    required this.onShuffle,
    this.isLoading = false,
    this.leading = const [],
  });

  final VoidCallback onPlay;

  final AsyncCallback onShuffle;

  final bool isLoading;

  /// Like, download and similar buttons shown before the play controls.
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: leading),
            ),
          ),
        ),
        IconButton(
          tooltip: context.l10n!.shuffle,
          iconSize: 26,
          icon: Icon(
            FluentIcons.arrow_shuffle_24_filled,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: isLoading ? null : onShuffle,
        ),
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: context.l10n!.play,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
            foregroundColor: Colors.black,
            fixedSize: const Size(56, 56),
            shape: const CircleBorder(),
          ),
          iconSize: 30,
          icon: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(FluentIcons.play_24_filled),
          onPressed: isLoading ? null : onPlay,
        ),
      ],
    );
  }
}
