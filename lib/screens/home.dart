import 'package:flutter/material.dart';

import '../format.dart';
import '../i18n.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../widgets.dart';
import 'entry_form.dart';
import 'plan.dart';
import 'settings.dart';
import 'profile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final per = app.period;
        final s = statsFor(per);
        final insights = insightsFor(per);
        final total = app.totalBudget(per);
        final cs = Theme.of(context).colorScheme;
        final rate = s.savingsRate;

        // categories that need attention, most urgent first
        final watch = app.spendingCategories
            .map((c) => (c, s.byCat[c.id] ?? 0.0, app.budgetFor(per, c.id)))
            .where((e) => e.$2 > 0 || e.$3 > 0)
            .toList()
          ..sort((a, b) {
            double r(double sp, double b) => b > 0 ? sp / b : (sp > 0 ? 0.5 : 0);
            return r(b.$2, b.$3).compareTo(r(a.$2, a.$3));
          });

        return Scaffold(
          appBar: AppBar(
            title: const PeriodSwitcher(),
            centerTitle: true,
            leading: IconButton(
              tooltip: tr('Profile'),
              icon: app.userName.isEmpty
                  ? const Icon(Icons.account_circle_outlined)
                  : CircleAvatar(
                      radius: 14,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(app.userName.characters.first.toUpperCase(),
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    ),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
            actions: [
              IconButton(
                tooltip: tr('Settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntryForm())),
            icon: const Icon(Icons.add),
            label: const T('Add entry'),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final msg = await app.scanSms();
              if (context.mounted && msg.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              children: [
                if (app.pending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    child: Material(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        leading: Icon(Icons.sms_outlined, color: cs.onPrimaryContainer),
                        title: Text(trn(app.pending.length, '{n} bank transaction to review', '{n} bank transactions to review'),
                            style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                        subtitle: T('Confirm the amount and pick a category', style: TextStyle(color: cs.onPrimaryContainer)),
                        trailing: Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                        onTap: () => app.tab.value = 1,
                      ),
                    ),
                  ),

                if (app.backupDue)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    child: Material(
                      color: warnColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        leading: const Icon(Icons.backup_outlined, color: warnColor),
                        title: Text(
                          app.daysSinceBackup == null
                              ? tr('Back up your data to Gmail')
                              : tr('Last backup was {n} days ago', {'n': app.daysSinceBackup}),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const T('Your entries live only on this phone'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => emailBackupFlow(context),
                      ),
                    ),
                  ),

                // Summary: a small statement that adds up, top to bottom
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Expanded(child: Eyebrow('This month')),
                      if (rate != null)
                        Pill(tr('{p}% of income not spent', {'p': (rate * 100).round()}),
                            rate >= 0.2 ? goodColor : rate >= 0.05 ? warnColor : badColor),
                    ]),
                    const SizedBox(height: 10),
                    _line(context, 'Income', s.income, cs.primary, bold: true),
                    _line(context, 'Spending', -s.spend, spendColor),
                    const Divider(height: 14),
                    _line(context, 'Left after spending', s.net, s.net < 0 ? badColor : cs.onSurface, bold: true),
                    if (s.save > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.savings_outlined, size: 16, color: cs.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(child: T('Moved to savings', style: TextStyle(color: cs.onSurfaceVariant))),
                          Text(money(s.save), style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: tabular)),
                        ]),
                      ),
                  ]),
                ),

                const PlanCard(),

                // Budget overview
                SectionCard(
                  title: 'Budget',
                  trailing: TextButton(
                      onPressed: () {
                        app.budgetTab.value = 0;
                        app.tab.value = 4;
                      },
                      child: const T('Manage')),
                  child: total <= 0
                      ? T('No budgets set. Set a monthly template once and every month follows it.',
                          style: TextStyle(color: cs.onSurfaceVariant))
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                s.spend <= total
                                    ? tr('{a} {cur} left', {'a': fmt(total - s.spend), 'cur': app.currency})
                                    : tr('{a} {cur} over', {'a': fmt(s.spend - total), 'cur': app.currency}),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600, color: s.spend > total ? badColor : null),
                              ),
                            ),
                            Text('${fmt(s.spend)} / ${fmt(total)}',
                                style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: tabular)),
                          ]),
                          const SizedBox(height: 8),
                          BudgetBar(spent: s.spend, budget: total, color: cs.primary),
                          if (per.isCurrent) ...[
                            const SizedBox(height: 6),
                            Text(
                              tr('{d} days left · {p}% of the period gone',
                                  {'d': per.days - per.elapsed + 1, 'p': (per.elapsed / per.days * 100).round()}),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 14),
                          for (final e in watch.take(5)) _catRow(context, e.$1.display, e.$1.color, e.$2, e.$3),
                        ]),
                ),

                // Insights
                SectionCard(
                  title: 'What stands out',
                  child: Column(children: [for (final i in insights) InsightTile(i)]),
                ),

                // Recent
                SectionCard(
                  title: 'Recent entries',
                  trailing: TextButton(onPressed: () => app.tab.value = 2, child: const T('All')),
                  child: s.list.isEmpty
                      ? T('Nothing logged in this period yet.', style: TextStyle(color: cs.onSurfaceVariant))
                      : Column(children: [
                          for (final t in s.list.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: CategoryDot(app.cat(t.categoryId)?.color ?? 0xFF888888, size: 12),
                              title: Text(t.label.isEmpty ? (app.cat(t.categoryId)?.display ?? '') : t.label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${app.cat(t.categoryId)?.display ?? ''} · ${shortDate(parseIso(t.date))}'),
                              trailing: Text(ltr('${t.kind == 'income' ? '+' : '−'}${fmtAuto(t.amount)}'),
                                  style: TextStyle(
                                      fontFeatures: tabular,
                                      fontWeight: FontWeight.w600,
                                      color: t.kind == 'income' ? cs.primary : null)),
                              onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => EntryForm(existing: t))),
                            ),
                        ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _line(BuildContext context, String label, double v, Color color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(tr(label), style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w400))),
          Text('${v < 0 ? ltr('−${fmt(v.abs())}') : fmt(v.abs())} ${app.currency}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontFeatures: tabular)),
        ]),
      );

  Widget _catRow(BuildContext context, String name, int color, double spent, double budget) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CategoryDot(color),
          const SizedBox(width: 8),
          Expanded(child: Text(name)),
          Text(budget > 0 ? '${fmt(spent)} / ${fmt(budget)}' : tr('{a} · no budget', {'a': fmt(spent)}),
              style: TextStyle(color: spent > budget && budget > 0 ? badColor : cs.onSurfaceVariant, fontSize: 13, fontFeatures: tabular)),
        ]),
        if (budget > 0) ...[
          const SizedBox(height: 5),
          BudgetBar(spent: spent, budget: budget),
        ],
      ]),
    );
  }
}
