import 'package:flutter/material.dart';

import '../format.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../widgets.dart';
import 'entry_form.dart';
import 'settings.dart';

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
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntryForm())),
            icon: const Icon(Icons.add),
            label: const Text('Add entry'),
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
                        title: Text('${app.pending.length} bank transaction${app.pending.length == 1 ? '' : 's'} to review',
                            style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                        subtitle: Text('Confirm the amount and pick a category', style: TextStyle(color: cs.onPrimaryContainer)),
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
                              ? 'Back up your data to Gmail'
                              : 'Last backup was ${app.daysSinceBackup} days ago',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Your entries live only on this phone'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => emailBackupFlow(context),
                      ),
                    ),
                  ),

                // Summary
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Eyebrow('Net cash flow'),
                    const SizedBox(height: 4),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
                      Text(fmt(s.net),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600, fontFeatures: tabular,
                              color: s.net < 0 ? badColor : cs.onSurface)),
                      Text(app.currency, style: TextStyle(color: cs.onSurfaceVariant)),
                      if (rate != null)
                        Pill('${(rate * 100).round()}% saved', rate >= 0.2 ? goodColor : rate >= 0.05 ? warnColor : badColor),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      _stat(context, 'Income', s.income, cs.primary),
                      _stat(context, 'Spending', s.spend, spendColor),
                      _stat(context, 'Saved', s.save, cs.onSurface),
                    ]),
                  ]),
                ),

                // Budget overview
                SectionCard(
                  title: 'Budget',
                  trailing: TextButton(onPressed: () => app.tab.value = 4, child: const Text('Manage')),
                  child: total <= 0
                      ? Text('No budgets set. Set a monthly template once and every month follows it.',
                          style: TextStyle(color: cs.onSurfaceVariant))
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                s.spend <= total ? '${fmt(total - s.spend)} ${app.currency} left' : '${fmt(s.spend - total)} ${app.currency} over',
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
                              '${per.days - per.elapsed + 1} days left · ${(per.elapsed / per.days * 100).round()}% of the period gone',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(height: 14),
                          for (final e in watch.take(5)) _catRow(context, e.$1.name, e.$1.color, e.$2, e.$3),
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
                  trailing: TextButton(onPressed: () => app.tab.value = 2, child: const Text('All')),
                  child: s.list.isEmpty
                      ? Text('Nothing logged in this period yet.', style: TextStyle(color: cs.onSurfaceVariant))
                      : Column(children: [
                          for (final t in s.list.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: CategoryDot(app.cat(t.categoryId)?.color ?? 0xFF888888, size: 12),
                              title: Text(t.label.isEmpty ? (app.cat(t.categoryId)?.name ?? '') : t.label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${app.cat(t.categoryId)?.name ?? ''} · ${shortDate(parseIso(t.date))}'),
                              trailing: Text('${t.kind == 'income' ? '+' : '−'}${fmtAuto(t.amount)}',
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

  Widget _stat(BuildContext context, String label, double v, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(label),
          const SizedBox(height: 2),
          Text(fmt(v),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color, fontWeight: FontWeight.w600, fontFeatures: tabular)),
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
          Text(budget > 0 ? '${fmt(spent)} / ${fmt(budget)}' : '${fmt(spent)} · no budget',
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
