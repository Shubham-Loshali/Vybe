import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/position_data.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/artwork_color_extractor.dart';
import 'package:vybe/utilities/artwork_provider.dart';
import 'package:vybe/utilities/lyrics_import.dart';
import 'package:vybe/widgets/now_playing/lyrics_backdrop.dart';
import 'package:vybe/widgets/now_playing/synced_lyrics_view.dart';

String _trackKey(MediaItem item) =>
    '${item.extras?['ytid'] ?? item.id}|${item.title}|${item.artist}|${item.album}|${item.duration}';

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
  late Future<Lyrics?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SpotifyLyricsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_trackKey(oldWidget.metadata) != _trackKey(widget.metadata)) _load();
  }

  void _load({bool forceRefresh = false}) {
    final item = widget.metadata;
    _lyricsFuture = item.extras?['isLive'] == true
        ? Future<Lyrics?>.value()
        : getSongLyricsResult(
            item.artist,
            item.title,
            duration: item.duration,
            album: item.album,
            videoId: item.extras?['ytid']?.toString(),
            forceRefresh: forceRefresh,
          );
  }

  void _open(Lyrics lyrics) {
    unawaited(
      Navigator.of(context).push<void>(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              FadeTransition(
                opacity: animation,
                child: _FullScreenLyricsPage(
                  metadata: widget.metadata,
                  lyrics: lyrics,
                  dominantColor: widget.dominantColor,
                ),
              ),
        ),
      ),
    );
  }

  Future<void> _import() async {
    final item = widget.metadata;
    final result = await importLyricsFile(context, item);
    if (!mounted ||
        result == null ||
        _trackKey(item) != _trackKey(widget.metadata))
      return;
    setState(() => _lyricsFuture = Future.value(result));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.metadata.extras?['isLive'] == true)
      return const SizedBox.shrink();
    return FutureBuilder<Lyrics?>(
      key: ValueKey(_trackKey(widget.metadata)),
      future: _lyricsFuture,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final result = loading ? null : snapshot.data;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LyricsBackdrop(
                    artwork: widget.metadata.artUri?.toString(),
                    color: widget.dominantColor,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: result == null ? null : () => _open(result),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.lyrics_outlined,
                                size: 20,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  context.l10n?.lyrics ?? 'Lyrics',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Add .lrc or .txt lyrics',
                                onPressed: () => unawaited(_import()),
                                icon: const Icon(
                                  Icons.note_add_outlined,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                              ),
                              if (result != null)
                                IconButton(
                                  tooltip: 'Expand lyrics',
                                  onPressed: () => _open(result),
                                  icon: const Icon(
                                    Icons.open_in_full_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (loading)
                            Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  context.l10n?.loading ?? 'Loading',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            )
                          else if (result == null)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.l10n?.lyricsNotAvailable ??
                                        'Lyrics not available',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Retry lyrics',
                                  onPressed: () =>
                                      setState(() => _load(forceRefresh: true)),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            )
                          else
                            ValueListenableBuilder<bool>(
                              valueListenable: syncedLyricsEnabled,
                              builder: (context, enabled, _) =>
                                  result.isSynced && enabled
                                  ? StreamBuilder<PositionData>(
                                      stream: audioHandler.positionDataStream,
                                      initialData:
                                          audioHandler.currentPositionData,
                                      builder: (context, position) => _preview(
                                        result,
                                        position.data?.position ??
                                            Duration.zero,
                                        synced: true,
                                      ),
                                    )
                                  : _preview(
                                      result,
                                      Duration.zero,
                                      synced: false,
                                    ),
                            ),
                          if (result != null) ...[
                            const SizedBox(height: 18),
                            Text(
                              result.isSynced
                                  ? 'Synced · ${result.source}'
                                  : 'Lyrics without timing · ${result.source}',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _preview(Lyrics lyrics, Duration position, {required bool synced}) {
    final active = synced ? lyrics.lineIndexAt(position) : -1;
    final lines = synced
        ? lyrics.synced!.map((l) => l.text.isEmpty ? '•••' : l.text).toList()
        : lyrics.text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final start = math.max(0, active - 1);
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 250),
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = start; i < math.min(lines.length, start + 3); i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                lines[i],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: !synced || active < 0 || i == active
                      ? Colors.white
                      : Colors.white60,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Subscribes to the current song so next/previous and automatic queue changes
/// never leave the expanded page displaying the previous song's lyrics.
class _FullScreenLyricsPage extends StatefulWidget {
  const _FullScreenLyricsPage({
    required this.metadata,
    required this.lyrics,
    required this.dominantColor,
  });
  final MediaItem metadata;
  final Lyrics lyrics;
  final Color dominantColor;

  @override
  State<_FullScreenLyricsPage> createState() => _FullScreenLyricsPageState();
}

class _FullScreenLyricsPageState extends State<_FullScreenLyricsPage> {
  late MediaItem _metadata;
  Lyrics? _lyrics;
  late Color _color;
  bool _loading = false;
  int _request = 0;
  StreamSubscription<MediaItem?>? _mediaSubscription;
  late final Stream<Duration> _positions = audioHandler.positionDataStream.map(
    (p) => p.position,
  );

  @override
  void initState() {
    super.initState();
    _metadata = widget.metadata;
    _lyrics = widget.lyrics;
    _color = widget.dominantColor;
    _mediaSubscription = audioHandler.mediaItem.listen((item) {
      if (item != null && _trackKey(item) != _trackKey(_metadata))
        unawaited(_load(item));
    });
  }

  Future<void> _load(MediaItem item, {bool forceRefresh = false}) async {
    final request = ++_request;
    setState(() {
      _metadata = item;
      _lyrics = null;
      _loading = true;
    });
    unawaited(
      ArtworkColorExtractor.extractDominantColor(item.artUri?.toString())
          .then((color) {
            if (mounted && request == _request) setState(() => _color = color);
          }),
    );
    Lyrics? result;
    try {
      if (item.extras?['isLive'] != true) {
        result = await getSongLyricsResult(
          item.artist,
          item.title,
          duration: item.duration,
          album: item.album,
          videoId: item.extras?['ytid']?.toString(),
          forceRefresh: forceRefresh,
        );
      }
    } catch (error, stack) {
      logger.log('Lyrics lookup failed', error: error, stackTrace: stack);
    }
    if (!mounted || request != _request) return;
    setState(() {
      _lyrics = result;
      _loading = false;
    });
  }

  Future<void> _import() async {
    final item = _metadata;
    final request = _request;
    final result = await importLyricsFile(context, item);
    if (!mounted ||
        result == null ||
        request != _request ||
        _trackKey(item) != _trackKey(_metadata))
      return;
    _request++;
    setState(() {
      _lyrics = result;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _request++;
    unawaited(_mediaSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0A10),
      body: Stack(
        fit: StackFit.expand,
        children: [
          LyricsBackdrop(artwork: _metadata.artUri?.toString(), color: _color),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _cover(44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _metadata.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _metadata.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add .lrc or .txt lyrics',
                        onPressed: () => unawaited(_import()),
                        icon: const Icon(
                          Icons.note_add_outlined,
                          size: 20,
                          color: Colors.white70,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Retry lyrics',
                        onPressed: _loading
                            ? null
                            : () => unawaited(
                                _load(_metadata, forceRefresh: true),
                              ),
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: _loading ? Colors.white24 : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) return _lyricsBody(30);
                      final coverSize = math.min(
                        constraints.maxWidth * 0.34,
                        constraints.maxHeight * 0.68,
                      );
                      return Row(
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * 0.42,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: _cover(coverSize),
                              ),
                            ),
                          ),
                          Expanded(child: _lyricsBody(36)),
                          const SizedBox(width: 24),
                        ],
                      );
                    },
                  ),
                ),
                _playbackControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(double size) {
    final artwork = _metadata.artUri?.toString();
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size > 100 ? 24 : 10),
        color: Colors.white12,
        boxShadow: [
          BoxShadow(
            color: _color.withValues(alpha: 0.4),
            blurRadius: 48,
            spreadRadius: 4,
          ),
        ],
      ),
      child: artwork == null || artwork.isEmpty
          ? const Icon(Icons.music_note_rounded, color: Colors.white60)
          : Image(
              image: ArtworkProvider.get(artwork),
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Icon(Icons.music_note_rounded, color: Colors.white60),
            ),
    );
  }

  Widget _lyricsBody(double fontSize) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
      );
    final lyrics = _lyrics;
    if (lyrics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lyrics_outlined,
                color: Colors.white60,
                size: 36,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n?.lyricsNotAvailable ?? 'Lyrics not available',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () =>
                    unawaited(_load(_metadata, forceRefresh: true)),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: syncedLyricsEnabled,
      builder: (context, enabled, _) {
        if (lyrics.isSynced && enabled) {
          return SyncedLyricsView(
            key: ValueKey(_trackKey(_metadata)),
            lyrics: lyrics,
            positionStream: _positions,
            initialPosition: audioHandler.currentPositionData.position,
            onSeek: (position) => unawaited(audioHandler.seek(position)),
            fontSize: fontSize,
          );
        }
        return SingleChildScrollView(
          key: ValueKey(_trackKey(_metadata)),
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lyrics.isSynced
                    ? 'Sync is turned off in settings'
                    : 'Lyrics without timing',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Text(
                lyrics.text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Lyrics · ${lyrics.source}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _playbackControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: StreamBuilder<PositionData>(
        stream: audioHandler.positionDataStream,
        initialData: audioHandler.currentPositionData,
        builder: (context, snapshot) {
          final data = snapshot.data!;
          final duration = data.duration > Duration.zero
              ? data.duration
              : (_metadata.duration ?? Duration.zero);
          final total = duration.inMilliseconds.toDouble();
          final position = data.position.inMilliseconds
              .toDouble()
              .clamp(0.0, math.max(0.0, total))
              .toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: position,
                  max: math.max(1, total),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  label: _time(Duration(milliseconds: position.round())),
                  onChanged: total <= 0
                      ? null
                      : (value) => unawaited(
                          audioHandler.seek(
                            Duration(milliseconds: value.round()),
                          ),
                        ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _time(data.position),
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  StreamBuilder<PlaybackState>(
                    stream: audioHandler.playbackState,
                    initialData: audioHandler.playbackState.value,
                    builder: (context, playback) {
                      final playing = playback.data?.playing ?? false;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Previous song',
                            onPressed: () =>
                                unawaited(audioHandler.skipToPrevious()),
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          IconButton(
                            tooltip: playing ? 'Pause' : 'Play',
                            onPressed: () => unawaited(
                              playing
                                  ? audioHandler.pause()
                                  : audioHandler.play(),
                            ),
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next song',
                            onPressed: () =>
                                unawaited(audioHandler.skipToNext()),
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  Text(
                    _time(duration),
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _time(Duration value) {
    final seconds = math.max(0, value.inSeconds);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
