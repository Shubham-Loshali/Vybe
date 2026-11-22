import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/main.dart' show audioHandler;
import 'package:vybe/screens/listen_together_page.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/utilities/account_name.dart';

/// Opens Spotify-styled "Connect" bottom sheet matching the Spotify UX.
Future<void> showSpotifyConnectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) => const SpotifyConnectSheet(),
  );
}

class SpotifyConnectSheet extends StatefulWidget {
  const SpotifyConnectSheet({super.key});

  @override
  State<SpotifyConnectSheet> createState() => _SpotifyConnectSheetState();
}

class _SpotifyConnectSheetState extends State<SpotifyConnectSheet> {
  bool _autoInvite = true;

  @override
  Widget build(BuildContext context) {
    final currentSong = audioHandler.currentSong;
    final title = currentSong?['title']?.toString() ?? 'No track playing';
    final artist = currentSong?['artist']?.toString() ?? '';
    final trackLabel = artist.isNotEmpty ? '$title - $artist' : title;

    final user = CloudSyncService.instance.currentUser.value;
    final userName = accountDisplayName(user) ?? 'You';
    final userInitial = userName.characters.first.toUpperCase();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Center drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF555555),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header: "Connect"
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Connect',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  fontFamily: 'Figtree',
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Card: "This phone"
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF282828),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'This phone',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF383838),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Normal',
                                style: TextStyle(
                                  color: Color(0xFFB3B3B3),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          trackLabel,
                          style: const TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    FluentIcons.phone_24_regular,
                    color: Color(0xFF1DB954),
                    size: 34,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Auto-invite people nearby to a Jam
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  const Icon(
                    FluentIcons.people_community_24_regular,
                    color: Colors.white70,
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Auto-invite people nearby to a Jam',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _autoInvite,
                    activeTrackColor: const Color(0xFF1DB954),
                    onChanged: (val) {
                      setState(() {
                        _autoInvite = val;
                      });
                    },
                  ),
                ],
              ),
            ),

            // "No devices found on this network"
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              child: Text(
                'No devices found on this network',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),

            // Generous spacing like in the screenshot
            const SizedBox(height: 36),

            // Bottom 2 Cards (Your Jam & Find Bluetooth devices)
            ValueListenableBuilder<ListenTogetherSession?>(
              valueListenable: ListenTogetherService.instance.session,
              builder: (context, session, _) {
                final inJam = session != null;
                return Row(
                  children: [
                    // Left Card: "+ [S] Your Jam"
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(context);
                          openListenTogetherPage(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: inJam
                                ? const Color(0xFF38142F)
                                : const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(12),
                            border: inJam
                                ? Border.all(
                                    color: const Color(0xFF9D4EDD)
                                        .withValues(alpha: 0.6),
                                    width: 1.2,
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    FluentIcons.add_20_regular,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFB4D6),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      userInitial,
                                      style: const TextStyle(
                                        color: Color(0xFF4C0838),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                inJam ? 'Your Jam (${session.code})' : 'Your Jam',
                                style: const TextStyle(
                                  color: Color(0xFF1DB954),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Right Card: "Find Bluetooth devices"
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.pop(context);
                          _showVolumeDialog(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF242424),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                FluentIcons.bluetooth_24_regular,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Find Bluetooth devices',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVolumeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StreamBuilder<double>(
        stream: audioHandler.volumeStream,
        initialData: audioHandler.volume,
        builder: (context, snapshot) {
          final volume = (snapshot.data ?? 1).clamp(0.0, 1.0);
          final percent = (volume * 100).round();
          return AlertDialog(
            title: const Text('Volume'),
            content: Row(
              children: [
                Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_down_rounded,
                ),
                Expanded(
                  child: Slider(
                    value: volume,
                    onChanged: (v) => unawaited(audioHandler.setVolume(v)),
                  ),
                ),
                Text('$percent%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }
}
