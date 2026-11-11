import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/utilities/flutter_bottom_sheet.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/queue_list_view.dart';
import 'package:share_plus/share_plus.dart';

class SpotifyBottomRow extends StatelessWidget {
  const SpotifyBottomRow({
    super.key,
    required this.metadata,
  });

  final MediaItem metadata;

  Future<void> _shareSong(BuildContext context) async {
    final ytid = metadata.extras?['ytid']?.toString();
    final artist = metadata.artist?.trim() ?? '';
    final title = metadata.title.trim();
    final text = ytid != null && ytid.isNotEmpty
        ? 'Listening to $title ${artist.isNotEmpty ? "by $artist " : ""}on Vybe: https://youtu.be/$ytid'
        : 'Listening to $title ${artist.isNotEmpty ? "by $artist " : ""}on Vybe';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: '$title - Vybe',
        ),
      );
    } catch (_) {
      if (context.mounted) {
        showToast(context, context.l10n?.error ?? 'Unable to share');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const iconColor = Color(0xFFB3B3B3);
    const iconSize = 22.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Device connect button
          IconButton(
            iconSize: iconSize,
            icon: const Icon(
              FluentIcons.speaker_2_24_regular,
              color: iconColor,
            ),
            tooltip: 'Devices',
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              padding: const EdgeInsets.all(8),
            ),
            onPressed: () {
              showToast(context, 'Playing on this device');
            },
          ),
          // Right actions: Share & Queue
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: iconSize,
                icon: const Icon(
                  FluentIcons.share_24_regular,
                  color: iconColor,
                ),
                tooltip: context.l10n?.share ?? 'Share',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: () => _shareSong(context),
              ),
              const SizedBox(width: 4),
              IconButton(
                iconSize: iconSize,
                icon: const Icon(
                  FluentIcons.apps_list_24_regular,
                  color: iconColor,
                ),
                tooltip: context.l10n?.queue ?? 'Queue',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: () => showCustomBottomSheet(
                  context,
                  const QueueWidget(isBottomSheet: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

