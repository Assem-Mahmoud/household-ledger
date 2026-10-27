import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../models.dart';
import '../state.dart';
import '../stats.dart';
import '../widgets.dart';

/// Two views of the same numbers:
///  - This month: what applies now (template value unless changed for this month only)
///  - Template: the default every month inherits
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Budget'),
          bottom: const TabBar(tabs: [Tab(text: 'This period'), Tab(text: 'Template')]),
        ),
        body: const TabBarView(children: [_MonthTab(), _TemplateTab()]),
      ),
    );
  }
}

Future<void> _editAmount(BuildContext context, Category c, {required bool fromTemplate}) async {
  final per = app.period;
  final current = fromTemplate ? c.budget : app.budgetFor(per, c.id);
  final ctl = TextEditingController(text: current > 0 ? fmtAuto(current).replaceAll(',', '') : '');
  final overridden = app.isOverridden(per, c.id);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c2) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c2).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(c.name, style: Theme.of(c2).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          fromTemplate
              ? 'Default for every period. Periods you changed individually keep their own value.'
              : 'Template value: ${fmt(c.budget)} ${app.currency}${overridden ? ' · this period currently differs' : ''}',
          style: TextStyle(color: Theme.of(c2).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 22, fontFeatures: tabular),
          decoration: InputDecoration(labelText: 'Monthly amount', suffixText: app.currency, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        if (fromTemplate)
          FilledButton(onPressed: () => Navigator.pop(c2, 'template'), child: const Text('Save template'))
        else ...[
          FilledButton(onPressed: () => Navigator.pop(c2, 'month'), child: Text('Save for ${per.label} only')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(c2, 'template'), child: const Text('Save to template (all periods)')),
          if (overridden) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(c2, 'reset'), child: const Text('Reset to template value')),
          ],
        ],
      ]),
    ),
  );
  if (result == null) return;
  final v = parseAmount(ctl.text) ?? 0;
  switch (result) {
    case 'month':
      await app.setMonthBudget(per, c.id, v);
    case 'template':
      await app.setTemplateBudget(c.id, v, clearFor: fromTemplate ? null : per);
    case 'reset':
      await app.resetMonthBudget(per, c.id);
  }
}

class _MonthTab extends StatelessWidget {
  const _MonthTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final per = app.period;
        final s = statsFor(per);
        final total = app.totalBudget(per);
        final saveCats = app.active('expense').where((c) => c.isSaving).toList();
        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          const Padding(padding: EdgeInsets.only(top: 4), child: Center(child: PeriodSwitcher())),
          SectionCard(
            child: Row(children: [
              _fig(context, 'Budgeted', total),
              _fig(context, 'Spent', s.spend),
              _fig(context, total >= s.spend ? 'Left' : 'Over', (total - s.spend).abs(),
                  color: total >= s.spend ? goodColor : badColor),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: Text('Tap a category to change it for this period only or update the template.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          for (final c in [...app.spendingCategories, ...saveCats]) _row(context, c, s.byCat[c.id] ?? (c.isSaving ? _saved(s, c.id) : 0)),
        ]);
      },
    );
  }

  double _saved(PeriodStats s, int id) =>
      s.list.where((t) => t.categoryId == id && t.kind == 'expense').fold(0.0, (a, t) => a + t.amount);

  Widget _fig(BuildContext context, String label, double v, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(label),
          Text(fmt(v),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: color, fontFeatures: tabular)),
        ]),
      );

  Widget _row(BuildContext context, Category c, double spent) {
    final cs = Theme.of(context).colorScheme;
    final per = app.period;
    final b = app.budgetFor(per, c.id);
    final custom = app.isOverridden(per, c.id);
    return InkWell(
      onTap: () => _editAmount(context, c, fromTemplate: false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CategoryDot(c.color),
            const SizedBox(width: 8),
            Flexible(child: Text(c.isSaving ? '${c.name} (target)' : c.name, overflow: TextOverflow.ellipsis)),
            if (custom) ...[const SizedBox(width: 6), Pill('this period', cs.primary)],
            const Spacer(),
            Text(b > 0 ? '${fmt(spent)} / ${fmt(b)}' : '${fmt(spent)} · no budget',
                style: TextStyle(
                    fontFeatures: tabular,
                    fontSize: 13.5,
                    color: !c.isSaving && b > 0 && spent > b ? badColor : cs.onSurfaceVariant)),
          ]),
          if (b > 0) ...[
            const SizedBox(height: 6),
            BudgetBar(spent: spent, budget: b, color: c.isSaving ? goodColor : null),
          ],
        ]),
      ),
    );
  }
}

class _TemplateTab extends StatelessWidget {
  const _TemplateTab();

  Future<void> _suggest(BuildContext context) async {
    final avg = averages(app.period, n: 3);
    if (avg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least one earlier period with entries to suggest amounts.')));
      return;
    }
    final values = <int, double>{};
    avg.forEach((id, v) {
      final step = v >= 1000 ? 100 : 50;
      values[id] = ((v / step).ceil() * step).toDouble();
    });
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fill template from your history?'),
        content: Text('Sets ${values.length} categories to their average over the last 3 periods, rounded up. '
            'Categories with no history keep their current value.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok == true) await app.setTemplateBudgets(values);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final income = app.expectedIncome;
        final spendTotal = app.templateTotal();
        final saveTotal = app.templateTotal(includeSavings: true) - spendTotal;
        double grp(String g) => app.active('expense').where((c) => c.grp == g).fold(0.0, (a, c) => a + c.budget);
        final need = grp('need'), want = grp('want');
        final unplanned = income - spendTotal - saveTotal;

        return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          SectionCard(
            title: 'Monthly plan',
            trailing: TextButton.icon(
              onPressed: () => _suggest(context),
              icon: const Icon(Icons.auto_graph, size: 18),
              label: const Text('Suggest'),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () => _editIncome(context),
                child: Row(children: [
                  const Expanded(child: Text('Expected monthly income')),
                  Text(income > 0 ? money(income) : 'Set',
                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary, fontFeatures: tabular)),
                  const Icon(Icons.edit, size: 16),
                ]),
              ),
              const Divider(height: 24),
              _line(context, 'Spending budgets', spendTotal),
              _line(context, 'Savings target', saveTotal),
              if (income > 0)
                _line(context, unplanned >= 0 ? 'Unallocated' : 'Over-allocated', unplanned.abs(),
                    color: unplanned >= 0 ? cs.onSurfaceVariant : badColor),
              if (income > 0) ...[
                const SizedBox(height: 12),
                SplitBar([(need, spendColor), (want, warnColor), (saveTotal + (unplanned > 0 ? unplanned : 0), cs.primary)]),
                const SizedBox(height: 6),
                Text(
                  'Needs ${(need / income * 100).round()}% · Wants ${(want / income * 100).round()}% · '
                  'Savings ${((saveTotal + (unplanned > 0 ? unplanned : 0)) / income * 100).round()}%   (guide 50 / 30 / 20)',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text('Every period starts from these amounts. Change a single period from the "This period" tab.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          for (final g in const [('need', 'Needs'), ('want', 'Wants'), ('save', 'Savings')]) ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4), child: Eyebrow(g.$2)),
            for (final c in app.active('expense').where((c) => c.grp == g.$1))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: CategoryDot(c.color, size: 12),
                title: Text(c.name),
                trailing: Text(c.budget > 0 ? fmt(c.budget) : '—',
                    style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
                onTap: () => _editAmount(context, c, fromTemplate: true),
              ),
          ],
        ]);
      },
    );
  }

  Widget _line(BuildContext context, String label, double v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(money(v), style: TextStyle(fontFeatures: tabular, color: color)),
        ]),
      );

  Future<void> _editIncome(BuildContext context) async {
    final ctl = TextEditingController(text: app.expectedIncome > 0 ? fmtAuto(app.expectedIncome).replaceAll(',', '') : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Expected monthly income'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: app.currency, helperText: 'Salary plus allowances, used for planning only'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) await app.setSetting('expectedIncome', '${parseAmount(ctl.text) ?? 0}');
  }
}
