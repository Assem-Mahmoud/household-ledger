import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../funds.dart';
import '../i18n.dart';
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
            label: const T('Add to plan'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            const Padding(padding: EdgeInsets.only(top: 4), child: Center(child: PeriodSwitcher())),
            SectionCard(
              child: lines.isEmpty
                  ? T(
                      'Plan what must happen each month: rent to pay, school fees, an amount to save. '
                      'Tick each one off when it\'s done, or link it to a category to tick it automatically.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text(tr('{a} of {b} done', {'a': lines.where((l) => l.done).length, 'b': lines.length}),
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
                          tr('Income {i} − plan {p} = {r} {cur} left for day-to-day spending',
                              {'i': fmt(income), 'p': fmt(total), 'r': fmt(income - total), 'cur': app.currency}),
                          style: TextStyle(
                              color: income - total < 0 ? badColor : cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ]),
            ),
            for (final l in lines) PlanTile(l, per: per),
            const YearlySection(),
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
    final f = line.fund;
    final statusText = f != null
        ? _fundStatus(line, f, status)
        : switch (status) {
      'done' => tr(line.autoDone && !line.manualDone ? 'Done (from entries)' : 'Done'),
      'overdue' => tr('Overdue since {d}', {'d': shortDate(line.due!)}),
      'due' => tr('Due {d}', {'d': shortDate(line.due!)}),
      _ => line.due != null ? tr('By {d}', {'d': shortDate(line.due!)}) : tr('This month'),
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
        onChanged: f != null
            ? (v) => line.fundPay
                ? app.markFundPaid(per, f, v ?? false)
                : app.setFundSaved(per, f, v ?? false, line.target)
            : line.autoDone && !line.manualDone
                ? null
                : (v) => app.setPlanDone(per, it, v ?? false),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(f != null ? Icons.event_repeat : it.kind == 'save' ? Icons.savings_outlined : Icons.receipt_outlined,
                  size: 16, color: cs.onSurfaceVariant),
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
              if (line.overridden) T('this month', style: TextStyle(color: cs.primary, fontSize: 12)),
            ]),
            if (linked != null && !line.done && !dense) ...[
              const SizedBox(height: 6),
              BudgetBar(spent: line.progress, budget: line.target, color: goodColor),
              const SizedBox(height: 3),
              Text(tr('{a} logged under {cat}', {'a': fmt(line.progress), 'cat': linked.display}),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ]);
    return InkWell(
      onTap: () => f != null ? editFund(context, f) : editPlanItem(context, line),
      child: Padding(padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 12), child: tile),
    );
  }
}

String _fundStatus(PlanLine line, Fund f, String status) {
  if (line.fundPay) {
    if (line.done) return tr('Paid');
    final saved = f.saved > 0 ? ' · ${tr('{a} already saved', {'a': fmt(f.saved)})}' : '';
    final when = status == 'overdue'
        ? tr('Overdue since {d}', {'d': shortDate(f.due)})
        : tr('Due {d}', {'d': shortDate(f.due)});
    return '$when · ${tr('total {a}', {'a': fmt(f.amount)})}$saved';
  }
  if (line.done) return tr('Set aside');
  return tr('Set aside for {d} · {a} of {b} saved',
      {'d': '${shortDate(f.due)} ${f.due.year}', 'a': fmt(f.saved), 'b': fmt(f.amount)});
}

/// Yearly and irregular expenses, spread over the months before they are due.
class YearlySection extends StatelessWidget {
  const YearlySection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = app.activeFunds;
    return SectionCard(
      title: 'Yearly & irregular expenses',
      trailing: TextButton.icon(
        onPressed: () => editFund(context, null),
        icon: const Icon(Icons.add, size: 18),
        label: const T('Add'),
      ),
      child: list.isEmpty
          ? T('Car insurance, school fees, Iqama or registration renewal… Add them with their due date and the app '
              'works out how much to set aside each month. It appears in your monthly plan automatically.',
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.4))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final f in list)
                InkWell(
                  onTap: () => editFund(context, f),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(fmt(f.amount), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                      ]),
                      const SizedBox(height: 4),
                      BudgetBar(spent: f.saved, budget: f.amount, color: goodColor),
                      const SizedBox(height: 4),
                      Text(
                        [
                          tr('Due {d}', {'d': '${shortDate(f.due)} ${f.due.year}'}),
                          tr('{a} saved', {'a': fmt(f.saved)}),
                          if (app.fundMonthly(f) > 0)
                            tr('{a} {cur} a month', {'a': fmt(app.fundMonthly(f)), 'cur': app.currency})
                          else if (f.saved >= f.amount)
                            tr('Fully saved'),
                          if (f.repeatMonths > 0) tr(_repeatLabel(f.repeatMonths)),
                        ].join(' · '),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                      ),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

String _repeatLabel(int months) => switch (months) {
      12 => 'Every year',
      6 => 'Every 6 months',
      3 => 'Every 3 months',
      0 => 'Only once',
      _ => 'Every {n} months',
    };

/// Add or edit a yearly/irregular expense. [title], [amount], [due] and [categoryId] prefill a new one.
Future<void> editFund(BuildContext context, Fund? existing,
    {String? title, double? amount, DateTime? due, int? categoryId}) async {
  final titleCtl = TextEditingController(text: existing?.title ?? title ?? '');
  final amountCtl = TextEditingController(
      text: existing != null ? fmtAuto(existing.amount).replaceAll(',', '') : amount != null ? fmtAuto(amount).replaceAll(',', '') : '');
  final savedCtl = TextEditingController(
      text: existing != null && existing.saved > 0 ? fmtAuto(existing.saved).replaceAll(',', '') : '');
  var dueDate = existing?.due ?? due;
  var repeat = existing?.repeatMonths ?? 12;
  int? cat = existing?.categoryId ?? categoryId;
  String? error;

  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, setState) {
      final a = parseAmount(amountCtl.text) ?? 0;
      final sv = parseAmount(savedCtl.text) ?? 0;
      final cur = periodFor(DateTime.now(), app.cycleStartDay);
      final months = dueDate == null ? 0 : periodsBefore(cur, dueDate!, app.cycleStartDay);
      final monthly = dueDate == null || a <= 0
          ? 0.0
          : monthlySetAside(amount: a, savedBefore: sv, from: cur, due: dueDate!, startDay: app.cycleStartDay);
      final preview = dueDate == null || a <= 0
          ? null
          : a - sv <= 0
              ? tr('Already fully saved.')
              : months <= 0
                  ? tr('Due this month: {a} {cur} still needed.', {'a': fmt(a - sv), 'cur': app.currency})
                  : trn(months, 'Set aside {a} {cur} a month for {n} month, starting {m}.',
                      'Set aside {a} {cur} a month for {n} months, starting {m}.',
                      {'a': fmt(monthly), 'cur': app.currency, 'm': cur.label});
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(existing == null ? 'Add yearly expense' : 'Edit yearly expense'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtl,
              autofocus: existing == null && title == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('What is it?'),
                hintText: tr('e.g. Car insurance, School fees, Iqama renewal'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Amount'), suffixText: app.currency, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: dueDate ?? DateTime.now().add(const Duration(days: 180)),
                  firstDate: DateTime.now().subtract(const Duration(days: 60)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                );
                if (d != null) setState(() => dueDate = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                    labelText: tr('Next due date'), border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.event)),
                child: Text(dueDate == null ? tr('Pick a date') : '${shortDate(dueDate!)} ${dueDate!.year}'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: savedCtl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Already saved for it (optional)'),
                helperText: tr('Leave empty to start from zero.'),
                suffixText: app.currency,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: repeat,
              decoration: InputDecoration(labelText: tr('Repeats'), border: const OutlineInputBorder()),
              items: [
                for (final m in const [12, 6, 3, 0]) DropdownMenuItem(value: m, child: Text(tr(_repeatLabel(m)))),
              ],
              onChanged: (v) => setState(() => repeat = v ?? 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: cat,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Category (optional)'), border: const OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: T('None')),
                for (final x in app.active('expense'))
                  DropdownMenuItem<int?>(
                    value: x.id,
                    child: Row(children: [CategoryDot(x.color), const SizedBox(width: 8), Text(x.display)]),
                  ),
              ],
              onChanged: (v) => setState(() => cat = v),
            ),
            if (preview != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Theme.of(c).colorScheme.primaryContainer.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(preview, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: badColor))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (titleCtl.text.trim().isEmpty || a <= 0 || dueDate == null) {
                  setState(() => error = tr('Enter a name, an amount and the due date.'));
                  return;
                }
                Navigator.pop(c, 'save');
              },
              child: const T('Save'),
            ),
            if (existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: badColor),
                onPressed: () => Navigator.pop(c, 'delete'),
                child: const T('Remove'),
              ),
            ],
          ]),
        ),
      );
    }),
  );
  if (action == null) return;
  if (action == 'delete') {
    await app.deleteFund(existing!);
    return;
  }
  final f = existing ?? Fund(id: 0, title: '', amount: 0, dueDate: isoDate(dueDate!));
  f
    ..title = titleCtl.text.trim()
    ..amount = parseAmount(amountCtl.text) ?? 0
    ..dueDate = isoDate(dueDate!)
    ..saved = parseAmount(savedCtl.text) ?? 0
    ..repeatMonths = repeat
    ..categoryId = cat
    ..archived = false;
  await app.saveFund(f);
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
            Text(tr(existing == null ? 'Add to plan' : 'Edit plan item'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pay', label: T('Pay'), icon: Icon(Icons.receipt_outlined)),
                ButtonSegment(value: 'save', label: T('Save'), icon: Icon(Icons.savings_outlined)),
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
                labelText: tr(kind == 'save' ? 'What are you saving for?' : 'What to pay'),
                hintText: tr(kind == 'save' ? 'e.g. Rent fund, Emergency fund' : 'e.g. Rent, School fees'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Amount this month'), suffixText: app.currency, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: dueDay,
              decoration: InputDecoration(labelText: tr('Due by'), border: const OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(value: null, child: T('Any time this month')),
                for (var d = 1; d <= 31; d++) DropdownMenuItem<int?>(value: d, child: Text(tr('Day {n}', {'n': d}))),
              ],
              onChanged: (v) => setState(() => dueDay = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              value: categoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr('Tick automatically from category (optional)'),
                helperText: tr('Ticks itself once entries in this category reach the amount'),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: T('No, I\'ll tick it myself')),
                for (final cat in app.active('expense'))
                  DropdownMenuItem<int?>(
                    value: cat.id,
                    child: Row(children: [CategoryDot(cat.color), const SizedBox(width: 8), Text(cat.display)]),
                  ),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),
            if (existing == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const T('Repeat every month'),
                subtitle: Text(tr(recurring ? 'Added to every month from {m}' : 'Only for {m}', {'m': per.label})),
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
                    setState(() => error = tr('Enter a name and an amount above zero.'));
                    return;
                  }
                  Navigator.pop(c, 'add');
                },
                child: const T('Add'),
              )
            else ...[
              if (existing.recurring)
                FilledButton(onPressed: () => Navigator.pop(c, 'all'), child: const T('Save for every month')),
              if (existing.recurring) const SizedBox(height: 8),
              if (existing.recurring)
                OutlinedButton(
                  onPressed: () => Navigator.pop(c, 'month'),
                  child: Text(tr('Change amount for {m} only', {'m': per.label})),
                )
              else
                FilledButton(onPressed: () => Navigator.pop(c, 'month'), child: const T('Save')),
              if (line!.overridden) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(c, 'reset'), child: const T('Use the usual amount this month')),
              ],
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: badColor),
                onPressed: () => Navigator.pop(c, 'remove'),
                child: Text(existing.recurring ? tr('Stop from {m} on', {'m': per.label}) : tr('Remove')),
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
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
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
          child: Text(tr(lines.isEmpty ? 'Set up' : 'All'))),
      child: lines.isEmpty
          ? T('Add what must happen each month (rent, fees, savings) and tick it off as you go.',
              style: TextStyle(color: cs.onSurfaceVariant))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                open.isEmpty
                    ? tr('Everything in this month\'s plan is done.')
                    : tr('{a} of {b} done · {r} {cur} still to go',
                        {'a': lines.length - open.length, 'b': lines.length, 'r': fmt(left), 'cur': app.currency}),
                style: TextStyle(color: open.isEmpty ? goodColor : cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final l in (open.isEmpty ? lines : open).take(4)) PlanTile(l, per: per, dense: true),
            ]),
    );
  }
}
