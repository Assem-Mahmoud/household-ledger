import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';

import '../format.dart';
import '../i18n.dart';
import '../sms_parser.dart';
import '../sms_template.dart';
import '../state.dart';
import '../widgets.dart';

/// Paste a bank SMS, see what the app reads, and teach it the format by marking the amount and merchant.
class TeachSmsScreen extends StatefulWidget {
  final String body;
  final String sender;
  const TeachSmsScreen({super.key, this.body = '', this.sender = ''});

  @override
  State<TeachSmsScreen> createState() => _TeachSmsScreenState();
}

class _TeachSmsScreenState extends State<TeachSmsScreen> {
  late final TextEditingController msgCtl = TextEditingController(text: widget.body);
  late final TextEditingController senderCtl = TextEditingController(text: widget.sender);
  (int, int)? amount, merchant;
  TextSelection? lastSelection;
  String kind = 'expense';
  bool saving = false;

  String get text => normalizeDigits(msgCtl.text).trim();

  @override
  void dispose() {
    msgCtl.dispose();
    senderCtl.dispose();
    super.dispose();
  }

  void _resetMarks() => setState(() {
        amount = null;
        merchant = null;
        lastSelection = null;
      });

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text == null) return;
    msgCtl.text = d!.text!;
    _resetMarks();
  }

  void _mark(String what, TextSelection? sel) {
    if (sel == null || sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('Select part of the message first: long-press a word, then drag the handles.')));
      return;
    }
    final r = (sel.start < sel.end ? sel.start : sel.end, sel.start < sel.end ? sel.end : sel.start);
    setState(() {
      if (what == 'amount') {
        amount = r;
        if (merchant != null && merchant!.$1 < r.$2 && r.$1 < merchant!.$2) merchant = null;
      } else {
        merchant = r;
        if (amount != null && amount!.$1 < r.$2 && r.$1 < amount!.$2) amount = null;
      }
      lastSelection = null;
    });
  }

  (SmsTemplate?, String?) _build() {
    if (amount == null) return (null, null);
    try {
      return (
        SmsTemplate.build(text: text, amount: amount!, merchant: merchant, kind: kind, sender: senderCtl.text),
        null
      );
    } on FormatException catch (e) {
      return (null, e.message);
    }
  }

  Future<void> _save(SmsTemplate t) async {
    setState(() => saving = true);
    final msg = await app.addTemplate(t);
    if (!mounted) return;
    setState(() => saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr('Format saved. Messages like this will be read the way you marked them.')} $msg')));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = text;
    final (ParsedSms?, bool) read = t.isEmpty ? (null, false) : app.readMessage(t, sender: senderCtl.text);
    final current = read.$1, taught = read.$2;
    final (template, error) = _build();
    final preview = template?.apply(t, currency: app.currencyCode);

    return Scaffold(
      appBar: AppBar(title: const T('Test or teach the SMS reader')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        TextField(
          controller: msgCtl,
          minLines: 4,
          maxLines: 10,
          onChanged: (_) => _resetMarks(),
          decoration: InputDecoration(
            labelText: tr('Bank message'),
            hintText: tr('Paste a bank SMS here'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(tooltip: tr('Paste'), icon: const Icon(Icons.content_paste), onPressed: _paste),
          ),
        ),
        if (t.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Eyebrow('What the app reads now'),
          const SizedBox(height: 6),
          _ResultCard(parsed: current, note: taught ? tr('Using a format you taught') : null),
          const SizedBox(height: 24),
          const Eyebrow('Not right? Teach it'),
          const SizedBox(height: 6),
          T('Long-press the amount in the message below, adjust the selection, then tap Amount. Do the same for the merchant (optional).',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectableText.rich(
              _spans(t, cs),
              style: const TextStyle(fontSize: 15.5, height: 1.5),
              onSelectionChanged: (sel, _) {
                if (!sel.isCollapsed) lastSelection = sel;
              },
              contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  ContextMenuButtonItem(
                    label: tr('Amount'),
                    onPressed: () {
                      _mark('amount', state.textEditingValue.selection);
                      state.hideToolbar();
                    },
                  ),
                  ContextMenuButtonItem(
                    label: tr('Merchant'),
                    onPressed: () {
                      _mark('merchant', state.textEditingValue.selection);
                      state.hideToolbar();
                    },
                  ),
                  ...state.contextMenuButtonItems,
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => _mark('amount', lastSelection),
              icon: const Icon(Icons.payments_outlined),
              label: const T('Amount'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _mark('merchant', lastSelection),
              icon: const Icon(Icons.storefront_outlined),
              label: const T('Merchant'),
            ),
            if (amount != null || merchant != null)
              TextButton(onPressed: _resetMarks, child: const T('Clear marks')),
          ]),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'expense', label: T('Expense'), icon: const Icon(Icons.arrow_upward)),
              ButtonSegment(value: 'income', label: T('Income'), icon: const Icon(Icons.arrow_downward)),
            ],
            selected: {kind},
            onSelectionChanged: (s) => setState(() => kind = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: senderCtl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('Sender (optional)'),
              helperText: tr('Use this format only for messages from this sender, e.g. CIB or NBE.'),
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (amount == null)
            T('Mark the amount to continue.', style: TextStyle(color: cs.onSurfaceVariant))
          else if (error != null)
            Text(tr(error), style: const TextStyle(color: badColor))
          else ...[
            const Eyebrow('With your marks'),
            const SizedBox(height: 6),
            _ResultCard(parsed: preview),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: saving || template == null ? null : () => _save(template),
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.school_outlined),
              label: const T('Save this format'),
            ),
          ],
        ],
        const SizedBox(height: 28),
        _SavedFormats(onChanged: () => setState(() {})),
      ]),
    );
  }

  TextSpan _spans(String t, ColorScheme cs) {
    final marks = <(int, int, Color)>[
      if (amount != null) (amount!.$1, amount!.$2, goodColor.withOpacity(0.28)),
      if (merchant != null) (merchant!.$1, merchant!.$2, cs.primary.withOpacity(0.22)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <TextSpan>[];
    var i = 0;
    for (final m in marks) {
      if (m.$1 < i || m.$2 > t.length) continue;
      if (m.$1 > i) spans.add(TextSpan(text: t.substring(i, m.$1)));
      spans.add(TextSpan(
          text: t.substring(m.$1, m.$2), style: TextStyle(backgroundColor: m.$3, fontWeight: FontWeight.w700)));
      i = m.$2;
    }
    if (i < t.length) spans.add(TextSpan(text: t.substring(i)));
    return TextSpan(children: spans);
  }
}

class _ResultCard extends StatelessWidget {
  final ParsedSms? parsed;
  final String? note;
  const _ResultCard({required this.parsed, this.note});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = parsed;
    if (p == null) {
      return const T('Not recognised as a transaction (no amount found, or it matched an ignore keyword).',
          style: TextStyle(color: badColor));
    }
    final catId = app.suggestCategory(p.merchant, '', p.kind);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 92, child: Text(tr(label), style: TextStyle(color: cs.onSurfaceVariant))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('Amount', '${fmtAuto(p.amount)} ${app.currency}'),
        row('Type', tr(p.kind == 'income' ? 'Income' : 'Expense')),
        row('Merchant', p.merchant.isEmpty ? tr('(not found)') : p.merchant),
        row('Category', catId == null ? tr('(you pick)') : app.cat(catId)?.display ?? ''),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, style: TextStyle(fontSize: 12, color: cs.primary)),
        ],
      ]),
    );
  }
}

class _SavedFormats extends StatelessWidget {
  final VoidCallback onChanged;
  const _SavedFormats({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final list = app.templates;
    if (list.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Eyebrow(tr('Formats you taught ({n})', {'n': list.length})),
      const SizedBox(height: 6),
      for (final t in list)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(t.sample.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              tr(t.kind == 'income' ? 'Income' : 'Expense'),
              if (t.sender.isNotEmpty) tr('from {s}', {'s': t.sender}),
            ].join(' · ')),
            trailing: IconButton(
              tooltip: tr('Delete'),
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: () async {
                await app.deleteTemplate(t);
                onChanged();
              },
            ),
          ),
        ),
    ]);
  }
}
