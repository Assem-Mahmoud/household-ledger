import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';

import '../defaults.dart';
import '../models.dart';
import '../periods.dart';
import '../sms_parser.dart';
import '../state.dart';
import '../widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final h = int.tryParse(app.settings['reminderH'] ?? '21') ?? 21;
        final m = int.tryParse(app.settings['reminderM'] ?? '0') ?? 0;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            _header(context, 'Month'),
            ListTile(
              title: const Text('Period starts on day'),
              subtitle: Text(app.cycleStartDay == 1
                  ? 'Calendar months'
                  : 'Day ${app.cycleStartDay} to day ${app.cycleStartDay - 1} of the next month (salary to salary)'),
              trailing: DropdownButton<int>(
                value: app.cycleStartDay,
                items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                onChanged: (v) => app.setSetting('cycleDay', '${v ?? 1}'),
              ),
            ),
            ListTile(
              title: const Text('Currency label'),
              trailing: Text(app.currency, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              onTap: () => _editText(context, 'Currency label', 'currency'),
            ),

            _header(context, 'Alerts'),
            ListTile(
              title: const Text('Warn when a budget reaches'),
              subtitle: Slider(
                value: app.alertPct.toDouble(),
                min: 50,
                max: 95,
                divisions: 9,
                label: '${app.alertPct}%',
                onChanged: (v) => app.setSetting('alertPct', '${v.round()}'),
              ),
              trailing: Text('${app.alertPct}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            SwitchListTile(
              title: const Text('Daily reminder'),
              subtitle: Text('Log cash spending and confirm SMS at ${two(h)}:${two(m)}'),
              value: app.flag('reminderOn'),
              onChanged: (v) async {
                await app.setSetting('reminderOn', v ? '1' : '0');
                await app.applyReminder();
              },
            ),
            ListTile(
              enabled: app.flag('reminderOn'),
              title: const Text('Reminder time'),
              trailing: Text('${two(h)}:${two(m)}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
                if (t == null) return;
                await app.setSetting('reminderH', '${t.hour}');
                await app.setSetting('reminderM', '${t.minute}');
                await app.applyReminder();
              },
            ),

            _header(context, 'Bank SMS'),
            SwitchListTile(
              title: const Text('Import transactions from SMS'),
              subtitle: const Text('Reads bank messages on this phone. Nothing leaves the device.'),
              value: app.flag('smsOn'),
              onChanged: (v) async {
                await app.setSetting('smsOn', v ? '1' : '0');
                await app.applyReminder();
              },
            ),
            SwitchListTile(
              title: const Text('Notify when a bank SMS arrives'),
              value: app.flag('smsAlerts'),
              onChanged: app.flag('smsOn')
                  ? (v) async {
                      await app.setSetting('smsAlerts', v ? '1' : '0');
                      await app.applyReminder();
                    }
                  : null,
            ),
            ListTile(
              title: const Text('Scan again from a date'),
              subtitle: const Text('Re-reads older messages. Already reviewed ones are skipped.'),
              trailing: const Icon(Icons.history),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().subtract(const Duration(days: 30)),
                  firstDate: DateTime(2018),
                  lastDate: DateTime.now(),
                );
                if (d == null) return;
                final msg = await app.scanSms(from: d);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              },
            ),
            ListTile(
              title: const Text('Bank senders'),
              subtitle: Text(app.lines('senders').isEmpty
                  ? 'Automatic: any SMS that looks like a transaction'
                  : 'Only: ${app.lines('senders').join(', ')}'),
              onTap: () => _editText(context, 'Bank senders', 'senders',
                  help: 'One sender name per line exactly as it appears in Messages (e.g. AlRajhiBank). Leave empty for automatic detection.',
                  multiline: true),
            ),
            ListTile(
              title: const Text('Ignored senders'),
              subtitle: Text(app.lines('blockedSenders').isEmpty ? 'None' : app.lines('blockedSenders').join(', ')),
              onTap: () => _editText(context, 'Ignored senders', 'blockedSenders', multiline: true),
            ),
            ListTile(
              title: const Text('Ignore messages containing'),
              subtitle: Text('${app.lines('ignoreKw').length} keywords (OTP, declined, reminders…)'),
              onTap: () => _editText(context, 'Ignore keywords', 'ignoreKw', multiline: true,
                  help: 'One per line. Messages containing any of these are skipped.',
                  resetTo: defaultIgnoreKeywords.join('\n')),
            ),
            ListTile(
              title: const Text('Treat as income when containing'),
              subtitle: Text('${app.lines('incomeKw').length} keywords (salary, deposit, refund…)'),
              onTap: () => _editText(context, 'Income keywords', 'incomeKw', multiline: true,
                  help: 'One per line. Everything else is treated as an expense.',
                  resetTo: defaultIncomeKeywords.join('\n')),
            ),
            ListTile(
              title: const Text('Test the SMS reader'),
              subtitle: const Text('Paste a bank message to see what the app extracts'),
              trailing: const Icon(Icons.science_outlined),
              onTap: () => _testParser(context),
            ),

            _header(context, 'Categories'),
            ListTile(
              title: const Text('Manage categories'),
              subtitle: Text('${app.categories.where((c) => !c.archived).length} active'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
            ListTile(
              title: const Text('Auto-category rules'),
              subtitle: Text('${app.rules.length} merchant keywords'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())),
            ),

            _header(context, 'Data'),
            ListTile(
              title: const Text('Copy all entries as CSV'),
              subtitle: Text('${app.txns.length} entries · paste into Excel or Google Sheets'),
              trailing: const Icon(Icons.copy),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: app.exportCsv()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard.')));
                }
              },
            ),
            ListTile(
              title: const Text('Import entries from CSV'),
              subtitle: const Text('Paste rows with a header: date,type,category,amount,note'),
              trailing: const Icon(Icons.content_paste),
              onTap: () => _import(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text('All data is stored only on this phone. Export regularly to keep a backup.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );

  Future<void> _editText(BuildContext context, String title, String key,
      {String? help, bool multiline = false, String? resetTo}) async {
    final ctl = TextEditingController(text: app.settings[key] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: multiline ? 5 : 1,
            maxLines: multiline ? 12 : 1,
            decoration: InputDecoration(helperText: help, helperMaxLines: 3, border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          if (resetTo != null) TextButton(onPressed: () => ctl.text = resetTo, child: const Text('Defaults')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) await app.setSetting(key, result.trim());
  }

  Future<void> _testParser(BuildContext context) async {
    final ctl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setState) {
        final text = ctl.text;
        final parsed = text.trim().isEmpty ? null : parseSms(text, ignore: app.lines('ignoreKw'), income: app.lines('incomeKw'));
        final catId = parsed == null ? null : app.suggestCategory(parsed.merchant, text, parsed.kind);
        return AlertDialog(
          title: const Text('Test the SMS reader'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: ctl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(hintText: 'Paste a bank SMS here', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (text.trim().isNotEmpty)
                parsed == null
                    ? const Text('Not recognised as a transaction (no amount found, or it matched an ignore keyword).',
                        style: TextStyle(color: badColor))
                    : Text(
                        'Amount: ${parsed.amount} ${app.currency}\n'
                        'Type: ${parsed.kind}\n'
                        'Merchant: ${parsed.merchant.isEmpty ? '(not found)' : parsed.merchant}\n'
                        'Category: ${catId == null ? '(you pick)' : app.cat(catId)!.name}',
                      ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        );
      }),
    );
  }

  Future<void> _import(BuildContext context) async {
    final clip = await Clipboard.getData('text/plain');
    if (!context.mounted) return;
    final ctl = TextEditingController(text: clip?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import CSV'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctl,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'date,type,category,amount,note\n2026-10-01,expense,Groceries,250,Lulu',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await app.importCsv(ctl.text);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ------------------------------------------------------------ categories

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final groups = const [('need', 'Needs'), ('want', 'Wants'), ('save', 'Savings'), ('income', 'Income')];
        return Scaffold(
          appBar: AppBar(title: const Text('Categories')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('New category'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final g in groups) ...[
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Eyebrow(g.$2)),
              for (final c in app.categories.where((c) => c.grp == g.$1))
                ListTile(
                  leading: CategoryDot(c.color, size: 14),
                  title: Text(c.name,
                      style: c.archived ? TextStyle(color: Theme.of(context).disabledColor, decoration: TextDecoration.lineThrough) : null),
                  subtitle: c.archived ? const Text('Hidden') : null,
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _edit(context, c),
                ),
            ],
          ]),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Category? existing) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    var grp = existing?.grp ?? 'want';
    var color = existing?.color ?? palette[app.categories.length % palette.length];
    var archived = existing?.archived ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: nameCtl, autofocus: existing == null,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: grp,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'need', child: Text('Expense · need')),
                  DropdownMenuItem(value: 'want', child: Text('Expense · want')),
                  DropdownMenuItem(value: 'save', child: Text('Savings / investment')),
                  DropdownMenuItem(value: 'income', child: Text('Income')),
                ],
                onChanged: existing != null && existing.kind == 'income'
                    ? null
                    : (v) => setState(() => grp = v ?? 'want'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in palette)
                  GestureDetector(
                    onTap: () => setState(() => color = p),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(p),
                        shape: BoxShape.circle,
                        border: Border.all(width: 3, color: color == p ? Theme.of(c).colorScheme.onSurface : Colors.transparent),
                      ),
                    ),
                  ),
              ]),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hide this category'),
                  subtitle: const Text('Past entries keep it'),
                  value: archived,
                  onChanged: (v) => setState(() => archived = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtl.text.trim().isEmpty) return;
    if (existing == null) {
      final created = await app.addCategory(nameCtl.text, grp == 'income' ? 'income' : 'expense', grp);
      created.color = color;
      await app.updateCategory(created);
    } else {
      existing
        ..name = nameCtl.text.trim()
        ..grp = existing.kind == 'income' ? 'income' : grp
        ..kind = existing.kind
        ..color = color
        ..archived = archived;
      if (existing.kind == 'expense' && grp == 'income') existing.grp = 'want';
      await app.updateCategory(existing);
    }
  }
}

// ----------------------------------------------------------------- rules

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final rules = List<Rule>.from(app.rules)..sort((a, b) => a.keyword.compareTo(b.keyword));
        return Scaffold(
          appBar: AppBar(title: const Text('Auto-category rules')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Add rule'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'When a merchant name contains a keyword, its category is suggested automatically. '
                'Rules you create by confirming entries are marked "learned".',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
            for (final r in rules)
              ListTile(
                dense: true,
                leading: CategoryDot(app.cat(r.categoryId)?.color ?? 0xFF888888, size: 12),
                title: Text(r.keyword),
                subtitle: Text('${app.cat(r.categoryId)?.name ?? 'Deleted category'}${r.learned ? ' · learned' : ''}'),
                trailing: IconButton(
                  tooltip: 'Delete rule',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => app.deleteRule(r),
                ),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _add(BuildContext context) async {
    final ctl = TextEditingController();
    int? catId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('New rule'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, autofocus: true,
                decoration: const InputDecoration(labelText: 'Merchant contains', hintText: 'e.g. panda', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: catId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final cat in app.categories.where((x) => !x.archived))
                  DropdownMenuItem(value: cat.id, child: Text(cat.name)),
              ],
              onChanged: (v) => setState(() => catId = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && catId != null && ctl.text.trim().isNotEmpty) await app.addRule(ctl.text, catId!);
  }
}
