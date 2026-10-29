import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart' show accountIcon, editAccount;
import 'review.dart' show frequentCategories, pickCategory;

/// Calculator-style entry: amount on a number pad, one tap for the category, save.
class QuickAddScreen extends StatefulWidget {
  final String kind;
  const QuickAddScreen({super.key, this.kind = 'expense'});
  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  late String kind = widget.kind;
  String digits = '';
  int? categoryId;
  int? extraCategory; // picked from "More" when it isn't among the shortcuts
  int? accountId = app.lastAccountId;
  DateTime date = DateTime.now();
  String merchant = '';
  String note = '';
  bool saving = false;

  double get amount => double.tryParse(digits) ?? 0;

  String get shown {
    if (digits.isEmpty) return '0';
    final parts = digits.split('.');
    final whole = fmt(double.tryParse(parts[0]) ?? 0);
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  void _key(String k) {
    setState(() {
      if (k == '⌫') {
        if (digits.isNotEmpty) digits = digits.substring(0, digits.length - 1);
        return;
      }
      if (k == '.') {
        if (!digits.contains('.')) digits = digits.isEmpty ? '0.' : '$digits.';
        return;
      }
      if (digits.contains('.') && digits.split('.')[1].length >= 2) return;
      if (digits.replaceAll('.', '').length >= 9) return;
      digits = digits == '0' ? k : digits + k;
    });
  }

  Future<void> _details() async {
    final mCtl = TextEditingController(text: merchant);
    final nCtl = TextEditingController(text: note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Details'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: mCtl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Merchant or payee (optional)')),
          ),
          const SizedBox(height: 10),
          TextField(controller: nCtl, decoration: InputDecoration(labelText: tr('Note (optional)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Save')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        merchant = mCtl.text.trim();
        note = nCtl.text.trim();
      });
    }
  }

  Future<void> _save() async {
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Enter an amount above zero.')));
      return;
    }
    if (categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Pick a category.')));
      return;
    }
    setState(() => saving = true);
    final t = Txn(
      kind: kind,
      amount: amount,
      categoryId: categoryId!,
      date: isoDate(date),
      merchant: merchant,
      note: note,
      accountId: accountId,
    );
    await app.saveTxn(t);
    if (merchant.isNotEmpty) await app.learnRule(merchant, categoryId!);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
        content: Text(tr('Saved {a} {cur}', {'a': fmtAuto(amount), 'cur': app.currency})), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    var shortcuts = frequentCategories(kind).take(7).toList();
    if (categoryId != null && app.cat(categoryId!)?.kind != kind) categoryId = null;
    if (extraCategory != null && !shortcuts.any((x) => x.id == extraCategory) && app.cat(extraCategory!) != null) {
      shortcuts = [...shortcuts.take(6), app.cat(extraCategory!)!];
    }
    final today = DateTime.now();
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;

    Widget pill(IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12), shape: const StadiumBorder()),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 13)),
        );

    return Scaffold(
      backgroundColor: c.card,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [
              IconButton(tooltip: tr('Close'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 220,
                    child: SegmentTabs(
                      selected: kind == 'expense' ? 0 : 1,
                      onSelect: (i) => setState(() {
                        kind = i == 0 ? 'expense' : 'income';
                        categoryId = null;
                        extraCategory = null;
                      }),
                      labels: [Text(tr('Expense')), Text(tr('Income'))],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(shown,
                        style: TextStyle(fontSize: 52, fontWeight: FontWeight.w700, letterSpacing: -1, color: digits.isEmpty ? c.muted : c.text, fontFeatures: tabular)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(app.currency, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.muted)),
              ]),
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                pill(Icons.calendar_today_outlined, isToday ? tr('Today') : '${shortDate(date)} ${date.year}', () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => date = d);
                }),
                pill(Icons.edit_outlined, merchant.isNotEmpty ? merchant : note.isNotEmpty ? note : tr('Add note'), _details),
              ]),
              const SizedBox(height: 18),
              Text(tr('Category'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 8),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.05,
                children: [
                  for (final cat in shortcuts) _CatButton(cat: cat, selected: categoryId == cat.id, onTap: () => setState(() => categoryId = cat.id)),
                  _CatButton(
                    cat: null,
                    selected: false,
                    onTap: () async {
                      final id = await pickCategory(context, kind, selected: categoryId);
                      if (id != null) {
                        setState(() {
                          categoryId = id;
                          extraCategory = id;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(tr('Paid from'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final a in app.activeAccounts)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(accountIcon(a.type), size: 16),
                    label: Text(a.name),
                    selected: accountId == a.id,
                    onSelected: (v) => setState(() => accountId = v ? a.id : null),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(tr(app.activeAccounts.isEmpty ? 'Add account or card' : 'New')),
                  onPressed: () async {
                    final before = app.accounts.length;
                    await editAccount(context, null);
                    if (app.accounts.length > before) setState(() => accountId = app.accounts.last.id);
                  },
                ),
              ]),
            ]),
          ),
          Container(
            color: c.bg,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(children: [
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['.', '0', '⌫']])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    for (final k in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Material(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _key(k),
                              onLongPress: k == '⌫' ? () => setState(() => digits = '') : null,
                              child: SizedBox(
                                height: 50,
                                child: Center(
                                  child: k == '⌫'
                                      ? Icon(Icons.backspace_outlined, color: c.text, semanticLabel: tr('Delete'))
                                      : Text(k, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: saving ? null : _save,
                  child: Text(tr(kind == 'income' ? 'Save income' : 'Save expense'), style: const TextStyle(fontSize: 17)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CatButton extends StatelessWidget {
  final Category? cat; // null = "More"
  final bool selected;
  final VoidCallback onTap;
  const _CatButton({required this.cat, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final col = cat == null ? c.muted : categoryColor(cat);
    return Material(
      color: selected ? categoryTint(cat) : c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? col : c.divider, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: cat == null ? c.raised : categoryTint(cat), borderRadius: BorderRadius.circular(11)),
              child: Icon(cat == null ? Icons.more_horiz : categoryIcon(cat), size: 18, color: col),
            ),
            const SizedBox(height: 5),
            Text(cat?.display ?? tr('More'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.text)),
          ]),
        ),
      ),
    );
  }
}
