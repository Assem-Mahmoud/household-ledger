import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../widgets.dart';

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
      setState(() => error = 'Enter an amount above zero.');
      return;
    }
    if (categoryId == null) {
      setState(() => error = 'Pick a category.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final t = widget.existing ?? Txn(kind: kind, amount: amount, categoryId: categoryId!, date: isoDate(date));
    t
      ..kind = kind
      ..amount = amount
      ..categoryId = categoryId!
      ..date = isoDate(date)
      ..merchant = merchantCtl.text.trim()
      ..note = noteCtl.text.trim();
    await app.saveTxn(t);
    if (t.merchant.isNotEmpty) await app.learnRule(t.merchant, t.categoryId);
    if (!mounted) return;
    if (another) {
      setState(() {
        saving = false;
        savedCount++;
        amountCtl.clear();
        merchantCtl.clear();
        noteCtl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${fmtAuto(amount)} ${app.currency}'), duration: const Duration(seconds: 1)));
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It will be removed from your totals. Entries from SMS go back to the review list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
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
        title: Text(editing ? 'Edit entry' : 'Add entry'),
        actions: [
          if (editing) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense'), icon: Icon(Icons.north_east)),
              ButtonSegment(value: 'income', label: Text('Income'), icon: Icon(Icons.south_west)),
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
              labelText: 'Amount',
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
                  avatar: CategoryDot(c.color),
                  label: Text(c.name),
                  selected: categoryId == c.id,
                  onSelected: (_) => setState(() => categoryId = c.id),
                ),
            ],
          ),
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
              decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
              child: Text('${shortDate(date)} ${date.year}'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: merchantCtl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Merchant or payee (optional)',
              helperText: 'The category is remembered for this merchant next time.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtl,
            decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: badColor)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            if (!editing)
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => _save(another: true),
                  child: Text(savedCount > 0 ? 'Save & next ($savedCount)' : 'Save & add another'),
                ),
              ),
            if (!editing) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(onPressed: saving ? null : _save, child: const Text('Save')),
            ),
          ]),
        ],
      ),
    );
  }
}
