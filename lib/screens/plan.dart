import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../widgets.dart';

/// Monthly checklist: bills to pay and amounts to set aside, ticked off as they happen.
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final per = app.period;
        final lines = app.planFor(per);
        final total = lines.fold<double>(0, (a, l) => a + l.target);
        final doneAmount = lines.where((l) => l.done).fold<double>(0, (a, l) => a + l.target);
        final income = app.expectedIncome;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'plan-add',
            onPressed: () => editPlanItem(context, null),
            icon: const Icon(Icons.add_task),
            label: const Text('Add to plan'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            const Padding(padding: EdgeInsets.only(top: 4), child: Center(child: PeriodSwitcher())),
            SectionCard(
              child: lines.isEmpty
                  ? Text(
                      'Plan what must happen each month: rent to pay, school fees, an amount to save. '
                      'Tick each one off when it\'s done, or link it to a category to tick it automatically.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${lines.where((l) => l.done).length} of ${lines.length} done',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Text('${fmt(doneAmount)} / ${fmt(total)}',
                            style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: tabular)),
                      ]),
                      const SizedBox(height: 8),
                      BudgetBar(spent: doneAmount, budget: total, color: goodColor),
                      if (income > 0) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Income ${fmt(income)} − plan ${fmt(total)} = ${fmt(income - total)} ${app.currency} '
                          'left for day-to-day spending',
                          style: TextStyle(
                              color: income - total < 0 ? badColor : cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ]),
            ),
            for (final l in lines) PlanTile(l, per: per),
          ]),
        );
      },
    );
  }
}

/// One checklist row; also used on the Home card.
class PlanTile extends StatelessWidget {
  final PlanLine line;
  final Period per;
  final bool dense;
  const PlanTile(this.line, {super.key, required this.per, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final it = line.item;
    final status = line.status;
    final statusText = switch (status) {
      'done' => line.autoDone && !line.manualDone ? 'Done (from entries)' : 'Done',
      'overdue' => 'Overdue since ${shortDate(line.due!)}',
      'due' => 'Due ${shortDate(line.due!)}',
      _ => line.due != null ? 'By ${shortDate(line.due!)}' : 'This month',
    };
    final statusColor = switch (status) {
      'done' => goodColor,
      'overdue' => badColor,
      'due' => warnColor,
      _ => cs.onSurfaceVariant,
    };
    final linked = it.categoryId != null ? app.cat(it.categoryId!) : null;
    final tile = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Checkbox(
        value: line.done,
        onChanged: line.autoDone && !line.manualDone
            ? null
            : (v) => app.setPlanDone(per, it, v ?? false),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(it.kind == 'save' ? Icons.savings_outlined : Icons.receipt_outlined, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(it.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: line.done ? TextDecoration.lineThrough : null,
                      color: line.done ? cs.onSurfaceVariant : null,
                    )),
              ),
              Text(fmt(line.target), style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Expanded(child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12.5))),
              if (line.overridden) Text('this month', style: TextStyle(color: cs.primary, fontSize: 12)),
            ]),
            if (linked != null && !line.done && !dense) ...[
              const SizedBox(height: 6),
              BudgetBar(spent: line.progress, budget: line.target, color: goodColor),
              const SizedBox(height: 3),
              Text('${fmt(line.progress)} logged under ${linked.name}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ]);
    return InkWell(
      onTap: () => editPlanItem(context, line),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 12), child: tile),
    );
  }
}

/// Add a new plan item, or edit/remove an existing one.
Future<void> editPlanItem(BuildContext context, PlanLine? line) async {
  final per = app.period;
  final existing = line?.item;
  final titleCtl = TextEditingController(text: existing?.title ?? '');
  final amountCtl = TextEditingController(
      text: line != null ? fmtAuto(line.target).replaceAll(',', '') : '');
  var kind = existing?.kind ?? 'pay';
  int? dueDay = existing?.dueDay;
  int? categoryId = existing?.categoryId;
  var recurring = existing?.recurring ?? true;
  String? error;

  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(existing == null ? 'Add to plan' : 'Edit plan item', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pay', label: Text('Pay'), icon: Icon(Icons.receipt_outlined)),
                ButtonSegment(value: 'save', label: Text('Save'), icon: Icon(Icons.savings_outlined)),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() => kind = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtl,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: kind == 'save' ? 'What are you saving for?' : 'What to pay',
                hintText: kind == 'save' ? 'e.g. Rent fund, Emergency fund' : 'e.g. Rent, School fees',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount this month', suffixText: app.currency, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: dueDay,
              decoration: const InputDecoration(labelText: 'Due by', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Any time this month')),
                for (var d = 1; d <= 31; d++) DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
              ],
              onChanged: (v) => setState(() => dueDay = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tick automatically from category (optional)',
                helperText: 'Ticks itself once entries in this category reach the amount',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('No, I\'ll tick it myself')),
                for (final cat in app.active('expense'))
                  DropdownMenuItem<int?>(
                    value: cat.id,
                    child: Row(children: [CategoryDot(cat.color), const SizedBox(width: 8), Text(cat.name)]),
                  ),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),
            if (existing == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat every month'),
                subtitle: Text(recurring ? 'Added to every month from ${per.label}' : 'Only for ${per.label}'),
                value: recurring,
                onChanged: (v) => setState(() => recurring = v),
              ),
            if (error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: badColor)),
            ),
            const SizedBox(height: 16),
            if (existing == null)
              FilledButton(
                onPressed: () {
                  if (titleCtl.text.trim().isEmpty || (parseAmount(amountCtl.text) ?? 0) <= 0) {
                    setState(() => error = 'Enter a name and an amount above zero.');
                    return;
                  }
                  Navigator.pop(c, 'add');
                },
                child: const Text('Add'),
              )
            else ...[
              if (existing.recurring)
                FilledButton(onPressed: () => Navigator.pop(c, 'all'), child: const Text('Save for every month')),
              if (existing.recurring) const SizedBox(height: 8),
              if (existing.recurring)
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, 'month'),
                  child: Text('Change amount for ${per.label} only'),
                )
              else
                FilledButton(onPressed: () => Navigator.pop(c, 'month'), child: const Text('Save')),
              if (line!.overridden) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(c, 'reset'), child: const Text('Use the usual amount this month')),
              ],
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: badColor),
                onPressed: () => Navigator.pop(c, 'remove'),
                child: Text(existing.recurring ? 'Stop from ${per.label} on' : 'Remove'),
              ),
            ],
          ]),
        ),
      ),
    ),
  );
  if (action == null) return;
  final amount = parseAmount(amountCtl.text) ?? 0;
  final title = titleCtl.text.trim();
  switch (action) {
    case 'add':
      await app.savePlanItem(PlanItem(
        id: 0,
        title: title,
        kind: kind,
        amount: amount,
        dueDay: dueDay,
        categoryId: categoryId,
        startPeriod: per.key,
        onlyPeriod: recurring ? null : per.key,
      ));
    case 'all':
      existing!
        ..title = title.isEmpty ? existing.title : title
        ..kind = kind
        ..amount = amount > 0 ? amount : existing.amount
        ..dueDay = dueDay
        ..categoryId = categoryId;
      await app.savePlanItem(existing);
      if (line!.overridden) await app.setPlanAmountForPeriod(per, existing, null);
    case 'month':
      existing!
        ..title = title.isEmpty ? existing.title : title
        ..kind = kind
        ..dueDay = dueDay
        ..categoryId = categoryId;
      if (!existing.recurring && amount > 0) existing.amount = amount;
      await app.savePlanItem(existing);
      if (existing.recurring && amount > 0) await app.setPlanAmountForPeriod(per, existing, amount);
    case 'reset':
      await app.setPlanAmountForPeriod(per, existing!, null);
    case 'remove':
      await app.removePlanItem(existing!, per);
  }
}

/// Compact checklist for the Home screen.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final per = app.period;
    final lines = app.planFor(per);
    final cs = Theme.of(context).colorScheme;
    final open = lines.where((l) => !l.done).toList();
    final left = open.fold<double>(0, (a, l) => a + l.remaining);
    return SectionCard(
      title: 'Monthly plan',
      trailing: TextButton(
          onPressed: () {
            app.budgetTab.value = 1;
            app.tab.value = 4;
          },
          child: Text(lines.isEmpty ? 'Set up' : 'All')),
      child: lines.isEmpty
          ? Text('Add what must happen each month (rent, fees, savings) and tick it off as you go.',
              style: TextStyle(color: cs.onSurfaceVariant))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                open.isEmpty
                    ? 'Everything in this month\'s plan is done.'
                    : '${lines.length - open.length} of ${lines.length} done · ${fmt(left)} ${app.currency} still to go',
                style: TextStyle(color: open.isEmpty ? goodColor : cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final l in (open.isEmpty ? lines : open).take(4)) PlanTile(l, per: per, dense: true),
            ]),
    );
  }
}
