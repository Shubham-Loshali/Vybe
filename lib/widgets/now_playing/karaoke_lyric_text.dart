import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';

/// Fills each word over its timing window and keeps earlier words readable.
class KaraokeLyricText extends StatefulWidget {
  const KaraokeLyricText({
    super.key,
    required this.line,
    required this.position,
    this.nextStart,
    this.style,
    this.maxLines,
  });

  final LyricLine line;
  final Duration position;
  final Duration? nextStart;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<KaraokeLyricText> createState() => _KaraokeLyricTextState();
}

class _KaraokeLyricTextState extends State<KaraokeLyricText>
    with SingleTickerProviderStateMixin {
  static final _pieces = RegExp(r'\S+|\s+');
  static const _seekThreshold = 300;

  late final _clock = AnimationController.unbounded(vsync: this);
  late List<({String text, int? word})> _tokens;
  late List<double> _starts;
  late List<double> _ends;
  late String _translation;
  bool _reduceMotion = false;

  double get _position => widget.position.inMicroseconds / 1000;

  @override
  void initState() {
    super.initState();
    _layoutTiming();
    _clock.value = _position;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _clock.value = _position;
  }

  @override
  void didUpdateWidget(KaraokeLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.line != oldWidget.line ||
        widget.nextStart != oldWidget.nextStart) {
      _layoutTiming();
      _clock.value = _position;
      return;
    }

    final delta = (widget.position - oldWidget.position).inMicroseconds / 1000;
    if (delta == 0) return;
    if (_reduceMotion || delta < 0 || delta > _seekThreshold) {
      _clock.value = _position;
      return;
    }
    // Bridge playback samples with short linear motion. The controller stops
    // at the latest sample, so highlighting cannot drift while paused.
    _clock.animateTo(
      _position,
      duration: Duration(milliseconds: delta.round().clamp(16, 95)),
    );
  }

  void _layoutTiming() {
    final text = widget.line.text;
    final firstBreak = text.indexOf('\n');
    final primary = firstBreak < 0 ? text : text.substring(0, firstBreak);
    _translation = firstBreak < 0 ? '' : text.substring(firstBreak);
    var count = 0;
    _tokens = [
      for (final match in _pieces.allMatches(primary))
        (
          text: match.group(0)!,
          word: match.group(0)!.trim().isEmpty ? null : count++,
        ),
    ];
    final start = widget.line.start.inMicroseconds / 1000;
    final window = widget.nextStart == null
        ? count * 390.0
        : widget.nextStart!.inMicroseconds / 1000 - start;
    final estimatedDuration = math.min(window, math.max(650, count * 650));
    final cues = {
      for (final cue in widget.line.wordCues)
        cue.wordIndex: cue.start.inMicroseconds / 1000,
    };
    _starts = List<double>.filled(count, start);
    for (var word = 0; word < count; word++) {
      _starts[word] =
          cues[word] ??
          (cues.isEmpty
              ? start + estimatedDuration * word / count
              : word == 0
              ? start
              : _starts[word - 1]);
    }
    _ends = List.generate(count, (word) {
      final following = word + 1 < count
          ? _starts[word + 1]
          : start + (cues.isEmpty ? estimatedDuration : window);
      return _starts[word] + (following - _starts[word]).clamp(65, 720);
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.style?.color ??
        DefaultTextStyle.of(context).style.color ??
        Colors.white;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final now = _clock.value;
        if (widget.line.text.isEmpty) {
          return Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < 3; i++)
                  TextSpan(
                    text: i == 0 ? '•' : ' •',
                    style: TextStyle(
                      color: color.withValues(
                        alpha: _reduceMotion
                            ? 0.8
                            : 0.55 +
                                  0.38 *
                                      (0.5 +
                                          0.5 * math.sin(now / 220 - i * 1.1)),
                      ),
                    ),
                  ),
              ],
            ),
            style: widget.style,
          );
        }

        return Text.rich(
          TextSpan(
            children: [
              for (final token in _tokens)
                TextSpan(
                  text: token.text,
                  style: token.word == null
                      ? null
                      : _wordStyle(color, token.word!, now),
                ),
              if (_translation.isNotEmpty)
                TextSpan(
                  text: _translation,
                  style: TextStyle(color: color.withValues(alpha: 0.65)),
                ),
            ],
          ),
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
        );
      },
    );
  }

  TextStyle _wordStyle(Color color, int word, double position) {
    final start = _starts[word];
    final end = _ends[word];
    final ramp = ((position - start) / (end - start)).clamp(0.0, 1.0);
    final glowIn = ((position - start) / 85).clamp(0.0, 1.0);
    final glowOut = ((end + 130 - position) / 160).clamp(0.0, 1.0);
    final glow = _reduceMotion ? 0.0 : glowIn * glowOut;
    final fill = _reduceMotion
        ? (position >= start ? 1.0 : 0.0)
        : Curves.easeOut.transform(ramp);
    return TextStyle(
      color: color.withValues(alpha: 0.54 + 0.46 * fill),
      shadows: glow > 0.02
          ? [
              Shadow(
                color: color.withValues(alpha: 0.46 * glow),
                blurRadius: 11,
              ),
            ]
          : const [],
    );
  }
}
