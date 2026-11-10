import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Thin horizontal progress bar.
class MeterBar extends StatelessWidget {
  const MeterBar({super.key, required this.value, this.color, this.trackColor, this.height = 8});

  final double value; // 0..1
  final Color? color;
  final Color? trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth * value.clamp(0.0, 1.0);
          return Stack(children: [
            Positioned.fill(child: ColoredBox(color: trackColor ?? p.tile)),
            Positioned(left: 0, top: 0, bottom: 0, width: w, child: ColoredBox(color: color ?? p.link)),
          ]);
        }),
      ),
    );
  }
}

/// "Energy ===== 8/10": label, bar and a value at the right.
class MeterRow extends StatelessWidget {
  const MeterRow({
    super.key,
    required this.label,
    required this.value,
    required this.trailing,
    this.color,
    this.labelWidth = 92,
    this.trailingWidth = 52,
  });

  final String label;
  final double value;
  final String trailing;
  final Color? color;
  final double labelWidth;
  final double trailingWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(width: labelWidth, child: Text(label, style: TextStyle(color: p.muted, fontSize: 14.5))),
        Expanded(child: MeterBar(value: value, color: color)),
        SizedBox(
          width: trailingWidth,
          child: Text(trailing, textAlign: TextAlign.right, style: TextStyle(color: p.text, fontSize: 14.5)),
        ),
      ]),
    );
  }
}

/// Five dots for a 1 to 5 rating.
class DotRating extends StatelessWidget {
  const DotRating(this.value, {super.key});
  final int value;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 5; i++)
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: i < value ? p.link : p.tile),
        ),
    ]);
  }
}

/// Circular gauge with a value in the middle.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.value,
    required this.centerText,
    this.subText,
    this.size = 112,
    this.stroke = 10,
    this.color,
  });

  final double value; // 0..1
  final String centerText;
  final String? subText;
  final double size;
  final double stroke;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0.0, 1.0), color ?? p.link, p.tile, stroke),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerText, style: TextStyle(color: p.text, fontSize: size * 0.2, fontWeight: FontWeight.w800)),
            if (subText != null) Text(subText!, style: TextStyle(color: p.muted, fontSize: size * 0.12)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

TextPainter _label(String text, Color color, double size, {FontWeight weight = FontWeight.w400}) {
  return TextPainter(
    text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
}

/// Line chart with horizontal grid lines, y labels at the left and x labels below.
class LineChartView extends StatelessWidget {
  const LineChartView({
    super.key,
    required this.values,
    required this.xLabels,
    required this.yMin,
    required this.yMax,
    required this.yTicks,
    this.height = 170,
  });

  final List<double> values;
  final List<String> xLabels;
  final double yMin;
  final double yMax;
  final List<double> yTicks;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _LinePainter(values, xLabels, yMin, yMax, yTicks, p.link, p.divider, p.muted)),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.xLabels, this.yMin, this.yMax, this.yTicks, this.line, this.grid, this.text);
  final List<double> values;
  final List<String> xLabels;
  final double yMin;
  final double yMax;
  final List<double> yTicks;
  final Color line;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const bottom = 24.0;
    const top = 6.0;
    final plot = Rect.fromLTRB(left, top, size.width - 6, size.height - bottom);
    final range = (yMax - yMin) == 0 ? 1.0 : (yMax - yMin);
    double yOf(double v) => plot.bottom - (v - yMin) / range * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final t in yTicks) {
      final y = yOf(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final tp = _label(t.toStringAsFixed(0), text, 11);
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }
    if (values.isEmpty) return;
    final n = values.length;
    double xOf(int i) => n == 1 ? plot.center.dx : plot.left + 8 + i * (plot.width - 16) / (n - 1);

    final path = Path();
    for (var i = 0; i < n; i++) {
      final pt = Offset(xOf(i), yOf(values[i]));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = line;
    if (n <= 8) {
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(Offset(xOf(i), yOf(values[i])), 3.4, dot);
      }
    }
    for (var i = 0; i < xLabels.length && i < n; i++) {
      final tp = _label(xLabels[i], text, 11);
      tp.paint(canvas, Offset(xOf(i) - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.line != line || old.grid != grid || old.text != text || old.yMin != yMin || old.yMax != yMax;
}

/// Vertical bars with a value above and a label below each.
class BarChartView extends StatelessWidget {
  const BarChartView({
    super.key,
    required this.values,
    required this.labels,
    required this.maxValue,
    this.colors,
    this.height = 140,
    this.showValues = true,
    this.barWidth = 22,
  });

  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final List<Color>? colors;
  final double height;
  final bool showValues;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (showValues)
                Text(_fmt(values[i]), style: TextStyle(color: p.muted, fontSize: 11)),
              const SizedBox(height: 4),
              Container(
                width: barWidth,
                height: math.max(4, (height - 44) * (values[i] / maxValue).clamp(0.0, 1.0)),
                decoration: BoxDecoration(
                  color: colors != null && i < colors!.length ? colors![i] : p.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i], style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
      ]),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Spider chart for self-assessed muscle groups. Values are 0..1.
class RadarChartView extends StatelessWidget {
  const RadarChartView({super.key, required this.labels, required this.values, this.height = 300});

  final List<String> labels;
  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _RadarPainter(labels, values, p.link, p.divider, p.muted)),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.labels, this.values, this.accent, this.grid, this.text);
  final List<String> labels;
  final List<double> values;
  final Color accent;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n < 3) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 38;
    Offset point(int i, double r) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return center + Offset(math.cos(a), math.sin(a)) * r;
    }

    final gridPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [0.34, 0.67, 1.0]) {
      final ring = Path();
      for (var i = 0; i < n; i++) {
        final pt = point(i, radius * f);
        if (i == 0) {
          ring.moveTo(pt.dx, pt.dy);
        } else {
          ring.lineTo(pt.dx, pt.dy);
        }
      }
      ring.close();
      canvas.drawPath(ring, gridPaint);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, point(i, radius), gridPaint);
    }

    final shape = Path();
    for (var i = 0; i < n; i++) {
      final v = (i < values.length ? values[i] : 0.0).clamp(0.0, 1.0);
      final pt = point(i, radius * v);
      if (i == 0) {
        shape.moveTo(pt.dx, pt.dy);
      } else {
        shape.lineTo(pt.dx, pt.dy);
      }
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = accent.withValues(alpha: 0.22));
    canvas.drawPath(
      shape,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < n; i++) {
      final tp = _label(labels[i], text, 13);
      final pt = point(i, radius + 20);
      tp.paint(canvas, pt - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.values != values || old.accent != accent || old.labels != labels;
}
