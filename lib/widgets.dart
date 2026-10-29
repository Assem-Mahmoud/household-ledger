import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart' hide Category;

import 'format.dart';
import 'i18n.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';

// status colours follow light/dark mode
Color get goodColor => lc.good;
Color get warnColor => lc.warn;
Color get badColor => lc.bad;
Color get spendColor => lc.secondary;

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
    final c = lc;
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => InkResponse(
          onTap: onTap,
          radius: 20,
          child: Tooltip(
            message: tip,
            child: SizedBox(
              width: 34,
              height: 40,
              child: Icon(icon, size: 20, color: onTap == null ? c.outline : c.text),
            ),
          ),
        );
    return Container(
      height: 40,
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.outline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        arrow(Icons.chevron_left, tr('Previous period'), app.goPrev), // chevrons mirror themselves in Arabic
        GestureDetector(
          onTap: app.goToday,
          child: Text(per.label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        ),
        arrow(Icons.chevron_right, tr('Next period'),
            per.isCurrent ? null : app.goNext),
      ]),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(color: lc.card, borderRadius: BorderRadius.circular(20)),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(tr(title!), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: lc.text))),
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
        tr(text).toUpperCase(),
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
            margin: const EdgeInsetsDirectional.only(top: 6, end: 10),
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
    final ratio = budget > 0 ? spent / budget : 0.0;
    Color c = color ?? lc.primary;
    if (budget > 0) {
      if (ratio > 1) {
        c = badColor;
      } else if (ratio >= app.alertPct / 100) {
        c = warnColor;
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 7,
        child: Stack(children: [
          Container(color: lc.raised),
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

/// Currencies offered in Settings and first-run setup (code, English name).
const currencyChoices = [
  ('SAR', 'Saudi riyal'), ('EGP', 'Egyptian pound'), ('AED', 'UAE dirham'), ('KWD', 'Kuwaiti dinar'),
  ('QAR', 'Qatari riyal'), ('BHD', 'Bahraini dinar'), ('OMR', 'Omani rial'), ('JOD', 'Jordanian dinar'),
  ('USD', 'US dollar'), ('EUR', 'Euro'), ('GBP', 'British pound'),
];

class CurrencyPicker extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const CurrencyPicker({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final code = app.currencyCode;
    final known = currencyChoices.any((c) => c.$1 == code);
    return DropdownButton<String>(
      value: code,
      items: [
        for (final c in currencyChoices) DropdownMenuItem(value: c.$1, child: Text('${c.$1} · ${tr(c.$2)}')),
        if (!known) DropdownMenuItem(value: code, child: Text(code)),
      ],
      selectedItemBuilder: (_) => [
        for (final c in currencyChoices) Center(child: Text(c.$1)),
        if (!known) Center(child: Text(code)),
      ],
      onChanged: (v) {
        if (v != null && v != code) onChanged(v);
      },
    );
  }
}


/// Rounded square with a category's icon on its tinted colour.
class CategoryTile extends StatelessWidget {
  final Category? category;
  final double size;
  const CategoryTile(this.category, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: categoryTint(category), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(categoryIcon(category), size: size * 0.5, color: categoryColor(category)),
      );
}

/// Round avatar with the user's initial.
class Avatar extends StatelessWidget {
  final double size;
  const Avatar({super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final name = app.userName;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: lc.primarySoft, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: name.isEmpty
          ? Icon(Icons.person_outline, size: size * 0.5, color: lc.onPrimarySoft)
          : Text(name.characters.first.toUpperCase(),
              style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: lc.onPrimarySoft)),
    );
  }
}

/// Two-way switch shaped like the design's segmented tabs.
class SegmentTabs extends StatelessWidget {
  final List<Widget> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const SegmentTabs({super.key, required this.labels, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: lc.dark ? lc.card : const Color(0xFFE6ECE8), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Material(
                color: i == selected ? (lc.dark ? lc.raised : Colors.white) : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => onSelect(i),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: DefaultTextStyle(
                        style: TextStyle(
                            fontFamily: appFont,
                            fontSize: 14,
                            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w600,
                            color: i == selected ? lc.text : lc.muted),
                        child: labels[i],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// Small count bubble in the secondary colour.
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge(this.count, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: lc.secondary, borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: lc.onSecondary)),
      );
}


/// Ring chart: one arc per (value, colour), with a label in the middle.
class DonutChart extends StatelessWidget {
  final List<(double, Color)> parts;
  final String top, big, bottom;
  final double size;
  const DonutChart(this.parts, {super.key, required this.top, required this.big, required this.bottom, this.size = 150});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size.square(size), painter: _DonutPainter(parts, lc.raised)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(top, style: TextStyle(fontSize: 12, color: lc.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(big, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: lc.text, fontFeatures: tabular)),
            ),
            Text(bottom, style: TextStyle(fontSize: 12, color: lc.muted)),
          ]),
        ]),
      );
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> parts;
  final Color track;
  _DonutPainter(this.parts, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final total = parts.fold<double>(0, (a, p) => a + p.$1);
    canvas.drawArc(rect, 0, 2 * pi, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    if (total <= 0) return;
    var start = -pi / 2;
    const gap = 0.025;
    for (final p in parts) {
      if (p.$1 <= 0) continue;
      final sweep = p.$1 / total * 2 * pi;
      canvas.drawArc(rect, start + gap / 2, max(0.0, sweep - gap), false,
          Paint()..color = p.$2..style = PaintingStyle.stroke..strokeWidth = stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}


/// Descriptions used before, most frequent first (for suggestions and tracking).
List<String> pastDescriptions() {
  final counts = <String, int>{};
  final shown = <String, String>{};
  for (final t in app.txns) {
    final n = t.note.trim();
    if (n.isEmpty) continue;
    final k = n.toLowerCase();
    counts[k] = (counts[k] ?? 0) + 1;
    shown.putIfAbsent(k, () => n);
  }
  final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [for (final k in keys) shown[k]!];
}

/// "What for?" — a short description of the item, with suggestions from earlier entries.
class WhatForField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool dense;
  const WhatForField({super.key, required this.controller, this.focusNode, this.dense = true});
  @override
  State<WhatForField> createState() => _WhatForFieldState();
}

class _WhatForFieldState extends State<WhatForField> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final past = pastDescriptions();
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        final starts = past.where((p) => p.toLowerCase().startsWith(q) && p.toLowerCase() != q);
        final has = past.where((p) => !p.toLowerCase().startsWith(q) && p.toLowerCase().contains(q));
        return [...starts, ...has].take(6);
      },
      fieldViewBuilder: (context, ctl, focus, onSubmit) => TextField(
        controller: ctl,
        focusNode: focus,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmit(),
        decoration: InputDecoration(
          isDense: widget.dense,
          prefixIcon: const Icon(Icons.notes),
          hintText: tr('What for? e.g. car oil, school bag (optional)'),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: AlignmentDirectional.topStart,
        child: Material(
          elevation: 6,
          color: lc.card,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), shrinkWrap: true, children: [
              for (final o in options)
                ListTile(dense: true, leading: const Icon(Icons.history, size: 18), title: Text(o), onTap: () => onSelected(o)),
            ]),
          ),
        ),
      ),
    );
  }
}
