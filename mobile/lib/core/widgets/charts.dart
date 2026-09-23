import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../models/records.dart';
import '../theme.dart';

/*
 * The academy's figures, hand-drawn like the web dashboard's (web/components/
 * charts.tsx) and following the same rules: 2px lines, markers of at least
 * 8px with a 2px surface ring, hairline gridlines, and text in ink — never in
 * the series colour, which is unreadable at label size.
 *
 * Everything reads right to left, like the rest of the app: on a time axis the
 * oldest point sits at the right edge, where an Arabic reader starts.
 */

const _grid = Color(0xFFE9F0EF);
const _axis = Color(0xFFCFDCDB);

TextPainter _label(String text, {double size = 10.5, Color color = AppColors.muted, FontWeight weight = FontWeight.w600}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Cairo', fontSize: size, color: color, fontWeight: weight, height: 1.2),
    ),
    textDirection: TextDirection.rtl,
  )..layout();
}

/// One goal from its baseline forward, on the 0..4 prompt scale.
///
/// The axis is pinned at 0..4. Progress on this scale creeps — half a step
/// over a term is a real result — and zooming the axis to make it look bigger
/// is the prettiest way to lie with it.
class GoalCurveChart extends StatelessWidget {
  const GoalCurveChart({super.key, required this.curve, this.height = 210});

  final GoalCurve curve;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CurvePainter(curve)),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.curve);

  final GoalCurve curve;

  @override
  void paint(Canvas canvas, Size size) {
    const right = 26.0; // the level labels
    const left = 8.0;
    const top = 10.0;
    const bottom = 24.0; // the dates

    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    double y(int level) => plot.bottom - (level / 4) * plot.height;

    final grid = Paint()
      ..color = _grid
      ..strokeWidth = 1;

    for (var level = 0; level <= 4; level++) {
      canvas.drawLine(Offset(plot.left, y(level)), Offset(plot.right, y(level)), grid);
      final tp = _label('$level');
      tp.paint(canvas, Offset(plot.right + 8, y(level) - tp.height / 2));
    }

    // The target — where the goal counts as met.
    final target = curve.goal.target;
    if (target != null) {
      final paint = Paint()
        ..color = AppColors.warn.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(plot.left, y(target)), Offset(plot.right, y(target)), paint);
      final tp = _label('الهدف', color: AppColors.warn, size: 10);
      tp.paint(canvas, Offset(plot.left + 2, y(target) - tp.height - 1));
    }

    // Baseline first, so the line starts where the child started — without it
    // every goal looks like it began wherever it was first measured.
    final levels = [curve.goal.baseline, ...curve.points.map((p) => p.level)];
    final dates = [curve.baselineDate, ...curve.points.map((p) => p.date)];

    if (levels.length == 1) {
      _dot(canvas, Offset(plot.right - plot.width / 2, y(levels.first)), levels.first, hollow: true);
      return;
    }

    // Right to left: index 0 (the baseline) at the right edge.
    double x(int i) => plot.right - (i / (levels.length - 1)) * plot.width;

    final line = Paint()
      ..color = AppColors.viz
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(x(0), y(levels[0]));
    for (var i = 1; i < levels.length; i++) {
      path.lineTo(x(i), y(levels[i]));
    }
    canvas.drawPath(path, line);

    // Markers thin out on a long history, so they never become a solid bead.
    final everyMarker = levels.length <= 24;
    for (var i = 0; i < levels.length; i++) {
      if (everyMarker || i == 0 || i == levels.length - 1) {
        _dot(canvas, Offset(x(i), y(levels[i])), levels[i], hollow: i == 0);
      }
    }

    // First and last date only; a label under every point is a smear.
    final first = _label(Fmt.shortDate(dates.first), size: 10);
    first.paint(canvas, Offset(math.max(plot.right - first.width, 0), plot.bottom + 6));
    final last = _label(Fmt.shortDate(dates.last), size: 10);
    last.paint(canvas, Offset(plot.left, plot.bottom + 6));
  }

  void _dot(Canvas canvas, Offset at, int level, {bool hollow = false}) {
    canvas.drawCircle(at, 6, Paint()..color = Colors.white);
    if (hollow) {
      canvas.drawCircle(
        at,
        4.5,
        Paint()
          ..color = AppColors.leaf
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else {
      canvas.drawCircle(at, 4.5, Paint()..color = LevelColors.fill(level));
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => old.curve != curve;
}

/// A weekly series of stacked counts — held, absent, excused.
class StackedWeekBars extends StatelessWidget {
  const StackedWeekBars({super.key, required this.weeks, required this.series, this.height = 170});

  /// Oldest first, as the API sends them. Drawn oldest at the right.
  final List<String> weeks;

  /// (colour, values per week), bottom of the stack first.
  final List<(Color, List<int>)> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarsPainter(weeks, series)),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.weeks, this.series);

  final List<String> weeks;
  final List<(Color, List<int>)> series;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;

    const bottom = 20.0;
    const top = 8.0;
    final plot = Rect.fromLTRB(0, top, size.width, size.height - bottom);

    var max = 1;
    for (var w = 0; w < weeks.length; w++) {
      final total = series.fold<int>(0, (sum, s) => sum + s.$2[w]);
      max = math.max(max, total);
    }

    canvas.drawLine(plot.bottomLeft, plot.bottomRight, Paint()..color = _axis);

    final slot = plot.width / weeks.length;
    final barWidth = math.min(18.0, slot * 0.62);

    for (var w = 0; w < weeks.length; w++) {
      // Right to left: the oldest week at the right edge.
      final cx = plot.right - slot * (w + 0.5);
      var base = plot.bottom;

      for (final (color, values) in series) {
        final value = values[w];
        if (value <= 0) continue;
        final h = value / max * plot.height;
        final rect = Rect.fromLTWH(cx - barWidth / 2, base - h, barWidth, h);
        canvas.drawRect(rect, Paint()..color = color);
        // A 1px surface gap between stacked segments.
        canvas.drawLine(rect.topLeft, rect.topRight, Paint()..color = Colors.white..strokeWidth = 1);
        base -= h;
      }
    }

    final first = _label(Fmt.shortDate(weeks.first), size: 10);
    first.paint(canvas, Offset(plot.right - first.width, plot.bottom + 4));
    final last = _label(Fmt.shortDate(weeks.last), size: 10);
    last.paint(canvas, Offset(plot.left, plot.bottom + 4));
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

/// The average level week by week, on a pinned 0..4 axis.
class LevelTrendLine extends StatelessWidget {
  const LevelTrendLine({super.key, required this.weeks, required this.values, this.height = 170});

  final List<String> weeks;
  final List<double?> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TrendPainter(weeks, values)),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.weeks, this.values);

  final List<String> weeks;
  final List<double?> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.isEmpty) return;

    const right = 22.0;
    const bottom = 20.0;
    const top = 8.0;
    final plot = Rect.fromLTRB(4, top, size.width - right, size.height - bottom);
    double y(double v) => plot.bottom - (v / 4) * plot.height;
    double x(int i) => weeks.length == 1 ? plot.center.dx : plot.right - (i / (weeks.length - 1)) * plot.width;

    for (var level = 0; level <= 4; level++) {
      canvas.drawLine(Offset(plot.left, y(level.toDouble())), Offset(plot.right, y(level.toDouble())), Paint()..color = _grid);
      final tp = _label('$level');
      tp.paint(canvas, Offset(plot.right + 7, y(level.toDouble()) - tp.height / 2));
    }

    final line = Paint()
      ..color = AppColors.viz
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // A week with no ratings is a gap, not a zero: nothing was measured.
    Path? path;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(x(i), y(v));
      } else {
        path.lineTo(x(i), y(v));
      }
    }
    if (path != null) canvas.drawPath(path, line);

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      canvas.drawCircle(Offset(x(i), y(v)), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x(i), y(v)), 3.5, Paint()..color = AppColors.viz);
    }

    final first = _label(Fmt.shortDate(weeks.first), size: 10);
    first.paint(canvas, Offset(plot.right - first.width, plot.bottom + 4));
    final last = _label(Fmt.shortDate(weeks.last), size: 10);
    last.paint(canvas, Offset(plot.left, plot.bottom + 4));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

/// A labelled horizontal bar — for a handful of categories, where a row with
/// its number beats any chart.
class BarRow extends StatelessWidget {
  const BarRow({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.color = AppColors.viz,
    this.trailing,
    this.leading,
  });

  final String label;
  final int value;
  final int max;
  final Color color;
  final String? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
              Text(trailing ?? Fmt.number(value), style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: AppShape.chip,
            child: Stack(
              children: [
                Container(height: 8, color: AppColors.lineSoft),
                FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: fraction,
                  child: Container(height: 8, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The key under anything coloured by series. Colour is never alone: every
/// swatch carries its words.
class ChartKey extends StatelessWidget {
  const ChartKey({super.key, required this.items});

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 5),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
      ],
    );
  }
}
