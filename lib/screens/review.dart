import 'package:flutter/material.dart' hide Category;

import '../accounts.dart' show cardDigitsIn;
import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../sms_parser.dart' show foreignCurrency;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'profile.dart' show accountIcon, editAccount;
import 'teach.dart';

/// Bank SMS waiting for confirmation, one at a time. Shown inside the Activity tab.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int? focusedId;

  Future<void> _scan() async {
    final msg = await app.scanSms();
    if (mounted && msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = lc;
        if (app.reviewAccount != null && app.reviewAccount != -1 && app.account(app.reviewAccount) == null) {
          app.reviewAccount = null; // the account was removed
        }
        final items = app.visiblePending;
        final window = app.reviewWindow;
        final filtered = app.reviewAccount != null;
        final hidden = filtered ? 0 : app.pending.length - items.length;
        final suggested = items.where((i) => i.categoryId != null).length;
        int count(int? id) => app.pending
            .where((p) => id == null || (id == -1 ? app.account(p.accountId) == null : p.accountId == id))
            .length;
        final focused = items.isEmpty ? null : items.firstWhere((i) => i.id == focusedId, orElse: () => items.first);
        final rest = items.where((i) => i.id != focused?.id).toList();

        return RefreshIndicator(
          onRefresh: _scan,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (app.lastAutoAdded > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Material(
                    color: c.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.auto_awesome, color: c.onPrimarySoft),
                      title: Text(tr('{n} from merchants you\'ve categorised were added automatically.', {'n': app.lastAutoAdded}),
                          style: TextStyle(color: c.onPrimarySoft, fontWeight: FontWeight.w600)),
                      trailing: IconButton(
                        tooltip: tr('Dismiss'),
                        icon: Icon(Icons.close, size: 18, color: c.onPrimarySoft),
                        onPressed: app.dismissAutoBanner,
                      ),
                      onTap: () => app.openActivity(1),
                    ),
                  ),
                ),
              if (window != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    InputChip(
                      avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                      label: Text('${shortDate(window.$1)} – ${shortDate(window.$2)}'),
                      onDeleted: app.clearReviewWindow,
                    ),
                    if (hidden > 0)
                      Text(tr('{n} more outside this range', {'n': hidden}), style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ]),
                ),
              if (app.activeAccounts.isNotEmpty && app.pending.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(children: [
                    for (final f in <(int?, String)>[
                      (null, tr('All')),
                      for (final a in app.activeAccounts) (a.id, a.name),
                      (-1, tr('No account')),
                    ])
                      if (f.$1 == null || count(f.$1) > 0)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: _FilterPill(
                            label: '${f.$2} · ${count(f.$1)}',
                            selected: app.reviewAccount == f.$1,
                            onTap: () => app.setReviewAccount(f.$1),
                          ),
                        ),
                  ]),
                ),
              if (focused == null) ...[
                const SizedBox(height: 56),
                Icon(Icons.task_alt, size: 60, color: c.primary),
                const SizedBox(height: 14),
                Text(tr(filtered ? 'Nothing waiting for this account' : window != null ? 'Nothing waiting in this range' : 'All caught up'),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    app.smsStartDate != null
                        ? tr('Bank SMS from {d} onwards show up here. Pull down to scan new messages.', {'d': shortDate(app.smsStartDate!)})
                        : tr('New bank SMS show up here for you to confirm. Pull down to scan new messages, or tap the calendar to scan a date range.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, height: 1.4),
                  ),
                ),
              ] else ...[
                ReviewCard(key: ValueKey(focused.id), item: focused),
                if (rest.isNotEmpty || suggested > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
                    child: Row(children: [
                      Expanded(child: Text(tr('Up next'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
                      if (suggested > 1)
                        TextButton(
                          style: TextButton.styleFrom(backgroundColor: c.primarySoft, foregroundColor: c.onPrimarySoft),
                          onPressed: () async {
                            final n = await app.confirmAllSuggested(only: items);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Confirmed {n} entries.', {'n': n}))));
                            }
                          },
                          child: Text(tr('Confirm {n} suggested', {'n': suggested})),
                        ),
                      PopupMenuButton<String>(
                        tooltip: tr('More'),
                        onSelected: (v) {
                          if (v == 'ignore') _ignoreAll(context, items);
                        },
                        itemBuilder: (_) => [PopupMenuItem(value: 'ignore', child: Text(tr('Ignore all {n}', {'n': items.length})))],
                      ),
                    ]),
                  ),
                if (rest.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20)),
                    child: Column(children: [
                      for (final it in rest)
                        InkWell(
                          onTap: () => setState(() => focusedId = it.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              CategoryTile(it.categoryId == null ? null : app.cat(it.categoryId!), size: 38),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(it.merchant.isEmpty ? it.sender : it.merchant,
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  Text(
                                    it.categoryId != null && app.cat(it.categoryId!) != null
                                        ? '${app.cat(it.categoryId!)!.display} · ${tr('suggested')}'
                                        : tr('Pick a category'),
                                    style: TextStyle(fontSize: 12, color: c.muted),
                                  ),
                                ]),
                              ),
                              Text(ltr('${it.kind == 'income' ? '+' : '−'}${fmtAuto(it.amount)}'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = lc;
    return Material(
      color: selected ? c.text : c.card,
      shape: StadiumBorder(side: BorderSide(color: selected ? c.text : c.outline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? c.bg : c.text)),
        ),
      ),
    );
  }
}

Future<void> _ignoreAll(BuildContext context, List<SmsItem> items) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(trn(items.length, 'Ignore {n} message?', 'Ignore {n} messages?')),
      content: const T('They leave the Review list and are not added to your entries. '
          'Use this when imported statements already cover these days.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Ignore all')),
      ],
    ),
  );
  if (ok == true) await app.ignoreMany(items);
}

/// Categories of [kind] the user picks most often, then the rest.
List<Category> frequentCategories(String kind) {
  final counts = <int, int>{};
  for (final t in app.txns) {
    if (t.kind == kind) counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
  }
  final list = app.active(kind).toList()..sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
  return list;
}

/// Grid of all categories of [kind]; returns the chosen id.
Future<int?> pickCategory(BuildContext context, String kind, {int? selected}) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: GridView.count(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.9,
            children: [
              for (final cat in app.active(kind))
                Material(
                  color: cat.id == selected ? lc.primarySoft : lc.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cat.id == selected ? lc.primary : lc.divider, width: cat.id == selected ? 2 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(c, cat.id),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CategoryTile(cat, size: 36),
                        const SizedBox(height: 6),
                        Text(cat.display,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

class ReviewCard extends StatefulWidget {
  final SmsItem item;
  const ReviewCard({super.key, required this.item});
  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  late double amount;
  late String merchant;
  late String kind;
  int? categoryId;
  int? accountId;
  bool remember = true;
  bool showRaw = false;
  late DateTime date;
  final noteCtl = TextEditingController();

  @override
  void dispose() {
    noteCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    amount = it.amount;
    merchant = it.merchant;
    kind = it.kind;
    categoryId = it.categoryId;
    accountId = it.accountId;
    date = DateTime.fromMillisecondsSinceEpoch(it.receivedAt);
  }

  Future<void> _confirm() async {
    if (amount <= 0 || categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Check the amount and pick a category first.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final others = await app.confirmSms(widget.item,
        amount: amount, kind: kind, categoryId: categoryId!, merchant: merchant,
        date: isoDate(date), remember: remember, accountId: accountId, note: noteCtl.text);
    if (others > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('{n} more from {m} were added to {cat} automatically.',
              {'n': others, 'm': merchant, 'cat': app.cat(categoryId!)?.display ?? ''}))));
    }
  }

  Future<void> _editText(String title, String value, bool number, ValueChanged<String> onSave) async {
    final ctl = TextEditingController(text: value);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(title)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(suffixText: number ? app.currency : null),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const T('Save')),
        ],
      ),
    );
    if (v != null) setState(() => onSave(v));
  }

  Future<void> _menu(String choice) async {
    switch (choice) {
      case 'sms':
        setState(() => showRaw = !showRaw);
      case 'teach':
        Navigator.push(context, MaterialPageRoute(builder: (_) => TeachSmsScreen(body: widget.item.body, sender: widget.item.sender)));
      case 'block':
        await app.ignoreSms(widget.item, blockSender: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final cats = frequentCategories(kind);
    if (categoryId != null && !cats.any((x) => x.id == categoryId)) categoryId = null;
    // the chosen or suggested category first, then the most used ones
    final chips = <Category>[
      if (categoryId != null) app.cat(categoryId!)!,
      ...cats.where((x) => x.id != categoryId).take(categoryId != null ? 3 : 4),
    ];
    final acc = app.account(accountId);
    final digits = cardDigitsIn(widget.item.body);
    final hint = app.looksLikeOwnTransfer(widget.item.body)
        ? tr('Looks like a card payment or a transfer between your own accounts. These aren\'t spending — tap Not spending.')
        : switch (foreignCurrency(widget.item.body, currency: app.currencyCode)) {
            final fx? => tr('This amount is in {c}. Edit it to the amount charged in your own currency before confirming.', {'c': fx}),
            _ => null,
          };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.dark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${widget.item.sender} · ${shortDate(date)}, ${two(date.hour)}:${two(date.minute)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          PopupMenuButton<String>(
            tooltip: tr('More'),
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'sms', child: Text(tr(showRaw ? 'Hide SMS' : 'Show SMS'))),
              PopupMenuItem(value: 'teach', child: Text(tr('Read wrongly? Teach the app'))),
              PopupMenuItem(value: 'block', child: Text(tr('Always ignore {s}', {'s': widget.item.sender}))),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showRaw)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(12)),
                child: SelectableText(widget.item.body, style: const TextStyle(fontSize: 12.5)),
              ),
            if (hint != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: c.attnBg, borderRadius: BorderRadius.circular(12)),
                child: Text(hint, style: TextStyle(fontSize: 12.5, color: c.attnText, height: 1.35)),
              ),
            // amount and merchant, tap to edit
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editText('Amount', fmtAuto(amount).replaceAll(',', ''), true, (v) => amount = parseAmount(v) ?? amount),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(fmtAuto(amount), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
                  const SizedBox(width: 6),
                  Text(app.currency, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.muted)),
                ]),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editText('Merchant', merchant, false, (v) => merchant = v.trim()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Flexible(
                    child: Text(merchant.isEmpty ? tr('Add merchant') : merchant,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: merchant.isEmpty ? c.primary : c.text)),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, size: 15, color: c.muted),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            WhatForField(controller: noteCtl),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
              for (final k in const [('expense', 'Expense'), ('income', 'Income')])
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  label: Text(tr(k.$2)),
                  selected: kind == k.$1,
                  onSelected: (_) => setState(() {
                    kind = k.$1;
                    categoryId = null;
                  }),
                ),
              if (acc != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(accountIcon(acc.type), size: 16),
                  label: Text(acc.name),
                )
              else if (digits.isNotEmpty)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add_card, size: 16),
                  label: Text(tr('Name card {d}', {'d': digits.first})),
                  onPressed: () async {
                    await editAccount(context, null, digits: digits.first);
                    final id = app.accountFor(widget.item.body);
                    if (mounted && id != null) setState(() => accountId = id);
                  },
                ),
            ]),
            const SizedBox(height: 14),
            Text(tr('Category'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final cat in chips)
                _CategoryChip(cat: cat, selected: cat.id == categoryId, onTap: () => setState(() => categoryId = cat.id)),
              ActionChip(
                label: Text(tr('More…')),
                onPressed: () async {
                  final id = await pickCategory(context, kind, selected: categoryId);
                  if (id != null) setState(() => categoryId = id);
                },
              ),
            ]),
            if (app.activeAccounts.length > 1) ...[
              const SizedBox(height: 12),
              Text(tr('Paid from'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in app.activeAccounts)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    avatar: Icon(accountIcon(a.type), size: 16),
                    label: Text(a.name),
                    selected: accountId == a.id,
                    onSelected: (v) => setState(() => accountId = v ? a.id : null),
                  ),
              ]),
            ],
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => remember = !remember),
              child: Row(children: [
                Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true)),
                Expanded(
                  child: Text(
                    merchant.isNotEmpty && categoryId != null
                        ? tr('Always put {m} in {cat}', {'m': merchant, 'cat': app.cat(categoryId!)?.display ?? ''})
                        : tr('Remember for this merchant'),
                    style: TextStyle(fontSize: 13.5, color: c.text),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: () => app.ignoreSms(widget.item),
                  child: const T('Not spending'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _confirm,
                  child: const T('Confirm'),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final Category cat;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.cat, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = lc;
    final col = categoryColor(cat);
    return Material(
      color: selected ? categoryTint(cat) : c.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? col : c.outline, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(categoryIcon(cat), size: 17, color: col),
            const SizedBox(width: 6),
            Text(cat.display, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: c.text)),
          ]),
        ),
      ),
    );
  }
}
