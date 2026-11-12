import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/widgets/now_playing/karaoke_lyric_text.dart';

/// Follows the playback clock without changing the height of wrapped lines.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.onSeek,
    this.initialPosition = Duration.zero,
    this.foregroundColor = Colors.white,
    this.fontSize = 30,
  });

  final Lyrics lyrics;
  final Stream<Duration> positionStream;
  final ValueChanged<Duration> onSeek;
  final Duration initialPosition;
  final Color foregroundColor;
  final double fontSize;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  static const _followAlignment = 0.20;
  static const _offsetStep = Duration(milliseconds: 500);
  static const _manualScrollPause = Duration(seconds: 4);
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _resumeTimer;
  List<GlobalKey> _lineKeys = [];
  final _lyricPosition = ValueNotifier(Duration.zero);
  Duration _position = Duration.zero;
  Duration _offset = Duration.zero;
  int _activeIndex = -1;
  bool _following = true;
  bool _scrollScheduled = false;
  bool _jumpToActive = false;

  List<LyricLine> get _lines => widget.lyrics.synced ?? const [];

  @override
  void initState() {
    super.initState();
    _resetLyrics();
    _listen();
  }

  void _listen() {
    _positionSubscription = widget.positionStream.listen((position) {
      _position = position;
      if (!mounted) return;
      _lyricPosition.value = position + _offset;
      final index = widget.lyrics.lineIndexAt(_lyricPosition.value);
      if (index == _activeIndex) return;
      final nearby = (_activeIndex - index).abs() <= 5;
      setState(() => _activeIndex = index);
      _scrollToActive(animate: nearby);
    });
  }

  void _resetLyrics() {
    _resumeTimer?.cancel();
    _lineKeys = List.generate(_lines.length, (_) => GlobalKey());
    _position = widget.initialPosition;
    _offset = Duration.zero;
    _lyricPosition.value = _position;
    _following = true;
    _activeIndex = widget.lyrics.lineIndexAt(_position);
    _scrollToActive(animate: false);
  }

  @override
  void didUpdateWidget(SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics)) _resetLyrics();
    if (oldWidget.positionStream != widget.positionStream) {
      unawaited(_positionSubscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    unawaited(_positionSubscription?.cancel());
    _scrollController.dispose();
    _lyricPosition.dispose();
    super.dispose();
  }

  void _scrollToActive({bool animate = true}) {
    _jumpToActive |= !animate;
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      final jump = _jumpToActive;
      _jumpToActive = false;
      if (!mounted ||
          !_following ||
          !_scrollController.hasClients ||
          _lineKeys.isEmpty)
        return;
      final index = math.max(0, _activeIndex);
      if (index >= _lineKeys.length) return;
      final line = _lineKeys[index].currentContext?.findRenderObject();
      if (line == null) return;
      unawaited(
        _scrollController.position.ensureVisible(
          line,
          alignment: _followAlignment,
          duration: jump || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 510),
          curve: Curves.easeOutQuart,
        ),
      );
    });
  }

  void _resumeFollowing() {
    _resumeTimer?.cancel();
    setState(() => _following = true);
    _scrollToActive();
  }

  void _changeOffset(Duration? delta) {
    setState(() {
      _offset = delta == null ? Duration.zero : _offset + delta;
      _lyricPosition.value = _position + _offset;
      _activeIndex = widget.lyrics.lineIndexAt(_lyricPosition.value);
    });
    _resumeFollowing();
  }

  void _seekToLine(LyricLine line) {
    final target = line.start - _offset;
    widget.onSeek(target.isNegative ? Duration.zero : target);
    _resumeFollowing();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.foregroundColor;
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _resumeTimer?.cancel();
                setState(() => _following = false);
              } else if (notification is ScrollEndNotification && !_following) {
                _resumeTimer?.cancel();
                _resumeTimer = Timer(_manualScrollPause, _resumeFollowing);
              }
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final edgePadding = constraints.maxHeight * _followAlignment;
                return ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, 0.08, 0.9, 1],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      edgePadding,
                      20,
                      edgePadding,
                    ),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < _lines.length; i++) _buildLine(i),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 28, 12, 0),
                          child: Text(
                            'Lyrics · ${widget.lyrics.source}',
                            style: TextStyle(
                              fontSize: 12,
                              color: color.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (!_following)
          TextButton.icon(
            onPressed: _resumeFollowing,
            icon: const Icon(Icons.my_location_rounded, size: 16),
            label: const Text('Follow song'),
            style: TextButton.styleFrom(foregroundColor: color),
          ),
        _buildOffsetControls(),
      ],
    );
  }

  Widget _buildLine(int index) {
    final isActive = index == _activeIndex;
    final distance = (index - _activeIndex).abs();
    final color = widget.foregroundColor;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return Semantics(
      selected: isActive,
      button: true,
      label: _lines[index].text.isEmpty
          ? 'Instrumental break'
          : _lines[index].text,
      child: GestureDetector(
        key: _lineKeys[index],
        behavior: HitTestBehavior.opaque,
        onTap: () => _seekToLine(_lines[index]),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
              fontSize: widget.fontSize,
              height: 1.45,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: color.withValues(
                alpha: isActive ? 1 : (distance <= 1 ? 0.51 : 0.36),
              ),
            ),
            child: isActive
                ? ValueListenableBuilder<Duration>(
                    valueListenable: _lyricPosition,
                    builder: (context, position, _) => KaraokeLyricText(
                      line: _lines[index],
                      position: position,
                      nextStart: index + 1 < _lines.length
                          ? _lines[index + 1].start
                          : null,
                      style: TextStyle(color: color),
                    ),
                  )
                : Text(_lines[index].text.isEmpty ? '•••' : _lines[index].text),
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetControls() {
    final seconds = _offset.inMilliseconds / 1000;
    final label = '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
    final color = widget.foregroundColor.withValues(alpha: 0.8);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Show lyrics later',
          color: color,
          icon: const Icon(Icons.remove_rounded, size: 20),
          onPressed: () => _changeOffset(-_offsetStep),
        ),
        Flexible(
          child: TextButton(
            onPressed: () => _changeOffset(null),
            style: TextButton.styleFrom(foregroundColor: color),
            child: Text(
              'Timing $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Show lyrics earlier',
          color: color,
          icon: const Icon(Icons.add_rounded, size: 20),
          onPressed: () => _changeOffset(_offsetStep),
        ),
      ],
    );
  }
}
