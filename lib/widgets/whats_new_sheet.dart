import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/playlists_manager.dart';

/// The highlights of this version, shown once to people who update.
/// Replace these with each release.
const whatsNewHighlights = <(IconData, String, String)>[
  (
    FluentIcons.flash_24_filled,
    'Instant playback',
    'Songs start the moment you tap them.',
  ),
  (
    FluentIcons.next_24_filled,
    'Next always works',
    'At the end of your queue, Next plays a similar song.',
  ),
  (
    FluentIcons.search_24_filled,
    'A new search',
    'Suggestions and songs appear as you type.',
  ),
  (
    FluentIcons.history_24_filled,
    'Pick up where you left off',
    'Your last song waits in the player when you open Vybe.',
  ),
  (
    FluentIcons.people_team_24_filled,
    'Better shared playlists',
    'Changes stay in sync for everyone.',
  ),
];

const _seenVersionKey = 'whatsNewSeenVersion';

/// Shows [WhatsNewOverlay] once per version, after an update. A fresh install
/// has nothing to compare against, so it is only marked as seen.
Future<void> showWhatsNewIfUpdated(BuildContext context) async {
  final settings = Hive.box('settings');
  if (settings.get(_seenVersionKey) == appVersion) return;
  await settings.put(_seenVersionKey, appVersion);

  final isFreshInstall =
      userRecentlyPlayed.value.isEmpty &&
      userLikedSongsList.value.isEmpty &&
      userCustomPlaylists.value.isEmpty;
  if (isFreshInstall || !context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n!.whatsNewDismiss,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const WhatsNewOverlay(),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// A card floating over the dimmed app, with Dismiss underneath, in the
/// style of Spotify's in-app announcements.
class WhatsNewOverlay extends StatelessWidget {
  const WhatsNewOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;
    final size = MediaQuery.sizeOf(context);
    final cardWidth = math.min(360, size.width - 48).toDouble();

    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(
                    width: cardWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFF282828),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 24),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Artwork(colorScheme: colorScheme),
                        const SizedBox(height: 22),
                        Text(
                          l10n.whatsNewTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final (icon, title, description)
                            in whatsNewHighlights)
                          _Highlight(
                            icon: icon,
                            title: title,
                            description: description,
                            color: colorScheme.primary,
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: colorScheme.primary,
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                            child: Text(l10n.whatsNewGotIt),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              child: Text(
                l10n.whatsNewDismiss,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// The card's cover: the Vybe mark on a green glow, with the version.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: RadialGradient(
            center: const Alignment(0, -0.25),
            radius: 1.05,
            colors: [
              colorScheme.primary.withValues(alpha: 0.85),
              const Color(0xFF0E2A18),
              const Color(0xFF050907),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                'assets/icons/ic_launcher.png',
                width: 92,
                height: 92,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: Text(
                context.l10n!.whatsNewBadge.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 10,
              child: Text(
                'v$appVersion',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: description,
                    style: const TextStyle(color: Color(0xFFB3B3B3)),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
