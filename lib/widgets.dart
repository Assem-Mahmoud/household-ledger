import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'state.dart';

const goodColor = Color(0xFF1D7A4A);
const warnColor = Color(0xFFB07A12);
const badColor = Color(0xFFB3322F);
const spendColor = Color(0xFFB4612B);

Color levelColor(String level, BuildContext ctx) {
  switch (level) {
    case 'good':
      return goodColor;
    case 'warn':
      return warnColor;
    case 'bad':
      return badColor;
    default:
      return Theme.of(ctx).colorScheme.primary;
  }
}

/// "‹ October 2026 ›" switcher shown in app bars.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({super.key});

  // Listens to the app itself: it is used as a const widget, which parents never rebuild.
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final per = app.period;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous period',
          icon: const Icon(Icons.chevron_left),
          onPressed: app.goPrev,
        ),
        GestureDetector(
          onTap: app.goToday,
          child: Text(per.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: 'Next period',
          icon: const Icon(Icons.chevron_right),
          onPressed: per.isCurrent ? null : app.goNext,
        ),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({super.key, this.title, this.trailing, required this.child,
      this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16)});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ],
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 0.8, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      );
}

class InsightTile extends StatelessWidget {
  final Insight insight;
  const InsightTile(this.insight, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(color: levelColor(insight.level, context), shape: BoxShape.circle),
          ),
          Expanded(child: Text(insight.text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class CategoryDot extends StatelessWidget {
  final int color;
  final double size;
  const CategoryDot(this.color, {super.key, this.size = 10});
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle));
}

/// Horizontal progress bar coloured by how close spending is to the limit.
class BudgetBar extends StatelessWidget {
  final double spent;
  final double budget;
  final Color? color;
  const BudgetBar({super.key, required this.spent, required this.budget, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = budget > 0 ? spent / budget : 0.0;
    Color c = color ?? spendColor;
    if (budget > 0) {
      if (ratio > 1) {
        c = badColor;
      } else if (ratio >= app.alertPct / 100) {
        c = warnColor;
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: Stack(children: [
          Container(color: cs.surfaceContainerHighest),
          FractionallySizedBox(widthFactor: ratio.clamp(0.0, 1.0).toDouble(), child: Container(color: c)),
        ]),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

const tabular = [FontFeature.tabularFigures()];

String money(double v, {bool decimals = false}) => '${decimals ? fmtAuto(v) : fmt(v)} ${app.currency}';

// ---------------------------------------------------------------- charts

class TrendPoint {
  final String label;
  final double income;
  final double spend;
  final bool highlight;
  TrendPoint(this.label, this.income, this.spend, {this.highlight = false});
}

class TrendChart extends StatelessWidget {
  final List<TrendPoint> points;
  const TrendChart(this.points, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 210,
      child: CustomPaint(
        painter: _TrendPainter(points, cs.primary, spendColor, cs.onSurface, cs.onSurfaceVariant, cs.outlineVariant),
        size: Size.infinite,
      ),
    );
  }
}

double niceStep(double raw) {
  if (raw <= 0) return 1;
  final p = pow(10, (log(raw) / ln10).floor()).toDouble();
  final n = raw / p;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
}

void _text(Canvas c, String s, Offset at, Color color, {double size = 10.5, TextAlign align = TextAlign.center, FontWeight weight = FontWeight.w400}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: weight, fontFeatures: tabular)),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = at.dx;
  if (align == TextAlign.center) dx -= tp.width / 2;
  if (align == TextAlign.right) dx -= tp.width;
  tp.paint(c, Offset(dx, at.dy - tp.height / 2));
}

class _TrendPainter extends CustomPainter {
  final List<TrendPoint> pts;
  final Color inc, sp, ink, muted, grid;
  _TrendPainter(this.pts, this.inc, this.sp, this.ink, this.muted, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, right = 6.0, top = 10.0, bottom = 26.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    final maxV = pts.fold<double>(1, (m, p) => max(m, max(p.income, p.spend)));
    final minNet = pts.fold<double>(0, (m, p) => min(m, p.income - p.spend));
    final step = niceStep(maxV / 4);
    final topV = (maxV / step).ceil() * step;
    final botV = minNet < 0 ? -((-minNet) / step).ceil() * step : 0.0;
    double y(double v) => top + (topV - v) / (topV - botV) * h;

    final gridPaint = Paint()..color = grid.withOpacity(0.6)..strokeWidth = 1;
    for (var v = botV; v <= topV + 0.001; v += step) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width - right, y(v)), gridPaint);
      _text(canvas, compact(v), Offset(left - 6, y(v)), muted, align: TextAlign.right);
    }
    final slot = w / max(pts.length, 1);
    final bw = slot * 0.28;
    final netPts = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final x0 = left + i * slot + slot * 0.18;
      final r1 = RRect.fromRectAndRadius(Rect.fromLTRB(x0, y(p.income), x0 + bw, y(0)), const Radius.circular(3));
      final r2 = RRect.fromRectAndRadius(Rect.fromLTRB(x0 + bw + 3, y(p.spend), x0 + 2 * bw + 3, y(0)), const Radius.circular(3));
      canvas.drawRRect(r1, Paint()..color = inc);
      canvas.drawRRect(r2, Paint()..color = sp);
      _text(canvas, p.label, Offset(left + i * slot + slot / 2, size.height - 10), p.highlight ? ink : muted,
          weight: p.highlight ? FontWeight.w700 : FontWeight.w400);
      if (p.income > 0 || p.spend > 0) netPts.add(Offset(left + i * slot + slot / 2, y(p.income - p.spend)));
    }
    if (netPts.length > 1) {
      final path = Path()..moveTo(netPts.first.dx, netPts.first.dy);
      for (final o in netPts.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, Paint()..color = ink..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
    for (var i = 0; i < netPts.length; i++) {
      canvas.drawCircle(netPts[i], i == netPts.length - 1 ? 4 : 3, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

class DailyChart extends StatelessWidget {
  final List<double> values; // one per day of the period
  final double? dailyBudget;
  final int? today; // index of today, if current
  const DailyChart(this.values, {super.key, this.dailyBudget, this.today});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 140,
      child: CustomPaint(
        painter: _DailyPainter(values, dailyBudget, today, spendColor, cs.onSurfaceVariant, cs.outlineVariant, cs.primary),
        size: Size.infinite,
      ),
    );
  }
}

class _DailyPainter extends CustomPainter {
  final List<double> v;
  final double? budget;
  final int? today;
  final Color bar, muted, grid, accent;
  _DailyPainter(this.v, this.budget, this.today, this.bar, this.muted, this.grid, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 18.0, top = 6.0;
    final w = size.width - left;
    final h = size.height - top - bottom;
    final maxV = max(v.fold<double>(1, (m, e) => max(m, e)), budget ?? 0.0);
    final step = niceStep(maxV / 3);
    final topV = (maxV / step).ceil() * step;
    double y(double val) => top + (topV - val) / topV * h;
    final gp = Paint()..color = grid.withOpacity(0.6);
    for (var g = 0.0; g <= topV + 0.001; g += step) {
      canvas.drawLine(Offset(left, y(g)), Offset(size.width, y(g)), gp);
      _text(canvas, compact(g), Offset(left - 5, y(g)), muted, align: TextAlign.right, size: 9.5);
    }
    final slot = w / max(v.length, 1);
    for (var i = 0; i < v.length; i++) {
      if (v[i] <= 0) continue;
      final x = left + i * slot + slot * 0.15;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x, y(v[i]), x + slot * 0.7, y(0)), const Radius.circular(2)),
          Paint()..color = (today != null && i > today!) ? bar.withOpacity(0.3) : bar);
    }
    if (budget != null && budget! > 0) {
      final by = y(budget!);
      final dash = Paint()..color = accent..strokeWidth = 1.5;
      for (var x = left; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, by), Offset(min(x + 4, size.width), by), dash);
      }
    }
    for (final i in [0, v.length ~/ 2, v.length - 1]) {
      if (i < 0 || i >= v.length) continue;
      _text(canvas, '${i + 1}', Offset(left + i * slot + slot / 2, size.height - 7), muted, size: 9.5);
    }
  }

  @override
  bool shouldRepaint(covariant _DailyPainter old) => true;
}

/// Stacked bar for income allocation (needs / wants / savings).
class SplitBar extends StatelessWidget {
  final List<(double, Color)> parts;
  const SplitBar(this.parts, {super.key});
  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (s, p) => s + p.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 12,
        child: Row(children: [
          for (final p in parts)
            if (p.$1 > 0) Expanded(flex: max(1, (p.$1 / max(total, 1) * 1000).round()), child: Container(color: p.$2)),
          if (total == 0) Expanded(child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest)),
        ]),
      ),
    );
  }
}
