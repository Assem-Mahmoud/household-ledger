import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';

import '../defaults.dart';
import '../models.dart';
import '../native.dart';
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
                if (v && context.mounted) await rescanAfterChange(context);
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
              title: const Text('SMS start date'),
              subtitle: Text(app.smsStartDate == null
                  ? 'Off · every message can be read'
                  : 'Only messages from ${shortDate(app.smsStartDate!)} ${app.smsStartDate!.year} on. Earlier days come from imported statements.'),
              trailing: const Icon(Icons.start),
              onTap: () => _smsStart(context),
            ),
            ListTile(
              title: const Text('Scan a date range'),
              subtitle: const Text('Read messages between two dates. Already reviewed ones are skipped.'),
              trailing: const Icon(Icons.date_range),
              onTap: () => scanRange(context),
            ),
            ListTile(
              title: const Text('Bank senders'),
              subtitle: Text(app.lines('senders').isEmpty
                  ? 'Automatic: any SMS that looks like a transaction'
                  : 'Only: ${app.lines('senders').join(', ')}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendersScreen())),
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

            _header(context, 'Backup to Gmail'),
            ListTile(
              title: const Text('Backup email'),
              subtitle: Text((app.settings['backupEmail'] ?? '').isEmpty
                  ? 'Not set — Gmail opens with an empty "To"'
                  : app.settings['backupEmail']!),
              trailing: const Icon(Icons.alternate_email),
              onTap: () => _editText(context, 'Backup email', 'backupEmail',
                  help: 'Backups are emailed here, usually your own Gmail address.'),
            ),
            ListTile(
              title: const Text('Email a backup now'),
              subtitle: Text(app.daysSinceBackup == null
                  ? 'Never backed up'
                  : app.daysSinceBackup == 0
                      ? 'Last backup: today'
                      : 'Last backup: ${app.daysSinceBackup} day${app.daysSinceBackup == 1 ? '' : 's'} ago'),
              trailing: Icon(Icons.backup_outlined, color: app.backupDue ? warnColor : null),
              onTap: () => emailBackupFlow(context),
            ),
            ListTile(
              title: const Text('Restore from backup'),
              subtitle: const Text('Pick a backup file saved from Gmail, Downloads or Drive'),
              trailing: const Icon(Icons.settings_backup_restore),
              onTap: () => _restore(context),
            ),

            _header(context, 'Data'),
            ListTile(
              title: const Text('Import entries from a CSV file'),
              subtitle: const Text('Statements or the web ledger export. Entries already in the app are skipped.'),
              trailing: const Icon(Icons.upload_file),
              onTap: () => _importFile(context),
            ),
            ListTile(
              title: const Text('Email entries as CSV'),
              subtitle: Text('${app.txns.length} entries · opens in Excel or Google Sheets'),
              trailing: const Icon(Icons.table_view_outlined),
              onTap: () async {
                try {
                  await Native.emailFile(
                    content: app.exportCsv(),
                    fileName: 'household-ledger-${isoDate(DateTime.now())}.csv',
                    to: app.settings['backupEmail'] ?? '',
                    subject: 'Household Ledger entries ${isoDate(DateTime.now())}',
                    body: 'All entries as CSV.',
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open email: $e')));
                  }
                }
              },
            ),
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
              title: const Text('Paste CSV rows'),
              subtitle: const Text('Header: date,type,category,amount,note'),
              trailing: const Icon(Icons.content_paste),
              onTap: () => _import(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                  'Data is stored only on this phone. Uninstalling the app deletes it, so keep a recent backup in Gmail.',
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
    if (result == null) return;
    await app.setSetting(key, result.trim());
    if (smsKeys.contains(key) && context.mounted) await rescanAfterChange(context);
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

  Future<void> _smsStart(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Start fresh with SMS', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Messages before the start date are ignored and cleared from Review. '
                'Use it when statements (CSV) already cover the past, so nothing is counted twice.'),
          ),
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Start from today'),
            onTap: () => Navigator.pop(c, 'today'),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Pick a start date'),
            subtitle: const Text('e.g. the day after your last imported statement'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
          if (app.smsStartDate != null)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Turn off the start date'),
              onTap: () => Navigator.pop(c, 'off'),
            ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    DateTime? date;
    if (choice == 'today') date = DateTime.now();
    if (choice == 'pick') {
      date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2018),
        lastDate: DateTime.now(),
        helpText: 'Read SMS from this day on',
      );
      if (date == null) return;
    }
    final cleared = await app.setSmsStartDate(date);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(date == null
          ? 'Start date turned off.'
          : 'SMS are read from ${shortDate(date)} on.${cleared > 0 ? ' $cleared older messages cleared from Review.' : ''}'),
    ));
  }

  Future<void> _restore(BuildContext context) async {
    String? text;
    try {
      text = await Native.pickFileText();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the file: $e')));
      return;
    }
    if (text == null || !context.mounted) return;
    final summary = app.describeBackup(text);
    if (summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That file is not a Household Ledger backup (.json from "Email a backup").')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('$summary\n\nEverything currently in the app (${app.txns.length} entries, budgets, rules and '
            'settings) will be replaced. Email a backup first if you might need the current data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Replace and restore')),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await app.restoreBackup(text);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _importFile(BuildContext context) async {
    String? text;
    try {
      text = await Native.pickFileText();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the file: $e')));
      return;
    }
    if (text == null || !context.mounted) return;
    if (app.describeBackup(text) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That is a full backup. Use "Restore from backup" instead.')));
      return;
    }
    final msg = await app.importCsv(text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6)));
    }
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

const smsKeys = {'senders', 'blockedSenders', 'ignoreKw', 'incomeKw'};

/// Re-checks waiting items and rescans the current period, then reports the result.
Future<void> rescanAfterChange(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Settings saved. Rescanning this period…'), duration: Duration(seconds: 1)));
  final msg = await app.applySmsSettings();
  if (msg.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(msg)));
}

/// Pick a from–to window and scan it.
Future<void> scanRange(BuildContext context) async {
  final now = DateTime.now();
  final per = app.period;
  final first = app.smsStartDate ?? DateTime(2018);
  if (first.isAfter(now)) return;
  DateTime clamp(DateTime d) => d.isBefore(first) ? first : (d.isAfter(now) ? now : d);
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(first.year, first.month, first.day),
    lastDate: now,
    initialDateRange: DateTimeRange(start: clamp(per.start), end: clamp(per.end)),
    helpText: 'Scan SMS from – to',
    saveText: 'Scan',
  );
  if (range == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final msg = await app.scanSms(from: range.start, to: range.end, filterReview: true);
  if (msg.isNotEmpty) messenger.showSnackBar(SnackBar(content: Text(msg)));
}

// --------------------------------------------------------------- senders

/// Choose which SMS senders are banks, from the senders found in the phone's messages.
class SendersScreen extends StatefulWidget {
  const SendersScreen({super.key});
  @override
  State<SendersScreen> createState() => _SendersScreenState();
}

class _SendersScreenState extends State<SendersScreen> {
  List<(String, int)>? found;
  late Set<String> selected;
  final manualCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    selected = app.lines('senders').toSet();
    app.detectSenders().then((v) {
      if (mounted) setState(() => found = v);
    });
  }

  @override
  void dispose() {
    manualCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await app.setSetting('senders', selected.join('\n'));
    if (!mounted) return;
    final nav = Navigator.of(context);
    await rescanAfterChange(context);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final known = found?.map((e) => e.$1.toLowerCase()).toSet() ?? <String>{};
    final extra = selected.where((s) => !known.contains(s)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank senders'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            selected.isEmpty
                ? 'No senders selected: any message that looks like a transaction is read. Tick your banks to read only their messages.'
                : 'Only messages from the ticked senders are read.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (found == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (found!.isEmpty)
          const ListTile(title: Text('No transaction messages found in the last 4 months.'))
        else
          for (final f in found!)
            CheckboxListTile(
              value: selected.contains(f.$1.toLowerCase()),
              title: Text(f.$1),
              subtitle: Text('${f.$2} transaction message${f.$2 == 1 ? '' : 's'} in the last 4 months'),
              onChanged: (v) => setState(() {
                if (v == true) {
                  selected.add(f.$1.toLowerCase());
                } else {
                  selected.remove(f.$1.toLowerCase());
                }
              }),
            ),
        for (final e in extra)
          CheckboxListTile(
            value: true,
            title: Text(e),
            subtitle: const Text('Added manually'),
            onChanged: (_) => setState(() => selected.remove(e)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: manualCtl,
                decoration: const InputDecoration(isDense: true, labelText: 'Add a sender name', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                final t = manualCtl.text.trim().toLowerCase();
                if (t.isEmpty) return;
                setState(() {
                  selected.add(t);
                  manualCtl.clear();
                });
              },
              child: const Text('Add'),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Asks for the backup address the first time, then opens Gmail with the backup attached.
Future<void> emailBackupFlow(BuildContext context) async {
  if ((app.settings['backupEmail'] ?? '').isEmpty) {
    final ctl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Where should backups go?'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Your Gmail address',
            helperText: 'Saved for next time. You can change it in Settings.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
    if (email == null) return;
    if (email.isNotEmpty) await app.setSetting('backupEmail', email);
  }
  try {
    final how = await app.emailBackup();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(how == 'gmail'
            ? 'Gmail opened with the backup attached. Tap Send to finish.'
            : 'Choose your mail app, then tap Send to finish.'),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open email: $e')));
    }
  }
}
