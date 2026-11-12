import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart' show audioHandler;
import 'package:vybe/utilities/flutter_bottom_sheet.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/queue_list_view.dart';

class SpotifyBottomRow extends StatelessWidget {
  const SpotifyBottomRow({super.key, required this.metadata});

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
        ShareParams(text: text, subject: '$title - Vybe'),
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
          // Playback volume
          IconButton(
            iconSize: iconSize,
            icon: const Icon(
              FluentIcons.speaker_2_24_regular,
              color: iconColor,
            ),
            tooltip: 'Volume',
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              padding: const EdgeInsets.all(8),
            ),
            onPressed: () =>
                showCustomBottomSheet(context, const _VolumePanel()),
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

class _VolumePanel extends StatelessWidget {
  const _VolumePanel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: audioHandler.volumeStream,
      initialData: audioHandler.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1).clamp(0.0, 1.0);
        final percent = (volume * 100).round();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Volume', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_down_rounded,
                  ),
                  Expanded(
                    child: Slider(
                      value: volume,
                      onChanged: (value) =>
                          unawaited(audioHandler.setVolume(value)),
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('$percent%', textAlign: TextAlign.end),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
