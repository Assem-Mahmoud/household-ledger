import 'dart:math';

import 'format.dart';
import 'i18n.dart';
import 'models.dart';
import 'periods.dart';
import 'state.dart';

class PeriodStats {
  final Period period;
  final List<Txn> list;
  double income = 0;
  double spend = 0; // expenses excluding savings transfers
  double save = 0; // savings & investment transfers
  final Map<int, double> byCat = {};
  final Map<int, int> countByCat = {};
  final Map<String, double> groups = {'need': 0, 'want': 0, 'save': 0};
  final Map<String, double> byDay = {};

  PeriodStats(this.period, this.list);

  double get net => income - spend;
  double? get savingsRate => income > 0 ? (income - spend) / income : null;
  bool get isEmpty => list.isEmpty;
}

PeriodStats statsFor(Period per) {
  final list = app.txns.where((t) => per.contains(t.date)).toList();
  final s = PeriodStats(per, list);
  for (final t in list) {
    if (t.kind == 'income') {
      s.income += t.amount;
      continue;
    }
    final c = app.cat(t.categoryId);
    final grp = c?.grp ?? 'want';
    if (grp == 'save') {
      s.save += t.amount;
    } else {
      s.spend += t.amount;
      s.byCat[t.categoryId] = (s.byCat[t.categoryId] ?? 0) + t.amount;
      s.countByCat[t.categoryId] = (s.countByCat[t.categoryId] ?? 0) + 1;
      s.byDay[t.date] = (s.byDay[t.date] ?? 0) + t.amount;
    }
    s.groups[grp == 'income' ? 'want' : grp] = (s.groups[grp == 'income' ? 'want' : grp] ?? 0) + t.amount;
  }
  return s;
}

/// Spending up to the same day-of-period in another period (for fair mid-month comparisons).
double spendUntilDay(Period per, int dayIndex) {
  final cutoff = isoDate(per.start.add(Duration(days: dayIndex - 1)));
  var sum = 0.0;
  for (final t in app.txns) {
    if (t.kind != 'expense' || !per.contains(t.date) || t.date.compareTo(cutoff) > 0) continue;
    if (app.cat(t.categoryId)?.isSaving ?? false) continue;
    sum += t.amount;
  }
  return sum;
}

class MerchantTotal {
  final String name;
  final double total;
  final int count;
  final int categoryId;
  MerchantTotal(this.name, this.total, this.count, this.categoryId);
}

List<MerchantTotal> topMerchants(PeriodStats s, {int limit = 8}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  final cats = <String, int>{};
  final display = <String, String>{};
  for (final t in s.list) {
    if (t.kind != 'expense' || (app.cat(t.categoryId)?.isSaving ?? false)) continue;
    final name = t.label.isEmpty ? (app.cat(t.categoryId)?.display ?? tr('Other')) : t.label;
    final key = name.toLowerCase();
    totals[key] = (totals[key] ?? 0) + t.amount;
    counts[key] = (counts[key] ?? 0) + 1;
    cats[key] = t.categoryId;
    display[key] = name;
  }
  final out = totals.keys.map((k) => MerchantTotal(display[k]!, totals[k]!, counts[k]!, cats[k]!)).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return out.take(limit).toList();
}

/// Average monthly spend per category over the last [n] complete periods before [per].
Map<int, double> averages(Period per, {int n = 3}) {
  final sums = <int, double>{};
  var p = per.prev;
  var used = 0;
  for (var i = 0; i < n; i++) {
    final s = statsFor(p);
    if (!s.isEmpty) {
      used++;
      s.byCat.forEach((k, v) => sums[k] = (sums[k] ?? 0) + v);
      for (final t in s.list) {
        if (t.kind == 'expense' && (app.cat(t.categoryId)?.isSaving ?? false)) {
          sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amount;
        }
      }
    }
    p = p.prev;
  }
  if (used == 0) return {};
  return sums.map((k, v) => MapEntry(k, v / used));
}

List<Insight> insightsFor(Period per) {
  final s = statsFor(per);
  final cur = app.currency;
  final out = <Insight>[];
  if (s.isEmpty) {
    return [
      Insight('info', per.isFuture
          ? tr('This period hasn\'t started yet.')
          : tr('No entries for this period yet. Scan your SMS or add entries manually.'))
    ];
  }

  // Savings rate
  final rate = s.savingsRate;
  if (rate != null) {
    final pct = (rate * 100).round();
    out.add(Insight(
      rate >= 0.2 ? 'good' : rate >= 0.05 ? 'warn' : 'bad',
      rate >= 0
          ? tr(rate >= 0.2
                  ? 'You kept {p}% of your income after spending, at or above the 20% benchmark.'
                  : 'You kept {p}% of your income after spending. A common target is 20%.',
              {'p': pct})
          : tr('Spending is {a} {cur} more than income this period.', {'a': fmt(s.spend - s.income), 'cur': cur}),
    ));
  } else if (per.isCurrent) {
    out.add(Insight('warn', tr('No income logged for this period yet, so the savings rate can\'t be calculated.')));
  }

  // Budget pace
  final total = app.totalBudget(per);
  if (per.isCurrent && total > 0) {
    final left = total - s.spend;
    final daysLeft = per.days - per.elapsed + 1;
    if (left >= 0) {
      out.add(Insight('info',
          tr('{a} {cur} left in this period\'s budgets, about {b} {cur} a day for the remaining {d} days.',
              {'a': fmt(left), 'b': fmt(left / max(daysLeft, 1)), 'cur': cur, 'd': daysLeft})));
    } else {
      out.add(Insight('bad', tr('Spending is {a} {cur} over the total budget of {b} {cur}.',
          {'a': fmt(-left), 'b': fmt(total), 'cur': cur})));
    }
    final projected = s.spend / max(per.elapsed, 1) * per.days;
    if (projected > total && left >= 0) {
      out.add(Insight('warn', tr('At the current pace, spending will reach about {a} {cur}, {b} over budget.',
          {'a': fmt(projected), 'b': fmt(projected - total), 'cur': cur})));
    }
  }

  // Comparison with previous period
  final prev = per.prev;
  if (per.isCurrent) {
    final prevSame = spendUntilDay(prev, per.elapsed);
    if (prevSame > 0) {
      final d = (s.spend - prevSame) / prevSame;
      out.add(Insight(d > 0.1 ? 'bad' : d < -0.05 ? 'good' : 'info',
          tr(d >= 0
                  ? 'By this point last period you had spent {a} {cur}. You\'re {p}% higher now.'
                  : 'By this point last period you had spent {a} {cur}. You\'re {p}% lower now.',
              {'a': fmt(prevSame), 'cur': cur, 'p': (d.abs() * 100).round()})));
    }
  } else {
    final ps = statsFor(prev);
    if (ps.spend > 0) {
      final d = (s.spend - ps.spend) / ps.spend;
      out.add(Insight(d > 0.1 ? 'bad' : d < -0.05 ? 'good' : 'info',
          tr(d >= 0 ? 'Spending rose {p}% vs {m} ({a} → {b} {cur}).' : 'Spending fell {p}% vs {m} ({a} → {b} {cur}).',
              {'p': (d.abs() * 100).round(), 'm': prev.label, 'a': fmt(ps.spend), 'b': fmt(s.spend), 'cur': cur})));
    }
  }

  // Budgets over / near
  final over = <String>[];
  final near = <String>[];
  for (final c in app.spendingCategories) {
    final b = app.budgetFor(per, c.id);
    final v = s.byCat[c.id] ?? 0;
    if (b <= 0) continue;
    if (v > b) {
      over.add('${c.display} (+${fmt(v - b)})');
    } else if (v >= b * app.alertPct / 100) {
      near.add('${c.display} ${(v / b * 100).round()}%');
    }
  }
  final sep = isAr ? '، ' : ', ';
  if (over.isNotEmpty) out.add(Insight('bad', tr('Over budget: {list}.', {'list': over.join(sep)})));
  if (near.isNotEmpty) out.add(Insight('warn', tr('Close to the limit: {list}.', {'list': near.join(sep)})));

  // Biggest category
  if (s.byCat.isNotEmpty && s.spend > 0) {
    final top = s.byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
    out.add(Insight('info',
        tr('{cat} is the largest spend at {a} {cur}, {p}% of the total.', {
          'cat': app.cat(top.key)?.display ?? tr('Other'),
          'a': fmt(top.value),
          'cur': cur,
          'p': (top.value / s.spend * 100).round(),
        })));
  }

  // Small purchases add up
  final small = s.list.where((t) => t.kind == 'expense' && t.amount < 50 && !(app.cat(t.categoryId)?.isSaving ?? false)).toList();
  if (small.length >= 10) {
    final sum = small.fold(0.0, (a, t) => a + t.amount);
    out.add(Insight('warn', tr('{n} small purchases under 50 {cur} added up to {a} {cur}.',
        {'n': small.length, 'cur': cur, 'a': fmt(sum)})));
  }

  // Wants share
  if (s.income > 0 && (s.groups['want'] ?? 0) / s.income > 0.3) {
    out.add(Insight('warn', tr('Wants are {p}% of income, above the 30% guide.',
        {'p': ((s.groups['want'] ?? 0) / s.income * 100).round()})));
  }

  // Largest single expense
  final expenses = s.list.where((t) => t.kind == 'expense').toList();
  if (expenses.isNotEmpty) {
    final big = expenses.reduce((a, b) => a.amount >= b.amount ? a : b);
    if (big.amount >= 500) {
      out.add(Insight('info',
          tr(big.label.isNotEmpty ? 'Largest single expense: {a} {cur} ({m}) on {d}.' : 'Largest single expense: {a} {cur} on {d}.',
              {'a': fmt(big.amount), 'cur': cur, 'm': big.label, 'd': shortDate(parseIso(big.date))})));
    }
  }
  return out;
}


class ItemTotal {
  final String name;
  final double total;
  final int count;
  ItemTotal(this.name, this.total, this.count);
}

/// Spending grouped by the "What for?" description (same text, any case).
List<ItemTotal> topItems(PeriodStats s, {int limit = 8}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  final shown = <String, String>{};
  for (final t in s.list) {
    final n = t.note.trim();
    if (t.kind != 'expense' || n.isEmpty || (app.cat(t.categoryId)?.isSaving ?? false)) continue;
    final k = n.toLowerCase();
    totals[k] = (totals[k] ?? 0) + t.amount;
    counts[k] = (counts[k] ?? 0) + 1;
    shown.putIfAbsent(k, () => n);
  }
  final out = totals.keys.map((k) => ItemTotal(shown[k]!, totals[k]!, counts[k]!)).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return out.take(limit).toList();
}
