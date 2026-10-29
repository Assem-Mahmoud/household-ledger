import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'plan.dart' show editFund;
import 'profile.dart' show accountIcon, editAccount;

/// Add or edit a manual entry. "Save & add another" supports quick end-of-day logging.
class EntryForm extends StatefulWidget {
  final Txn? existing;
  final String? initialKind;
  const EntryForm({super.key, this.existing, this.initialKind});

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  late String kind;
  int? categoryId;
  int? accountId;
  late DateTime date;
  final amountCtl = TextEditingController();
  final merchantCtl = TextEditingController();
  final noteCtl = TextEditingController();
  String? error;
  bool saving = false;
  int savedCount = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    kind = t?.kind ?? widget.initialKind ?? 'expense';
    categoryId = t?.categoryId;
    accountId = t != null ? t.accountId : app.lastAccountId;
    date = t != null ? parseIso(t.date) : DateTime.now();
    if (t != null) {
      amountCtl.text = fmtAuto(t.amount).replaceAll(',', '');
      merchantCtl.text = t.merchant;
      noteCtl.text = t.note;
    }
  }

  @override
  void dispose() {
    amountCtl.dispose();
    merchantCtl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  Future<void> _save({bool another = false}) async {
    final amount = parseAmount(amountCtl.text);
    if (amount == null || amount <= 0) {
      setState(() => error = tr('Enter an amount above zero.'));
      return;
    }
    if (categoryId == null) {
      setState(() => error = tr('Pick a category.'));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final t = widget.existing ?? Txn(kind: kind, amount: amount, categoryId: categoryId!, date: isoDate(date));
    final oldCategory = widget.existing?.categoryId;
    t
      ..kind = kind
      ..amount = amount
      ..categoryId = categoryId!
      ..date = isoDate(date)
      ..merchant = merchantCtl.text.trim()
      ..note = noteCtl.text.trim()
      ..accountId = accountId;
    await app.saveTxn(t);
    if (t.merchant.isNotEmpty) await app.learnRule(t.merchant, t.categoryId);
    if (!mounted) return;
    // Changed the category of a merchant? Offer to move its other entries too.
    if (t.merchant.isNotEmpty && oldCategory != t.categoryId) {
      final others = app.sameMerchantElsewhere(t);
      if (others.isNotEmpty) {
        final move = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('Update other {m} entries?', {'m': t.merchant})),
            content: Text(tr('{n} other entries from {m} are in a different category. Move them to {cat} as well?',
                {'n': others.length, 'm': t.merchant, 'cat': app.cat(t.categoryId)?.display ?? ''})),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Only this one')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Move all')),
            ],
          ),
        );
        if (move == true) await app.moveToCategory(others, t.categoryId);
        if (!mounted) return;
      }
    }
    if (another) {
      setState(() {
        saving = false;
        savedCount++;
        amountCtl.clear();
        merchantCtl.clear();
        noteCtl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Saved {a} {cur}', {'a': fmtAuto(amount), 'cur': app.currency})), duration: const Duration(seconds: 1)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Delete this entry?'),
        content: const T('It will be removed from your totals. Entries from SMS go back to the review list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await app.deleteTxn(widget.existing!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = app.active(kind);
    if (categoryId != null && app.cat(categoryId!)?.kind != kind) categoryId = null;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(editing ? 'Edit entry' : 'Add entry')),
        actions: [
          if (editing) IconButton(tooltip: tr('Delete'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: T('Expense'), icon: Icon(Icons.north_east)),
              ButtonSegment(value: 'income', label: T('Income'), icon: Icon(Icons.south_west)),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountCtl,
            autofocus: !editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, fontFeatures: tabular),
            decoration: InputDecoration(
              labelText: tr('Amount'),
              suffixText: app.currency,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Eyebrow('Category'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cats)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(categoryIcon(c), size: 18, color: categoryColor(c)),
                  label: Text(c.display),
                  selected: categoryId == c.id,
                  onSelected: (_) => setState(() => categoryId = c.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Eyebrow('Paid from'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in app.activeAccounts)
              ChoiceChip(
                avatar: Icon(accountIcon(a.type), size: 18),
                label: Text(a.name),
                selected: accountId == a.id,
                onSelected: (v) => setState(() => accountId = v ? a.id : null),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(tr(app.activeAccounts.isEmpty ? 'Add account or card' : 'New')),
              onPressed: () async {
                final before = app.accounts.length;
                await editAccount(context, null);
                if (app.accounts.length > before) setState(() => accountId = app.accounts.last.id);
              },
            ),
          ]),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2015),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => date = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: tr('Date'), border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today)),
              child: Text('${shortDate(date)} ${date.year}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: merchantCtl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('Merchant or payee (optional)'),
              helperText: tr('The category is remembered for this merchant next time.'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            decoration: InputDecoration(labelText: tr('Note (optional)'), border: const OutlineInputBorder()),
          ),
          if (editing && kind == 'expense') ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.event_repeat, size: 18),
                label: const T('This comes every year — plan for it'),
                onPressed: () {
                  final t = widget.existing!;
                  final d = parseIso(t.date);
                  editFund(context, null,
                      title: t.label.isNotEmpty ? t.label : app.cat(t.categoryId)?.display,
                      amount: t.amount,
                      due: DateTime(d.year + 1, d.month, d.day),
                      categoryId: t.categoryId);
                },
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: badColor)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            if (!editing)
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => _save(another: true),
                  child: Text(savedCount > 0 ? tr('Save & next ({n})', {'n': savedCount}) : tr('Save & add another')),
                ),
              ),
            if (!editing) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: saving ? null : _save, child: const T('Save')),
            ),
          ]),
        ],
      ),
    );
  }
}
