import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/full_player_state.dart';
import 'package:vybe/models/position_data.dart';
import 'package:vybe/screens/now_playing_page.dart';
import 'package:vybe/utilities/artwork_color_extractor.dart';
import 'package:vybe/utilities/player_colors.dart';
import 'package:vybe/widgets/marquee.dart';
import 'package:vybe/widgets/song_artwork.dart';

final Stream<FullPlayerState> _fullPlayerStateStream =
    Rx.combineLatest3(
          audioHandler.playbackStateStream,
          audioHandler.queue.distinct(),
          audioHandler.positionDataStream,
          (PlaybackState state, List<MediaItem> queue, PositionData pos) =>
              FullPlayerState(
                playbackState: state,
                queue: queue,
                position: pos,
              ),
        )
        .throttleTime(const Duration(milliseconds: 120), trailing: true)
        .asBroadcastStream();

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const double playerHeight = 72;
  static const double _borderRadius = 8;
  static const double _artworkSize = 52;
  static const double _artworkRadius = 6;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, mediaSnapshot) {
          final metadata = mediaSnapshot.data;
          if (metadata == null) return const SizedBox.shrink();

          return StreamBuilder<FullPlayerState>(
            stream: _fullPlayerStateStream,
            builder: (context, stateSnapshot) {
              final state = stateSnapshot.data;
              if (state == null) return const SizedBox.shrink();

              final hasNext =
                  state.queue.length > 1 &&
                  (state.playbackState.queueIndex ?? 0) <
                      state.queue.length - 1;

              return _MiniPlayerBody(
                colorScheme: colorScheme,
                metadata: metadata,
                state: state,
                hasNext: hasNext,
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniPlayerBody extends StatefulWidget {
  const _MiniPlayerBody({
    required this.colorScheme,
    required this.metadata,
    required this.state,
    required this.hasNext,
  });

  final ColorScheme colorScheme;
  final MediaItem metadata;
  final FullPlayerState state;
  final bool hasNext;

  @override
  State<_MiniPlayerBody> createState() => _MiniPlayerBodyState();
}

class _MiniPlayerBodyState extends State<_MiniPlayerBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  Color? _tint;
  String? _tintArtwork;

  void _updateTint() {
    final uri = widget.metadata.artUri?.toString();
    if (uri == _tintArtwork) return;
    _tintArtwork = uri;
    _tint = null;
    if (uri == null) return;
    ArtworkColorExtractor.extractDominantColor(uri).then((color) {
      if (mounted && _tintArtwork == uri) setState(() => _tint = color);
    });
  }

  @override
  void didUpdateWidget(covariant _MiniPlayerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTint();
  }

  @override
  void initState() {
    super.initState();
    _updateTint();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  static const double _dragThresholdForNavigation = 10;

  void _handleVerticalDrag(DragUpdateDetails details) {
    if ((details.primaryDelta ?? 0) < -_dragThresholdForNavigation) {
      _navigateToNowPlaying();
    }
  }

  void _navigateToNowPlaying() {
    Navigator.of(context).push(_createSlideTransition());
  }

  PageRoute<void> _createSlideTransition() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, _) => const NowPlayingPage(),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final metadata = widget.metadata;
    final state = widget.state;

    final totalDuration = state.position.duration > Duration.zero
        ? state.position.duration
        : (metadata.duration ?? Duration.zero);
    final progress = totalDuration.inMilliseconds == 0
        ? 0.0
        : (state.position.position.inMilliseconds /
                  totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: (_) => _animationController.forward(),
            onTapUp: (_) => _animationController.reverse(),
            onTapCancel: () => _animationController.reverse(),
            onVerticalDragUpdate: _handleVerticalDrag,
            onTap: _navigateToNowPlaying,
            child: Container(
              height: MiniPlayer.playerHeight,
              decoration: BoxDecoration(
                color: miniPlayerSurface(
                  _tint ?? colorScheme.surfaceContainerHigh,
                ),
                borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          _ArtworkWidget(metadata: metadata),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey(
                                '${metadata.extras?['ytid']}|${metadata.title}|${metadata.artist}',
                              ),
                              child: _MetadataWidget(
                                title: metadata.title,
                                artist: metadata.artist,
                                colorScheme: colorScheme,
                              ),
                            ),
                          ),
                          _ControlsWidget(
                            colorScheme: colorScheme,
                            playbackState: state.playbackState,
                            hasNext: widget.hasNext,
                            progress: progress,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkWidget extends StatelessWidget {
  const _ArtworkWidget({required this.metadata});
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Hero(
        tag: 'now_playing_artwork',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiniPlayer._artworkRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SongArtworkWidget(
            metadata: metadata,
            size: MiniPlayer._artworkSize,
            errorWidgetIconSize: 24,
            borderRadius: MiniPlayer._artworkRadius,
          ),
        ),
      ),
    );
  }
}

class _MetadataWidget extends StatelessWidget {
  const _MetadataWidget({
    required this.title,
    required this.artist,
    required this.colorScheme,
  });

  final String title;
  final String? artist;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeWidget(
            manualScrollEnabled: false,
            animationDuration: const Duration(seconds: 8),
            backDuration: const Duration(seconds: 2),
            pauseDuration: const Duration(seconds: 2),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (artist != null && artist!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              artist!,
              style: const TextStyle(
                color: Color(0xFFD9D9D9),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlsWidget extends StatelessWidget {
  const _ControlsWidget({
    required this.colorScheme,
    required this.playbackState,
    required this.hasNext,
    required this.progress,
  });

  final ColorScheme colorScheme;
  final PlaybackState playbackState;
  final bool hasNext;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircularPlayButton(
          colorScheme: colorScheme,
          playbackState: playbackState,
          progress: progress,
        ),
        if (hasNext) ...[
          IconButton(
            onPressed: audioHandler.skipToNext,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            icon: const Icon(
              FluentIcons.next_24_filled,
              color: Colors.white,
              size: 24,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

class _CircularPlayButton extends StatelessWidget {
  const _CircularPlayButton({
    required this.colorScheme,
    required this.playbackState,
    required this.progress,
  });

  final ColorScheme colorScheme;
  final PlaybackState playbackState;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final processingState = playbackState.processingState;
    final isPlaying = playbackState.playing;
    final isLoading =
        processingState == AudioProcessingState.loading ||
        processingState == AudioProcessingState.buffering;
    final isCompleted = processingState == AudioProcessingState.completed;

    if (isLoading) {
      return const SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    return IconButton(
      onPressed: isCompleted
          ? () => audioHandler.playAgain()
          : (isPlaying ? audioHandler.pause : audioHandler.play),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      icon: Icon(
        isCompleted
            ? FluentIcons.arrow_counterclockwise_24_filled
            : (isPlaying
                  ? FluentIcons.pause_24_filled
                  : FluentIcons.play_24_filled),
        color: Colors.white,
        size: 26,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
