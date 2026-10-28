import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../sms_parser.dart' show foreignCurrency;
import '../state.dart';
import '../widgets.dart';
import 'settings.dart' show scanRange;
import 'teach.dart';

/// Bank SMS waiting for confirmation: check amount, pick category, confirm or ignore.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  Future<void> _scan(BuildContext context) async {
    final msg = await app.scanSms();
    if (context.mounted && msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final items = app.visiblePending;
        final window = app.reviewWindow;
        final hidden = app.pending.length - items.length;
        final suggested = items.where((i) => i.categoryId != null).length;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const T('Review'),
            actions: [
              if (app.scanning)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                IconButton(tooltip: tr('Scan a date range'), icon: const Icon(Icons.date_range), onPressed: () => scanRange(context)),
                IconButton(tooltip: tr('Scan new SMS'), icon: const Icon(Icons.refresh), onPressed: () => _scan(context)),
              ],
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => _scan(context),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (app.lastAutoAdded > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Material(
                      color: goodColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.auto_awesome, color: goodColor),
                        title: Text(tr('{n} from merchants you\'ve categorised were added automatically.', {'n': app.lastAutoAdded})),
                        trailing: IconButton(
                          tooltip: tr('Dismiss'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: app.dismissAutoBanner,
                        ),
                        onTap: () => app.tab.value = 2,
                      ),
                    ),
                  ),
                if (window != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      InputChip(
                        avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                        label: Text('${shortDate(window.$1)} – ${shortDate(window.$2)}'),
                        onDeleted: app.clearReviewWindow,
                      ),
                      if (hidden > 0)
                        Text(tr('{n} more outside this range', {'n': hidden}),
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    ]),
                  ),
                if (items.isEmpty) ...[
                  const SizedBox(height: 48),
                  Icon(Icons.task_alt, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(tr(window != null ? 'Nothing waiting in this range' : 'All caught up'),
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      app.smsStartDate != null
                          ? tr('Bank SMS from {d} onwards show up here. Pull down to scan new messages.',
                              {'d': shortDate(app.smsStartDate!)})
                          : tr('New bank SMS show up here for you to confirm. Pull down to scan new messages, or tap the calendar to scan a date range.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      if (suggested > 1)
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.done_all),
                          label: Text(tr('Confirm {n} suggested', {'n': suggested})),
                          onPressed: () async {
                            final n = await app.confirmAllSuggested(only: items);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Confirmed {n} entries.', {'n': n}))));
                            }
                          },
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.clear_all),
                        label: Text(tr('Ignore all {n}', {'n': items.length})),
                        onPressed: () => _ignoreAll(context, items),
                      ),
                    ]),
                  ),
                  for (final it in items) ReviewCard(key: ValueKey(it.id), item: it),
                ],
              ],
            ),
          ),
        );
      },
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

class ReviewCard extends StatefulWidget {
  final SmsItem item;
  const ReviewCard({super.key, required this.item});
  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<ReviewCard> {
  late final TextEditingController amountCtl;
  late final TextEditingController merchantCtl;
  late String kind;
  int? categoryId;
  bool remember = true;
  bool showRaw = false;
  late DateTime date;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    amountCtl = TextEditingController(text: fmtAuto(it.amount).replaceAll(',', ''));
    merchantCtl = TextEditingController(text: it.merchant);
    kind = it.kind;
    categoryId = it.categoryId;
    date = DateTime.fromMillisecondsSinceEpoch(it.receivedAt);
  }

  @override
  void dispose() {
    amountCtl.dispose();
    merchantCtl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = parseAmount(amountCtl.text);
    if (amount == null || amount <= 0 || categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('Check the amount and pick a category first.')));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final merchant = merchantCtl.text.trim();
    final others = await app.confirmSms(widget.item,
        amount: amount, kind: kind, categoryId: categoryId!, merchant: merchantCtl.text,
        date: isoDate(date), remember: remember);
    if (others > 0) {
      messenger.showSnackBar(SnackBar(
          content: Text(tr('{n} more from {m} were added to {cat} automatically.',
              {'n': others, 'm': merchant, 'cat': app.cat(categoryId!)?.display ?? ''}))));
    }
  }

  Future<void> _ignore() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const T('Ignore this message'),
            subtitle: const T('Not a real expense, e.g. a transfer between my own accounts'),
            onTap: () => Navigator.pop(c, 'one'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(tr('Always ignore {s}', {'s': widget.item.sender})),
            subtitle: const T('Stop importing messages from this sender'),
            onTap: () => Navigator.pop(c, 'sender'),
          ),
        ]),
      ),
    );
    if (choice != null) await app.ignoreSms(widget.item, blockSender: choice == 'sender');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cats = app.active(kind);
    if (categoryId != null && !cats.any((c) => c.id == categoryId)) categoryId = null;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${widget.item.sender} · ${shortDate(date)}, ${two(date.hour)}:${two(date.minute)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ),
          GestureDetector(
            onTap: () => setState(() => showRaw = !showRaw),
            child: Text(tr(showRaw ? 'Hide SMS' : 'Show SMS'),
                style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (showRaw)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TeachSmsScreen(body: widget.item.body, sender: widget.item.sender))),
              icon: const Icon(Icons.school_outlined, size: 18),
              label: const T('Read wrongly? Teach the app'),
            ),
          ),
        if (app.looksLikeOwnTransfer(widget.item.body)) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: warnColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.swap_horiz, size: 18, color: warnColor),
              const SizedBox(width: 8),
              const Expanded(
                child: T('Looks like a card payment or a transfer between your own accounts. These aren\'t spending — tap Ignore.',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
        ],
        if (foreignCurrency(widget.item.body, currency: app.currencyCode) case final fx?) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: warnColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.currency_exchange, size: 18, color: warnColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('This amount is in {c}. Edit it to the amount charged in your own currency before confirming.', {'c': fx}),
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
        ],
        if (showRaw) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: SelectableText(widget.item.body, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular),
              decoration: InputDecoration(isDense: true, suffixText: app.currency, border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 10),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 'expense', label: T('Out')),
              ButtonSegment(value: 'income', label: T('In')),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: merchantCtl,
          decoration: InputDecoration(isDense: true, labelText: tr('Merchant'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: categoryId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: tr(categoryId != null && categoryId == widget.item.categoryId ? 'Category (suggested)' : 'Category'),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final c in cats)
              DropdownMenuItem(
                value: c.id,
                child: Row(children: [CategoryDot(c.color), const SizedBox(width: 8), Text(c.display)]),
              ),
          ],
          onChanged: (v) => setState(() => categoryId = v),
        ),
        Row(children: [
          Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true)),
          const Expanded(child: T('Remember for this merchant', style: TextStyle(fontSize: 13.5))),
        ]),
        Row(children: [
          TextButton(onPressed: _ignore, child: const T('Ignore')),
          const Spacer(),
          FilledButton.icon(onPressed: _confirm, icon: const Icon(Icons.check), label: const T('Confirm')),
        ]),
      ]),
    );
  }
}
