import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Scroll only overflowing content. Content changes reset to the first word,
/// and every delayed action is cancelled when the widget leaves the screen.
class MarqueeWidget extends StatefulWidget {
  const MarqueeWidget({
    super.key,
    required this.child,
    this.direction = Axis.horizontal,
    this.animationDuration = const Duration(milliseconds: 6000),
    this.backDuration = const Duration(milliseconds: 800),
    this.pauseDuration = const Duration(milliseconds: 800),
    this.manualScrollEnabled = true,
  });

  final Widget child;
  final Axis direction;
  final Duration animationDuration, backDuration, pauseDuration;
  final bool manualScrollEnabled;

  @override
  State<MarqueeWidget> createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;
  int _generation = 0;
  bool _scheduled = false;
  bool _needsReset = true;
  bool _animating = false;
  bool _dragging = false;
  double _lastExtent = -1;
  double _lastViewport = -1;

  @override
  void initState() {
    super.initState();
    _measureAfterLayout(reset: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureAfterLayout(reset: true);
  }

  @override
  void didUpdateWidget(MarqueeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldText = oldWidget.child;
    final newText = widget.child;
    final changed = oldText is Text && newText is Text
        ? oldText.data != newText.data ||
              oldText.textSpan != newText.textSpan ||
              oldText.style != newText.style
        : oldText.runtimeType != newText.runtimeType ||
              oldText.key != newText.key;
    _measureAfterLayout(
      reset:
          changed ||
          oldWidget.direction != widget.direction ||
          oldWidget.animationDuration != widget.animationDuration ||
          oldWidget.backDuration != widget.backDuration ||
          oldWidget.pauseDuration != widget.pauseDuration,
    );
  }

  void _cancelCycle() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _animating = false;
  }

  void _measureAfterLayout({bool reset = false}) {
    _needsReset = _needsReset || reset;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final changed =
          (_lastExtent - position.maxScrollExtent).abs() > 0.5 ||
          (_lastViewport - position.viewportDimension).abs() > 0.5;
      _lastExtent = position.maxScrollExtent;
      _lastViewport = position.viewportDimension;
      if (_needsReset || changed) {
        _cancelCycle();
        _needsReset = false;
        if (position.pixels != 0) _controller.jumpTo(0);
      }
      if (_dragging ||
          !TickerMode.valuesOf(context).enabled ||
          MediaQuery.disableAnimationsOf(context) ||
          position.maxScrollExtent <= 0.5) {
        _cancelCycle();
        return;
      }
      if (_timer == null && !_animating)
        _queueScroll(toEnd: true, generation: _generation);
    });
  }

  void _queueScroll({required bool toEnd, required int generation}) {
    final pause = widget.pauseDuration > Duration.zero
        ? widget.pauseDuration
        : const Duration(milliseconds: 100);
    _timer = Timer(pause, () {
      _timer = null;
      unawaited(_scroll(toEnd: toEnd, generation: generation));
    });
  }

  Future<void> _scroll({required bool toEnd, required int generation}) async {
    if (!mounted || generation != _generation || !_controller.hasClients)
      return;
    _animating = true;
    try {
      final target = toEnd ? _controller.position.maxScrollExtent : 0.0;
      final duration = toEnd ? widget.animationDuration : widget.backDuration;
      if (duration <= Duration.zero) {
        _controller.jumpTo(target);
      } else {
        await _controller.animateTo(
          target,
          duration: duration,
          curve: toEnd ? Curves.linear : Curves.easeOut,
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        _animating = false;
        _queueScroll(toEnd: !toEnd, generation: generation);
      }
    }
  }

  @override
  void dispose() {
    _cancelCycle();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _measureAfterLayout();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _dragging = true;
              _cancelCycle();
            } else if (notification is ScrollEndNotification && _dragging) {
              _dragging = false;
              _measureAfterLayout();
            }
            return false;
          },
          child: RepaintBoundary(
            child: SingleChildScrollView(
              scrollDirection: widget.direction,
              controller: _controller,
              physics: widget.manualScrollEnabled
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: widget.child,
            ),
          ),
        ),
      );
}
