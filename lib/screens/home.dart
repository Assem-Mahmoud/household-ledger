import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_form.dart';
import 'profile.dart';
import 'settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    return tr(h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = lc;
        final per = app.period;
        final s = statsFor(per);
        final total = app.totalBudget(per);
        final insights = insightsFor(per).where((i) => i.level != 'info').take(2).toList();

        // categories with spending or a budget, most used first
        final cats = app.spendingCategories
            .map((x) => (x, s.byCat[x.id] ?? 0.0, app.budgetFor(per, x.id)))
            .where((e) => e.$2 > 0)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
        final plan = app.planFor(per).where((l) => !l.done).take(3).toList();

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                final msg = await app.scanSms();
                if (context.mounted && msg.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // header: avatar, greeting, month, settings
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                    child: Row(children: [
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                        child: Semantics(label: tr('Profile'), button: true, child: const Avatar()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_greeting(), style: TextStyle(fontSize: 13, color: c.muted)),
                          Text(app.userName.isEmpty ? tr('Household Ledger') : app.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
                        ]),
                      ),
                      const PeriodSwitcher(),
                      IconButton(
                        tooltip: tr('Settings'),
                        icon: Icon(Icons.settings_outlined, color: c.text),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      ),
                    ]),
                  ),

                  _Hero(per: per, s: s, total: total),

                  if (app.pending.isNotEmpty)
                    _Strip(
                      icon: Icons.mark_chat_unread_outlined,
                      title: trn(app.pending.length, '{n} bank message to review', '{n} bank messages to review'),
                      subtitle: () {
                        final n = app.pending.where((p) => p.categoryId != null).length;
                        return n > 0 ? tr('{n} already have a category', {'n': n}) : tr('Confirm the amount and pick a category');
                      }(),
                      action: tr('Review'),
                      onTap: () => app.openActivity(0),
                    ),

                  if (app.backupDue)
                    _Strip(
                      icon: Icons.cloud_upload_outlined,
                      title: app.backupFailed
                          ? tr('The last automatic backup failed')
                          : app.backupUri.isEmpty
                              ? tr('Turn on automatic backup')
                              : tr('Last backup was {n} days ago', {'n': app.daysSinceBackup}),
                      subtitle: tr('Your entries live only on this phone'),
                      action: tr('Fix'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
                    ),

                  // where it went
                  SectionCard(
                    title: 'Where it went',
                    trailing: TextButton(onPressed: () => app.tab.value = 2, child: const T('See all')),
                    child: cats.isEmpty
                        ? Text(tr('Nothing logged in this period yet.'), style: TextStyle(color: c.muted))
                        : Column(children: [
                            for (final e in cats.take(5))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(children: [
                                  CategoryTile(e.$1),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                                        Expanded(
                                          child: Text(e.$1.display,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                        ),
                                        Text(fmt(e.$2), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                        if (e.$3 > 0)
                                          Text(' / ${fmt(e.$3)}', style: TextStyle(fontSize: 12, color: c.muted, fontFeatures: tabular)),
                                      ]),
                                      const SizedBox(height: 6),
                                      BudgetBar(
                                        spent: e.$2,
                                        budget: e.$3 > 0 ? e.$3 : s.spend,
                                        color: e.$3 > 0 ? categoryColor(e.$1) : categoryColor(e.$1),
                                      ),
                                    ]),
                                  ),
                                ]),
                              ),
                          ]),
                  ),

                  // coming up from the plan
                  SectionCard(
                    title: 'Coming up',
                    trailing: TextButton(onPressed: () => app.openPlan(0), child: Text(tr(plan.isEmpty ? 'Set up' : 'Plan'))),
                    child: plan.isEmpty
                        ? Text(
                            app.planFor(per).isEmpty
                                ? tr('Add what must happen each month (rent, fees, savings) and tick it off as you go.')
                                : tr('Everything in this month\'s plan is done.'),
                            style: TextStyle(color: app.planFor(per).isEmpty ? c.muted : c.good))
                        : Column(children: [
                            for (final l in plan)
                              InkWell(
                                onTap: () => app.openPlan(0),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  child: Row(children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.outline, width: 2)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(l.item.title,
                                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                                    ),
                                    _DueChip(l),
                                    const SizedBox(width: 10),
                                    Text(fmt(l.target), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                  ]),
                                ),
                              ),
                          ]),
                  ),

                  if (insights.isNotEmpty)
                    SectionCard(
                      title: 'What stands out',
                      child: Column(children: [
                        for (final i in insights)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                    color: levelColor(i.level, context).withOpacity(c.dark ? 0.2 : 0.12),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Icon(
                                    i.level == 'good'
                                        ? Icons.trending_up
                                        : i.level == 'bad'
                                            ? Icons.error_outline
                                            : Icons.lightbulb_outline,
                                    size: 18,
                                    color: levelColor(i.level, context)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(i.text, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
                            ]),
                          ),
                      ]),
                    ),

                  SectionCard(
                    title: 'Recent entries',
                    trailing: TextButton(onPressed: () => app.openActivity(1), child: const T('See all')),
                    child: s.list.isEmpty
                        ? Text(tr('Tap + to add your first entry.'), style: TextStyle(color: c.muted))
                        : Column(children: [for (final t in s.list.take(4)) EntryRow(t)]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The big "left to spend" card.
class _Hero extends StatelessWidget {
  final Period per;
  final PeriodStats s;
  final double total;
  const _Hero({required this.per, required this.s, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final hasBudget = total > 0;
    final left = total - s.spend;
    final daysLeft = per.isCurrent ? per.days - per.elapsed + 1 : 0;
    final String label;
    final double big;
    final String sub;
    if (hasBudget && left >= 0) {
      label = tr('Left to spend this month');
      big = left;
      sub = daysLeft > 0
          ? tr('of {b} budget · {d} days left · about {p} a day',
              {'b': fmt(total), 'd': daysLeft, 'p': fmt(left / daysLeft)})
          : tr('of {b} budget', {'b': fmt(total)});
    } else if (hasBudget) {
      label = tr('Over budget this month');
      big = -left;
      sub = tr('Spent {a} of {b} budgeted', {'a': fmt(s.spend), 'b': fmt(total)});
    } else {
      label = tr('Spent this month');
      big = s.spend;
      sub = tr('No budget yet. Set one in Plan › Budgets.');
    }
    Widget stat(String name, double v) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.heroChip, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(name), style: TextStyle(fontSize: 12, color: c.heroSub)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(fmt(v), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.heroText, fontFeatures: tabular)),
              ),
            ]),
          ),
        );
    return GestureDetector(
      onTap: hasBudget ? null : () => app.openPlan(1),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: TextStyle(fontSize: 14, color: c.heroSub)),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(fmt(big),
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: c.heroText, letterSpacing: -0.5, fontFeatures: tabular)),
              ),
            ),
            const SizedBox(width: 6),
            Text(app.currency, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.heroSub)),
          ]),
          Text(sub, style: TextStyle(fontSize: 13, color: c.heroSub)),
          if (hasBudget) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(children: [
                  Container(color: c.heroTrack),
                  FractionallySizedBox(
                    widthFactor: (s.spend / total).clamp(0.0, 1.0).toDouble(),
                    child: Container(color: left < 0 ? c.secondary : (c.dark ? c.primary : Colors.white)),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            stat('Income', s.income),
            const SizedBox(width: 8),
            stat('Spent', s.spend),
            const SizedBox(width: 8),
            stat('Saved', s.save),
          ]),
        ]),
      ),
    );
  }
}

/// Amber strip for things that need attention.
class _Strip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
  const _Strip({required this.icon, required this.title, required this.subtitle, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: c.attnBg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.dark ? c.secondary : const Color(0xFFFBDDB3), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: c.dark ? c.onSecondary : c.attnText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: c.attnText)),
                ]),
              ),
              Text(action, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.attnText)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DueChip extends StatelessWidget {
  final PlanLine l;
  const _DueChip(this.l);
  @override
  Widget build(BuildContext context) {
    final c = lc;
    final due = l.due;
    if (due == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final days = due.difference(DateTime(now.year, now.month, now.day)).inDays;
    final overdue = days < 0;
    final soon = days <= 3;
    final text = overdue
        ? tr('overdue')
        : days == 0
            ? tr('today')
            : trn(days, 'in {n} day', 'in {n} days');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: overdue ? c.bad.withOpacity(0.14) : soon ? c.attnBg : c.raised, borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: overdue ? c.bad : soon ? c.attnText : c.muted)),
    );
  }
}

/// One entry: category tile, merchant, category · account, signed amount.
class EntryRow extends StatelessWidget {
  final Txn t;
  final bool showDate;
  const EntryRow(this.t, {super.key, this.showDate = true});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final cat = app.cat(t.categoryId);
    final acc = app.account(t.accountId);
    final title = t.label.isEmpty ? (cat?.display ?? '') : t.label;
    final meta = [
      // the item description, unless it is already the title (no merchant)
      if (t.merchant.isNotEmpty && t.note.isNotEmpty) t.note,
      cat?.display ?? '',
      if (acc != null) acc.name,
      if (showDate) shortDate(parseIso(t.date)),
    ].where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryForm(existing: t))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          CategoryTile(cat),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Text(ltr('${t.kind == 'income' ? '+' : '−'}${fmtAuto(t.amount)}'),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular, color: t.kind == 'income' ? c.primary : c.text)),
        ]),
      ),
    );
  }
}
