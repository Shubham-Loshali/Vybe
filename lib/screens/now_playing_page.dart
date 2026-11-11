import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/artwork_color_extractor.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/mediaitem.dart';
import 'package:vybe/utilities/playlist_dialogs.dart';
import 'package:vybe/widgets/now_playing/bottom_actions_row.dart';
import 'package:vybe/widgets/now_playing/now_playing_controls.dart';
import 'package:vybe/widgets/now_playing/spotify_bottom_row.dart';
import 'package:vybe/widgets/now_playing/spotify_lyrics_card.dart';
import 'package:vybe/widgets/queue_list_view.dart';
import 'package:vybe/widgets/song_artwork.dart';
import 'package:share_plus/share_plus.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  Color _dominantColor = ArtworkColorExtractor.defaultGradientColor;
  String? _lastArtworkUri;

  void _updateDominantColor(String? artworkUri) {
    if (artworkUri == null || artworkUri == _lastArtworkUri) return;
    _lastArtworkUri = artworkUri;
    ArtworkColorExtractor.extractDominantColor(artworkUri).then((color) {
      if (mounted && color != _dominantColor) {
        setState(() => _dominantColor = color);
      }
    });
  }

  void _openSongOptionsSheet(BuildContext context, MediaItem metadata) {
    final ytid = metadata.extras?['ytid']?.toString();
    final isRadioStation = metadata.extras?['isLive'] == true;
    final isOffline = isSongAlreadyOffline(ytid);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF242424),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SongArtworkWidget(
                          metadata: metadata,
                          size: 50,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metadata.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              metadata.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB3B3B3),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                if (!offlineMode.value && !isRadioStation)
                  ListTile(
                    leading: const Icon(
                      FluentIcons.album_add_24_regular,
                      color: Colors.white,
                    ),
                    title: Text(
                      context.l10n?.addToPlaylist ?? 'Add to playlist',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      showAddToPlaylistDialog(
                        context,
                        song: mediaItemToMap(metadata),
                      );
                    },
                  ),
                if (!isRadioStation)
                  ListTile(
                    leading: Icon(
                      isOffline
                          ? FluentIcons.cloud_off_24_filled
                          : FluentIcons.cloud_arrow_down_24_regular,
                      color: Colors.white,
                    ),
                    title: Text(
                      isOffline
                          ? (context.l10n?.removeOffline ??
                              'Remove from downloads')
                          : (context.l10n?.makeOffline ?? 'Download song'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (ytid != null) {
                        if (isOffline) {
                          await OfflinePlaylistService()
                              .removeSongFromOfflineAndResync(ytid);
                        } else {
                          await makeSongOffline(mediaItemToMap(metadata));
                        }
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(
                    FluentIcons.timer_24_regular,
                    color: Colors.white,
                  ),
                  title: Text(
                    context.l10n?.sleepTimer ?? 'Sleep timer',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showSleepTimerDialog(context);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    FluentIcons.share_24_regular,
                    color: Colors.white,
                  ),
                  title: Text(
                    context.l10n?.share ?? 'Share',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    final artist = metadata.artist?.trim() ?? '';
                    final text = ytid != null && ytid.isNotEmpty
                        ? 'Listening to ${metadata.title} ${artist.isNotEmpty ? "by $artist " : ""}on Vybe: https://youtu.be/$ytid'
                        : 'Listening to ${metadata.title} ${artist.isNotEmpty ? "by $artist " : ""}on Vybe';
                    SharePlus.instance.share(
                      ShareParams(
                        text: text,
                        subject: '${metadata.title} - Vybe',
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    FluentIcons.copy_24_regular,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Copy song info',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final text = metadata.artist != null
                        ? '${metadata.artist} - ${metadata.title}'
                        : metadata.title;
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      showToast(
                        context,
                        context.l10n?.songInfoCopied ?? 'Copied',
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLargeScreen = size.width > 800 && size.height > 600;
    final screenWidth = size.width;
    final baseIconSize = screenWidth < 360
        ? 36.0
        : screenWidth < 400
        ? 40.0
        : 44.0;
    final miniIconSize = screenWidth < 360 ? 18.0 : 22.0;

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, snapshot) {
        final metadata = snapshot.data;
        if (metadata != null) {
          _updateDominantColor(metadata.artUri?.toString());
        }

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _dominantColor,
                  Color.alphaBlend(
                    _dominantColor.withValues(alpha: 0.35),
                    const Color(0xFF121212),
                  ),
                  const Color(0xFF121212),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: SafeArea(
              child: metadata == null
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Column(
                      children: [
                        _buildAppBar(context, metadata),
                        Expanded(
                          child: isLargeScreen
                              ? _DesktopLayout(
                                  metadata: metadata,
                                  size: size,
                                  adjustedIconSize: baseIconSize,
                                  adjustedMiniIconSize: miniIconSize,
                                  dominantColor: _dominantColor,
                                )
                              : _MobileLayout(
                                  metadata: metadata,
                                  size: size,
                                  adjustedIconSize: baseIconSize,
                                  adjustedMiniIconSize: miniIconSize,
                                  dominantColor: _dominantColor,
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar(BuildContext context, MediaItem metadata) {
    final albumTitle = metadata.album?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            iconSize: 26,
            icon: const Icon(
              FluentIcons.chevron_down_24_regular,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (albumTitle != null && albumTitle.isNotEmpty)
                      ? 'PLAYING FROM ALBUM'
                      : 'PLAYING SONG',
                  style: const TextStyle(
                    color: Color(0xFFB3B3B3),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  (albumTitle != null && albumTitle.isNotEmpty)
                      ? albumTitle
                      : metadata.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            iconSize: 24,
            icon: const Icon(
              FluentIcons.more_vertical_24_regular,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            onPressed: () => _openSongOptionsSheet(context, metadata),
          ),
        ],
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.dominantColor,
  });

  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final Color dominantColor;

  @override
  Widget build(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    final double imageSize = min(size.height * 0.4, 360).toDouble();

    return Row(
      children: [
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: imageSize,
                    height: imageSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SongArtworkWidget(
                        metadata: metadata,
                        size: imageSize,
                        errorWidgetIconSize: 64,
                        borderRadius: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!isLive)
                  NowPlayingControls(
                    size: size,
                    audioId: metadata.extras?['ytid'],
                    adjustedIconSize: adjustedIconSize,
                    adjustedMiniIconSize: adjustedMiniIconSize,
                    metadata: metadata,
                  ),
                SpotifyBottomRow(metadata: metadata),
                if (!isLive)
                  SpotifyLyricsCard(
                    metadata: metadata,
                    dominantColor: dominantColor,
                  ),
              ],
            ),
          ),
        ),
        const Expanded(
          flex: 4,
          child: QueueWidget(),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.dominantColor,
  });

  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final Color dominantColor;

  @override
  Widget build(BuildContext context) {
    final isLandscape = size.width > size.height;

    if (isLandscape) {
      return _buildLandscapeLayout(context);
    }
    return _buildPortraitLayout(context);
  }

  Widget _buildPortraitLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    final screenWidth = size.width;
    final screenHeight = size.height;
    final albumArtSize = min(screenWidth - 48, screenHeight * 0.40);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: albumArtSize,
              height: albumArtSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SongArtworkWidget(
                  metadata: metadata,
                  size: albumArtSize,
                  errorWidgetIconSize: 48,
                  borderRadius: 8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!isLive)
            NowPlayingControls(
              size: size,
              audioId: metadata.extras?['ytid'],
              adjustedIconSize: adjustedIconSize,
              adjustedMiniIconSize: adjustedMiniIconSize,
              metadata: metadata,
            ),
          SpotifyBottomRow(metadata: metadata),
          if (!isLive)
            SpotifyLyricsCard(
              metadata: metadata,
              dominantColor: dominantColor,
            ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    final albumArtSize = min(size.height * 0.55, size.width * 0.35);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: Container(
                width: albumArtSize,
                height: albumArtSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SongArtworkWidget(
                    metadata: metadata,
                    size: albumArtSize,
                    errorWidgetIconSize: 40,
                    borderRadius: 8,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                if (!isLive)
                  NowPlayingControls(
                    size: size,
                    audioId: metadata.extras?['ytid'],
                    adjustedIconSize: adjustedIconSize,
                    adjustedMiniIconSize: adjustedMiniIconSize,
                    metadata: metadata,
                  ),
                SpotifyBottomRow(metadata: metadata),
                if (!isLive)
                  SpotifyLyricsCard(
                    metadata: metadata,
                    dominantColor: dominantColor,
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
