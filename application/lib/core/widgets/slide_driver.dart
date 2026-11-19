import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The continuous position of a row of pages while the user drags them sideways (like a `PageController`, without a
/// `PageView`). [pos] is 2.0 when page 2 fills the view and 2.4 when the drag has moved 40% of the way to page 3.
/// Pages sit side by side, so page `i` is drawn at `(i - pos) * width`: the page being left slides out while the next
/// one slides in from the opposite side, following the finger. On release it settles on the nearest page.
class SlideDriver extends ChangeNotifier {
  SlideDriver({
    required TickerProvider vsync,
    required int initial,
    required int count,
    required this.onSettled,
  }) : _base = initial,
       _pos = initial.toDouble(),
       _count = count {
    _controller =
        AnimationController(vsync: vsync)
          ..addListener(_tick)
          ..addStatusListener(_status);
  }

  /// Called once a settle onto a different page has finished, with that page's index.
  final ValueChanged<int> onSettled;

  /// A drag past this fraction of the width settles on the next page; so does a quick flick of at least
  /// [flingDistance] pixels.
  static const commitFraction = 0.35;
  static const flingSpeed = 700.0;
  static const flingDistance = 40.0;

  late final AnimationController _controller;
  int _base;
  double _pos;
  int _count;
  double _from = 0;
  double _to = 0;
  int _target = 0;

  /// The page the drag started from (the page that is laid out normally).
  int get base => _base;
  double get pos => _pos;
  int get count => _count;
  bool get animating => _controller.isAnimating;

  set count(int value) {
    if (value == _count) return;
    _count = value;
    if (_base >= _count) resetSilently(_count - 1);
  }

  /// Shows page [index] at once, with no movement.
  void jumpTo(int index) {
    _controller.stop();
    _base = index;
    _pos = index.toDouble();
    notifyListeners();
  }

  /// Same as [jumpTo] but without notifying listeners, for use while building (the listeners are built right after).
  void resetSilently(int index) {
    _controller.stop();
    _base = index;
    _pos = index.toDouble();
  }

  void dragStart() => _controller.stop();

  /// [dx] is the finger's movement in pixels (positive to the right); [width] is one page's width.
  void dragUpdate(double dx, double width) {
    if (width <= 0) return;
    final lo = math.max(0, _base - 1).toDouble();
    final hi = math.min(_count - 1, _base + 1).toDouble();
    final next = (_pos - dx / width).clamp(lo, hi);
    if (next == _pos) return;
    _pos = next;
    notifyListeners();
  }

  /// [velocity] is the finger's speed in pixels per second (negative to the left).
  void dragEnd(double velocity, double width) {
    final moved = _pos - _base;
    var target = _base;
    if (moved != 0 && width > 0) {
      final dir = moved > 0 ? 1 : -1;
      final flicked =
          velocity.abs() >= flingSpeed &&
          (velocity < 0) == (dir > 0) &&
          moved.abs() * width >= flingDistance;
      if (moved.abs() >= commitFraction || flicked) target = _base + dir;
    }
    _settle(target.clamp(0, _count - 1));
  }

  void _settle(int target) {
    _from = _pos;
    _to = target.toDouble();
    _target = target;
    if (_from == _to) {
      _finish();
      return;
    }
    _controller.duration = Duration(
      milliseconds: (90 + 190 * (_to - _from).abs()).round(),
    );
    _controller.forward(from: 0);
  }

  void _tick() {
    _pos = _from + (_to - _from) * Curves.easeOutCubic.transform(_controller.value);
    notifyListeners();
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    _pos = _to;
    final changed = _target != _base;
    _base = _target;
    notifyListeners();
    if (changed) onSettled(_target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
