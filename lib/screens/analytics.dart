import 'dart:math';

import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart' show accountIcon;

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final per = app.period;
        final s = statsFor(per);
        final prev = statsFor(per.prev);

        // six-period trend
        final periods = <Period>[];
        var p = per;
        for (var i = 0; i < 6; i++) {
          periods.insert(0, p);
          p = p.prev;
        }
        final trend = periods.map((x) {
          final st = statsFor(x);
          return TrendPoint(x.shortLabel, st.income, st.spend, highlight: x.key == per.key);
        }).toList();
        final withData = periods.map(statsFor).where((x) => !x.isEmpty).toList();
        final avgSpend = withData.isEmpty ? 0.0 : withData.fold<double>(0, (a, x) => a + x.spend) / withData.length;
        final avgIncome = withData.isEmpty ? 0.0 : withData.fold<double>(0, (a, x) => a + x.income) / withData.length;

        // daily
        final daily = List<double>.generate(per.days, (i) => s.byDay[isoDate(per.start.add(Duration(days: i)))] ?? 0);
        final total = app.totalBudget(per);
        final avgDaily = s.spend / max(per.isCurrent ? per.elapsed : per.days, 1);

        // categories
        final cats = s.byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final merchants = topMerchants(s);

        // 50/30/20
        final need = s.groups['need'] ?? 0.0, want = s.groups['want'] ?? 0.0;
        final saved = s.income > 0 ? max(0.0, s.income - need - want) : (s.groups['save'] ?? 0.0);

        // ring chart: top five categories, the rest as "Other"
        final ringParts = <(double, Color)>[
          for (final e in cats.take(5)) (e.value, categoryColor(app.cat(e.key))),
          if (cats.length > 5) (cats.skip(5).fold<double>(0, (a, e) => a + e.value), lc.outline),
        ];
        final tips = insightsFor(per);

        return Scaffold(
          appBar: AppBar(
            title: const T('Insights'),
            centerTitle: false,
            actions: const [PeriodSwitcher(), SizedBox(width: 12)],
          ),
          body: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              SectionCard(
                child: cats.isEmpty
                    ? T('No spending in this period.', style: TextStyle(color: cs.onSurfaceVariant))
                    : Row(children: [
                        DonutChart(ringParts, top: tr('Spent'), big: fmt(s.spend), bottom: app.currency),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (final e in cats.take(5))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(color: categoryColor(app.cat(e.key)), borderRadius: BorderRadius.circular(3)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(app.cat(e.key)?.display ?? tr('Other'),
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                  ),
                                  Text('${(e.value / max(s.spend, 1) * 100).round()}%',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                ]),
                              ),
                            if (cats.length > 5)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: lc.outline, borderRadius: BorderRadius.circular(3))),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(tr('Other'), style: const TextStyle(fontSize: 13))),
                                  Text(
                                      '${(cats.skip(5).fold<double>(0, (a, e) => a + e.value) / max(s.spend, 1) * 100).round()}%',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                ]),
                              ),
                          ]),
                        ),
                      ]),
              ),

              for (final t in tips.take(4))
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: lc.card, borderRadius: BorderRadius.circular(18)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: levelColor(t.level, context).withOpacity(lc.dark ? 0.2 : 0.12), borderRadius: BorderRadius.circular(11)),
                      child: Icon(
                          t.level == 'good'
                              ? Icons.trending_up
                              : t.level == 'bad'
                                  ? Icons.error_outline
                                  : t.level == 'warn'
                                      ? Icons.warning_amber_rounded
                                      : Icons.lightbulb_outline,
                          size: 19,
                          color: levelColor(t.level, context)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t.text, style: TextStyle(fontSize: 14, height: 1.4, color: lc.text))),
                  ]),
                ),

              SectionCard(
                title: 'Last 6 months',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TrendChart(trend),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, runSpacing: 4, children: [
                    _legend(context, cs.primary, 'Income'),
                    _legend(context, spendColor, 'Spending'),
                    _legend(context, cs.onSurface, 'Net'),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    trn(withData.length, 'Average over {n} period with data: income {i}, spending {s} {cur}.',
                        'Average over {n} periods with data: income {i}, spending {s} {cur}.',
                        {'i': fmt(avgIncome), 's': fmt(avgSpend), 'cur': app.currency}),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ]),
              ),

              SectionCard(
                title: 'Daily spending',
                trailing: Text(tr('avg {a}/day', {'a': fmt(avgDaily)}), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DailyChart(daily,
                      dailyBudget: total > 0 ? total / per.days : null,
                      today: per.isCurrent ? per.elapsed - 1 : null),
                  if (total > 0) ...[
                    const SizedBox(height: 6),
                    Text(tr('Dashed line: daily budget of {a} {cur}.', {'a': fmt(total / per.days), 'cur': app.currency}),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  ],
                ]),
              ),

              SectionCard(
                title: 'Where the money went',
                child: cats.isEmpty
                    ? T('No spending in this period.', style: TextStyle(color: cs.onSurfaceVariant))
                    : Column(children: [
                        for (final e in cats) _catRow(context, e.key, e.value, s.spend, prev.byCat[e.key] ?? 0, s.countByCat[e.key] ?? 0),
                      ]),
              ),

              SectionCard(
                title: 'Needs · Wants · Savings',
                trailing: T('target 50 / 30 / 20', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                child: s.income <= 0
                    ? T('Log this period\'s income to compare against the 50/30/20 guide.',
                        style: TextStyle(color: cs.onSurfaceVariant))
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SplitBar([(need, spendColor), (want, warnColor), (saved, cs.primary)]),
                        const SizedBox(height: 12),
                        _ruleRow(context, 'Needs', need / s.income, 0.5, true),
                        _ruleRow(context, 'Wants', want / s.income, 0.3, true),
                        _ruleRow(context, 'Savings (incl. unspent)', saved / s.income, 0.2, false),
                      ]),
              ),

              if (app.accounts.isNotEmpty)
                SectionCard(
                  title: 'By account',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final e in (app.byAccount(per).entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1))))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Icon(accountIcon(app.account(e.key)?.type ?? 'bank'), size: 18,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(child: Text(app.account(e.key)?.name ?? tr('No account'))),
                          if (e.value.$2 > 0)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 12),
                              child: Text(ltr('+${fmt(e.value.$2)}'),
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontFeatures: tabular)),
                            ),
                          Text(ltr('−${fmt(e.value.$1)}'), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                        ]),
                      ),
                  ]),
                ),
              if (topItems(s).isNotEmpty)
                SectionCard(
                  title: 'Top items',
                  child: Column(children: [
                    for (final it in topItems(s))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(color: lc.primarySoft, borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.sell_outlined, size: 18, color: lc.onPrimarySoft),
                        ),
                        title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(trn(it.count, '{n} time', '{n} times')),
                        trailing: Text(fmt(it.total), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w700)),
                        onTap: () => app.searchEntries(it.name),
                      ),
                  ]),
                ),
              SectionCard(
                title: 'Top merchants',
                child: merchants.isEmpty
                    ? T('No merchant data yet.', style: TextStyle(color: cs.onSurfaceVariant))
                    : Column(children: [
                        for (final m in merchants)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CategoryTile(app.cat(m.categoryId), size: 34),
                            title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(trn(m.count, '{n} purchase · avg {a}', '{n} purchases · avg {a}', {'a': fmt(m.total / m.count)})),
                            trailing: Text(fmt(m.total), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
                          ),
                      ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _legend(BuildContext context, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(tr(label), style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);

  Widget _catRow(BuildContext context, int catId, double v, double total, double prevV, int count) {
    final cs = Theme.of(context).colorScheme;
    final c = app.cat(catId);
    final share = total > 0 ? v / total : 0.0;
    String delta = '';
    Color deltaColor = cs.onSurfaceVariant;
    if (prevV > 0) {
      final d = (v - prevV) / prevV;
      delta = '${d >= 0 ? '▲' : '▼'} ${(d.abs() * 100).round()}%';
      deltaColor = d > 0.1 ? badColor : d < -0.05 ? goodColor : cs.onSurfaceVariant;
    } else if (v > 0) {
      delta = tr('new');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CategoryTile(c, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text('${c?.display ?? tr('Other')}  ', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(fmt(v), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
          SizedBox(
            width: 64,
            child: Text(delta, textAlign: TextAlign.end, style: TextStyle(color: deltaColor, fontSize: 12.5)),
          ),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 7,
            backgroundColor: lc.raised,
            color: categoryColor(c),
          ),
        ),
        const SizedBox(height: 3),
        Text(trn(count, '{p}% of spending · {n} entry', '{p}% of spending · {n} entries', {'p': (share * 100).round()}),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }

  Widget _ruleRow(BuildContext context, String label, double actual, double target, bool lowerIsBetter) {
    final ok = lowerIsBetter ? actual <= target : actual >= target;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(tr(label))),
        Text('${(actual * 100).round()}%',
            style: TextStyle(fontWeight: FontWeight.w700, color: ok ? goodColor : badColor, fontFeatures: tabular)),
        SizedBox(
          width: 72,
          child: Text(tr('of {p}%', {'p': (target * 100).round()}), textAlign: TextAlign.end,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
        ),
      ]),
    );
  }
}
