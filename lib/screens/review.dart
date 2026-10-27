import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../widgets.dart';
import 'settings.dart' show scanRange;

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
            title: const Text('Review'),
            actions: [
              if (app.scanning)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                IconButton(tooltip: 'Scan a date range', icon: const Icon(Icons.date_range), onPressed: () => scanRange(context)),
                IconButton(tooltip: 'Scan new SMS', icon: const Icon(Icons.refresh), onPressed: () => _scan(context)),
              ],
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => _scan(context),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
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
                        Text('$hidden more outside this range',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                    ]),
                  ),
                if (items.isEmpty) ...[
                  const SizedBox(height: 48),
                  Icon(Icons.task_alt, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(window != null ? 'Nothing waiting in this range' : 'All caught up',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      app.smsStartDate != null
                          ? 'Bank SMS from ${shortDate(app.smsStartDate!)} onwards show up here. Pull down to scan new messages.'
                          : 'New bank SMS show up here for you to confirm. Pull down to scan new messages, or tap the calendar to scan a date range.',
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
                          label: Text('Confirm $suggested suggested'),
                          onPressed: () async {
                            final n = await app.confirmAllSuggested(only: items);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Confirmed $n entries.')));
                            }
                          },
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.clear_all),
                        label: Text('Ignore all ${items.length}'),
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
      title: Text('Ignore ${items.length} message${items.length == 1 ? '' : 's'}?'),
      content: const Text('They leave the Review list and are not added to your entries. '
          'Use this when imported statements already cover these days.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ignore all')),
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
          const SnackBar(content: Text('Check the amount and pick a category first.')));
      return;
    }
    await app.confirmSms(widget.item,
        amount: amount, kind: kind, categoryId: categoryId!, merchant: merchantCtl.text,
        date: isoDate(date), remember: remember);
  }

  Future<void> _ignore() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Ignore this message'),
            subtitle: const Text('Not a real expense, e.g. a transfer between my own accounts'),
            onTap: () => Navigator.pop(c, 'one'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text('Always ignore ${widget.item.sender}'),
            subtitle: const Text('Stop importing messages from this sender'),
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
            child: Text(showRaw ? 'Hide SMS' : 'Show SMS',
                style: TextStyle(color: cs.primary, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
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
              ButtonSegment(value: 'expense', label: Text('Out')),
              ButtonSegment(value: 'income', label: Text('In')),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: merchantCtl,
          decoration: const InputDecoration(isDense: true, labelText: 'Merchant', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: categoryId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: categoryId != null && categoryId == widget.item.categoryId ? 'Category (suggested)' : 'Category',
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final c in cats)
              DropdownMenuItem(
                value: c.id,
                child: Row(children: [CategoryDot(c.color), const SizedBox(width: 8), Text(c.name)]),
              ),
          ],
          onChanged: (v) => setState(() => categoryId = v),
        ),
        Row(children: [
          Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true)),
          const Expanded(child: Text('Remember for this merchant', style: TextStyle(fontSize: 13.5))),
        ]),
        Row(children: [
          TextButton(onPressed: _ignore, child: const Text('Ignore')),
          const Spacer(),
          FilledButton.icon(onPressed: _confirm, icon: const Icon(Icons.check), label: const Text('Confirm')),
        ]),
      ]),
    );
  }
}
