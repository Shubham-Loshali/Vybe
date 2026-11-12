import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

/// Draws the opening at the device's resolution while Vybe initializes.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, this.failed = false});

  final bool failed;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _background = Color(0xFF050907);
  static const _green = Color(0xFF67F28C);
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );
  late final _ambient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  AudioPlayer? _openingPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.failed) unawaited(_playOpeningSound());
    });
  }

  Future<void> _playOpeningSound() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final player = AudioPlayer(
      handleInterruptions: false,
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    _openingPlayer = player;
    try {
      await player.setVolume(0.55);
      await player.setAsset('assets/audio/opening.mp3');
      final active = WidgetsBinding.instance.lifecycleState;
      if (!mounted ||
          widget.failed ||
          active != null && active != AppLifecycleState.resumed)
        return;
      await player.play();
    } catch (error, stackTrace) {
      developer.log(
        'Opening sound could not play',
        name: 'StartupSplash',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_openingPlayer?.stop());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(StartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.failed != widget.failed) {
      _updateMotion();
      if (widget.failed) unawaited(_openingPlayer?.stop());
    }
  }

  void _updateMotion() {
    if (MediaQuery.disableAnimationsOf(context) || widget.failed) {
      _entrance.value = 1;
      _ambient.stop();
    } else {
      if (!_entrance.isAnimating && !_entrance.isCompleted) _entrance.forward();
      if (!_ambient.isAnimating) _ambient.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_openingPlayer?.dispose());
    _entrance.dispose();
    _ambient.dispose();
    super.dispose();
  }

  double _reveal(double start, double end) => Curves.easeOutCubic.transform(
    ((_entrance.value - start) / (end - start)).clamp(0.0, 1.0),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _background,
        body: Semantics(
          label: widget.failed ? 'Vybe could not start' : 'Starting Vybe',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 450;
              final diameter = compact ? 154.0 : 244.0;
              return AnimatedBuilder(
                animation: Listenable.merge([_entrance, _ambient]),
                child: Image.asset(
                  'assets/icons/ic_launcher.png',
                  width: diameter * 0.70,
                  height: diameter * 0.70,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                builder: (context, logo) {
                  final breathe =
                      (1 - math.cos(_ambient.value * math.pi * 2)) / 2;
                  final reveal = _reveal(0, 0.70);
                  final title = _reveal(0.20, 0.88);
                  final bars = _reveal(0.48, 1);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // The glow stays behind the mark, without changing the
                      // layout or scaling a portrait video to a wide display.
                      Align(
                        alignment: const Alignment(0, -0.15),
                        child: IgnorePointer(
                          child: Container(
                            width: diameter * 1.85,
                            height: diameter * 1.85,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  _green.withValues(
                                    alpha: reveal * (0.075 + breathe * 0.025),
                                  ),
                                  _green.withValues(alpha: reveal * 0.018),
                                  Colors.transparent,
                                ],
                                stops: const [0, 0.42, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Transform.translate(
                              offset: Offset(0, compact ? 0 : -24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox.square(
                                    dimension: diameter,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Positioned.fill(
                                          child: Opacity(
                                            opacity: reveal,
                                            child: RepaintBoundary(
                                              child: CustomPaint(
                                                painter: _HaloPainter(
                                                  progress: _ambient.value,
                                                  reveal: reveal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Opacity(
                                          opacity: reveal,
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              12 * (1 - reveal),
                                            ),
                                            child: Transform.scale(
                                              scale:
                                                  0.90 +
                                                  0.10 * reveal +
                                                  0.008 * breathe,
                                              child: logo,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Opacity(
                                    opacity: title,
                                    child: Transform.translate(
                                      offset: Offset(0, 9 * (1 - title)),
                                      child: const Text(
                                        'Vybe',
                                        style: TextStyle(
                                          fontFamily: 'Figtree',
                                          color: Color(0xFFF1FAF3),
                                          fontSize: 42,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1.6,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: compact ? 18 : 28),
                                  if (widget.failed)
                                    const Text(
                                      'Couldn’t open Vybe. Close the app and try again.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white70),
                                    )
                                  else
                                    Opacity(
                                      opacity: bars,
                                      child: SizedBox(
                                        width: 76,
                                        height: 24,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            for (
                                              var index = 0;
                                              index < 7;
                                              index++
                                            )
                                              Container(
                                                width: 3,
                                                height:
                                                    5 +
                                                    (15 -
                                                            (index - 3).abs() *
                                                                2) *
                                                        (0.5 +
                                                            0.5 *
                                                                math.sin(
                                                                  _ambient.value *
                                                                          4 *
                                                                          math.pi -
                                                                      index *
                                                                          0.72,
                                                                )),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _green.withValues(
                                                    alpha:
                                                        0.65 + 0.25 * breathe,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.progress, required this.reveal});

  final double progress;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.43;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = const Color(0xFF65E88B).withValues(alpha: 0.09);
    canvas.drawCircle(center, radius, track);
    final angle = -math.pi / 2 + progress * math.pi * 2;
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(angle),
        colors: [
          const Color(0xFF73FFA1).withValues(alpha: 0),
          const Color(0xFF73FFA1).withValues(alpha: 0.02),
          const Color(0xFF73FFA1).withValues(alpha: 0.72 * reveal),
        ],
        stops: const [0, 0.70, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle + math.pi,
      math.pi * reveal,
      false,
      sweep,
    );
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      1.8,
      Paint()..color = const Color(0xFF9AFBB5).withValues(alpha: 0.85 * reveal),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.reveal != reveal;
}
