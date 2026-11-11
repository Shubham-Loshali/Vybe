import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/position_data.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/widgets/now_playing/synced_lyrics_view.dart';

class SpotifyLyricsCard extends StatefulWidget {
  const SpotifyLyricsCard({
    super.key,
    required this.metadata,
    required this.dominantColor,
  });

  final MediaItem metadata;
  final Color dominantColor;

  @override
  State<SpotifyLyricsCard> createState() => _SpotifyLyricsCardState();
}

class _SpotifyLyricsCardState extends State<SpotifyLyricsCard> {
  Future<Lyrics?>? _lyricsFuture;
  String? _resolvedKey;
  StreamSubscription<PositionData>? _positionSub;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
    _positionSub = audioHandler.positionDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _currentPosition = data.position;
        });
      }
    });
  }

  @override
  void didUpdateWidget(SpotifyLyricsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id ||
        oldWidget.metadata.title != widget.metadata.title ||
        oldWidget.metadata.artist != widget.metadata.artist) {
      _fetchLyrics();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  void _fetchLyrics() {
    final key = '${widget.metadata.artist} - ${widget.metadata.title}';
    if (key == _resolvedKey && _lyricsFuture != null) return;
    _resolvedKey = key;
    setState(() {
      _lyricsFuture = getSongLyricsResult(
        widget.metadata.artist,
        widget.metadata.title,
        duration: widget.metadata.duration,
        album: widget.metadata.album,
      );
    });
  }

  void _openFullScreenLyrics(BuildContext context, Lyrics lyrics) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullScreenLyricsModal(
              metadata: widget.metadata,
              lyrics: lyrics,
              dominantColor: widget.dominantColor,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBgColor = Color.alphaBlend(
      widget.dominantColor.withValues(alpha: 0.65),
      const Color(0xFF1E1E1E),
    );

    return FutureBuilder<Lyrics?>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final lyrics = snapshot.data;
        final hasLyrics = lyrics != null && !lyrics.isEmpty;

        return GestureDetector(
          onTap: hasLyrics ? () => _openFullScreenLyrics(context, lyrics) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header row: "Lyrics" + "MORE" / Expand pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n?.lyrics ?? 'Lyrics',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (hasLyrics)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MORE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              FluentIcons.arrow_expand_24_filled,
                              size: 13,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Card preview lines
                if (isLoading)
                  _buildLoadingPreview()
                else if (!hasLyrics)
                  _buildUnavailablePreview(context)
                else if (lyrics.synced != null && lyrics.synced!.isNotEmpty)
                  _buildSyncedPreview(lyrics)
                else
                  _buildPlainPreview(lyrics),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 220,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 160,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }

  Widget _buildUnavailablePreview(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        context.l10n?.lyricsNotAvailable ?? 'Lyrics not available for this song',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSyncedPreview(Lyrics lyrics) {
    final synced = lyrics.synced!;
    final activeIndex = lyrics.lineIndexAt(_currentPosition);
    final startIndex = max(0, activeIndex - 1);
    final endIndex = min(synced.length, startIndex + 3);
    final previewLines = synced.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: previewLines.map((line) {
        final isActive = synced.indexOf(line) == activeIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: isActive ? 19 : 16,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              height: 1.25,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlainPreview(Lyrics lyrics) {
    final lines = (lyrics.plain ?? '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(3)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FullScreenLyricsModal extends StatelessWidget {
  const _FullScreenLyricsModal({
    required this.metadata,
    required this.lyrics,
    required this.dominantColor,
  });

  final MediaItem metadata;
  final Lyrics lyrics;
  final Color dominantColor;

  @override
  Widget build(BuildContext context) {
    final topGradientColor = Color.alphaBlend(
      dominantColor.withValues(alpha: 0.8),
      const Color(0xFF121212),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              topGradientColor,
              const Color(0xFF121212),
            ],
            stops: const [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Bar: Dismiss Chevron + Song Title/Artist
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        FluentIcons.chevron_down_24_regular,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (metadata.artist != null)
                            Text(
                              metadata.artist!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Lyrics View
              Expanded(
                child: lyrics.synced != null && lyrics.synced!.isNotEmpty
                    ? SyncedLyricsView(lyrics: lyrics)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: Text(
                          lyrics.plain ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

