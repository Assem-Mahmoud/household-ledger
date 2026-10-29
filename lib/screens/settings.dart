import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';

import '../defaults.dart';
import '../i18n.dart';
import '../models.dart';
import '../native.dart';
import '../periods.dart';
import '../sms_parser.dart';
import '../state.dart';
import '../widgets.dart';
import 'teach.dart';
import 'profile.dart';

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
          appBar: AppBar(title: const T('Settings')),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            _header(context, 'General'),
            ListTile(
              leading: const Icon(Icons.translate),
              title: const T('App language'),
              trailing: DropdownButton<String>(
                value: app.language.value,
                items: [
                  DropdownMenuItem(value: 'system', child: T('Phone language')),
                  const DropdownMenuItem(value: 'en', child: Text('English')),
                  const DropdownMenuItem(value: 'ar', child: Text('العربية')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  app.setLanguagePref(v);
                },
              ),
            ),

            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const T('Profile, currency & accounts'),
              subtitle: Text(tr('{c} · month starts on day {d} · {n} accounts',
                  {'c': app.currencyCode, 'd': app.cycleStartDay, 'n': app.accounts.length})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),

            _header(context, 'Bank SMS'),
            SwitchListTile(
              title: const T('Import transactions from SMS'),
              subtitle: const T('Reads bank messages on this phone. Nothing leaves the device.'),
              value: app.flag('smsOn'),
              onChanged: (v) async {
                await app.setSetting('smsOn', v ? '1' : '0');
                await app.applyReminder();
                if (v && context.mounted) await rescanAfterChange(context);
              },
            ),
            SwitchListTile(
              title: const T('Notify when a bank SMS arrives'),
              value: app.flag('smsAlerts'),
              onChanged: app.flag('smsOn')
                  ? (v) async {
                      await app.setSetting('smsAlerts', v ? '1' : '0');
                      await app.applyReminder();
                    }
                  : null,
            ),
            SwitchListTile(
              title: const T('Add known merchants automatically'),
              subtitle: const T('SMS from a merchant you have already categorised skip Review and go straight into your entries.'),
              value: app.autoConfirm,
              onChanged: (v) => app.setSetting('autoConfirm', v ? '1' : '0'),
            ),
            ListTile(
              title: const T('SMS start date'),
              subtitle: Text(app.smsStartDate == null
                  ? tr('Off · every message can be read')
                  : tr('Only messages from {d} on. Earlier days come from imported statements.',
                      {'d': '${shortDate(app.smsStartDate!)} ${app.smsStartDate!.year}'})),
              trailing: const Icon(Icons.start),
              onTap: () => _smsStart(context),
            ),
            ListTile(
              title: const T('Scan a date range'),
              subtitle: const T('Read messages between two dates. Already reviewed ones are skipped.'),
              trailing: const Icon(Icons.date_range),
              onTap: () => scanRange(context),
            ),
            ListTile(
              title: const T('Bank senders'),
              subtitle: Text(app.lines('senders').isEmpty
                  ? tr('Automatic: any SMS that looks like a transaction')
                  : tr('Only: {list}', {'list': app.lines('senders').join(', ')})),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendersScreen())),
            ),
            ListTile(
              title: const T('Ignored senders'),
              subtitle: Text(app.lines('blockedSenders').isEmpty ? tr('None') : app.lines('blockedSenders').join(', ')),
              onTap: () => _editText(context, 'Ignored senders', 'blockedSenders', multiline: true),
            ),
            ListTile(
              title: const T('Ignore messages containing'),
              subtitle: Text(tr('{n} keywords (OTP, declined, reminders…)', {'n': app.lines('ignoreKw').length})),
              onTap: () => _editText(context, 'Ignore keywords', 'ignoreKw', multiline: true,
                  help: 'One per line. Messages containing any of these are skipped.',
                  resetTo: defaultIgnoreKeywords.join('\n')),
            ),
            ListTile(
              title: const T('Treat as income when containing'),
              subtitle: Text(tr('{n} keywords (salary, deposit, refund…)', {'n': app.lines('incomeKw').length})),
              onTap: () => _editText(context, 'Income keywords', 'incomeKw', multiline: true,
                  help: 'One per line. Everything else is treated as an expense.',
                  resetTo: defaultIncomeKeywords.join('\n')),
            ),
            ListTile(
              title: const T('Test or teach the SMS reader'),
              subtitle: Text(app.templates.isEmpty
                  ? tr('Paste a bank message to see what the app reads. If it\'s wrong, mark the amount and merchant yourself.')
                  : tr('{n} formats taught. Paste a message to test or teach another.', {'n': app.templates.length})),
              trailing: const Icon(Icons.school_outlined),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeachSmsScreen())),
            ),

            _header(context, 'Alerts'),
            ListTile(
              title: const T('Warn when a budget reaches'),
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
              title: const T('Daily reminder'),
              subtitle: Text(tr('Log cash spending and confirm SMS at {t}', {'t': '${two(h)}:${two(m)}'})),
              value: app.flag('reminderOn'),
              onChanged: (v) async {
                await app.setSetting('reminderOn', v ? '1' : '0');
                await app.applyReminder();
              },
            ),
            ListTile(
              enabled: app.flag('reminderOn'),
              title: const T('Reminder time'),
              trailing: Text('${two(h)}:${two(m)}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
                if (t == null) return;
                await app.setSetting('reminderH', '${t.hour}');
                await app.setSetting('reminderM', '${t.minute}');
                await app.applyReminder();
              },
            ),

            _header(context, 'Categories'),
            ListTile(
              title: const T('Manage categories'),
              subtitle: Text(tr('{n} active', {'n': app.categories.where((c) => !c.archived).length})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
            ListTile(
              title: const T('Auto-category rules'),
              subtitle: Text(tr('{n} merchant keywords', {'n': app.rules.length})),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())),
            ),

            _header(context, 'Your data'),
            ListTile(
              leading: Icon(Icons.backup_outlined, color: app.backupDue ? warnColor : null),
              title: const T('Backup & restore'),
              subtitle: Text(app.daysSinceBackup == null
                  ? tr('Never backed up')
                  : app.daysSinceBackup == 0
                      ? tr('Last backup: today')
                      : trn(app.daysSinceBackup!, 'Last backup: {n} day ago', 'Last backup: {n} days ago')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const T('Import a statement (CSV)'),
              subtitle: const T('Statements or the web ledger export. Entries already in the app are skipped.'),
              onTap: () => _importFile(context),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const T('Paste CSV rows'),
              subtitle: const T('Header: date,type,category,amount,note'),
              onTap: () => _import(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: T(
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
        child: Text(tr(text), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );

  Future<void> _editText(BuildContext context, String title, String key,
      {String? help, bool multiline = false, String? resetTo}) async {
    final ctl = TextEditingController(text: app.settings[key] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: multiline ? 5 : 1,
            maxLines: multiline ? 12 : 1,
            decoration: InputDecoration(helperText: help == null ? null : tr(help), helperMaxLines: 3, border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          if (resetTo != null) TextButton(onPressed: () => ctl.text = resetTo, child: const T('Defaults')),
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const T('Save')),
        ],
      ),
    );
    if (result == null) return;
    await app.setSetting(key, result.trim());
    if (smsKeys.contains(key) && context.mounted) await rescanAfterChange(context);
  }

  Future<void> _smsStart(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: T('Start fresh with SMS', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: T('Messages before the start date are ignored and cleared from Review. '
                'Use it when statements (CSV) already cover the past, so nothing is counted twice.'),
          ),
          ListTile(
            leading: const Icon(Icons.today),
            title: const T('Start from today'),
            onTap: () => Navigator.pop(c, 'today'),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const T('Pick a start date'),
            subtitle: const T('e.g. the day after your last imported statement'),
            onTap: () => Navigator.pop(c, 'pick'),
          ),
          if (app.smsStartDate != null)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const T('Turn off the start date'),
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
        helpText: tr('Read SMS from this day on'),
      );
      if (date == null) return;
    }
    final cleared = await app.setSmsStartDate(date);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(date == null
          ? tr('Start date turned off.')
          : tr('SMS are read from {d} on.', {'d': shortDate(date)}) +
              (cleared > 0 ? ' ${tr('{n} older messages cleared from Review.', {'n': cleared})}' : '')),
    ));
  }

  Future<void> _restore(BuildContext context) async {
    String? text;
    try {
      text = await Native.pickFileText();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not open the file: {e}', {'e': e}))));
      return;
    }
    if (text == null || !context.mounted) return;
    final summary = app.describeBackup(text);
    if (summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('That file is not a Household Ledger backup (.json from "Email a backup").')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Restore this backup?'),
        content: Text('$summary\n\n${tr('Everything currently in the app ({n} entries, budgets, rules and '
            'settings) will be replaced. Email a backup first if you might need the current data.', {'n': app.txns.length})}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Replace and restore')),
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
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not open the file: {e}', {'e': e}))));
      return;
    }
    if (text == null || !context.mounted) return;
    if (app.describeBackup(text) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('That is a full backup. Use "Restore from backup" instead.')));
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
        title: const T('Import CSV'),
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Import')),
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
          appBar: AppBar(title: const T('Categories')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const T('New category'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            for (final g in groups) ...[
              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Eyebrow(g.$2)),
              for (final c in app.categories.where((c) => c.grp == g.$1))
                ListTile(
                  leading: CategoryDot(c.color, size: 14),
                  title: Text(c.display,
                      style: c.archived ? TextStyle(color: Theme.of(context).disabledColor, decoration: TextDecoration.lineThrough) : null),
                  subtitle: c.archived ? const T('Hidden') : null,
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
    final nameCtl = TextEditingController(text: existing?.display ?? '');
    var grp = existing?.grp ?? 'want';
    var color = existing?.color ?? palette[app.categories.length % palette.length];
    var archived = existing?.archived ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(tr(existing == null ? 'New category' : 'Edit category')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: nameCtl, autofocus: existing == null,
                  decoration: InputDecoration(labelText: tr('Name'), border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: grp,
                decoration: InputDecoration(labelText: tr('Type'), border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'need', child: T('Expense · need')),
                  DropdownMenuItem(value: 'want', child: T('Expense · want')),
                  DropdownMenuItem(value: 'save', child: T('Savings / investment')),
                  DropdownMenuItem(value: 'income', child: T('Income')),
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
                  title: const T('Hide this category'),
                  subtitle: const T('Past entries keep it'),
                  value: archived,
                  onChanged: (v) => setState(() => archived = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Save')),
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
        ..name = nameCtl.text.trim() == existing.display ? existing.name : nameCtl.text.trim()
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
          appBar: AppBar(title: const T('Auto-category rules')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const T('Add rule'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: T(
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
                subtitle: Text('${app.cat(r.categoryId)?.display ?? tr('Deleted category')}${r.learned ? ' · ${tr('learned')}' : ''}'),
                trailing: IconButton(
                  tooltip: tr('Delete rule'),
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
          title: const T('New rule'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, autofocus: true,
                decoration: InputDecoration(labelText: tr('Merchant contains'), hintText: tr('e.g. panda'), border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: catId,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Category'), border: const OutlineInputBorder()),
              items: [
                for (final cat in app.categories.where((x) => !x.archived))
                  DropdownMenuItem(value: cat.id, child: Text(cat.display)),
              ],
              onChanged: (v) => setState(() => catId = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Add')),
          ],
        ),
      ),
    );
    if (ok == true && catId != null && ctl.text.trim().isNotEmpty) await app.addRule(ctl.text, catId!);
  }
}

const smsKeys = {'senders', 'blockedSenders', 'ignoreKw', 'incomeKw', 'currency'};

/// Re-checks waiting items and rescans the current period, then reports the result.
Future<void> rescanAfterChange(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: T('Settings saved. Rescanning this period…'), duration: Duration(seconds: 1)));
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
    helpText: tr('Scan SMS from – to'),
    saveText: tr('Scan'),
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
        title: const T('Bank senders'),
        actions: [TextButton(onPressed: _save, child: const T('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            tr(selected.isEmpty
                ? 'No senders selected: any message that looks like a transaction is read. Tick your banks to read only their messages.'
                : 'Only messages from the ticked senders are read.'),
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (found == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (found!.isEmpty)
          const ListTile(title: T('No transaction messages found in the last 4 months.'))
        else
          for (final f in found!)
            CheckboxListTile(
              value: selected.contains(f.$1.toLowerCase()),
              title: Text(f.$1),
              subtitle: Text(trn(f.$2, '{n} transaction message in the last 4 months', '{n} transaction messages in the last 4 months')),
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
            subtitle: const T('Added manually'),
            onChanged: (_) => setState(() => selected.remove(e)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: manualCtl,
                decoration: InputDecoration(isDense: true, labelText: tr('Add a sender name'), border: const OutlineInputBorder()),
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
              child: const T('Add'),
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
        title: const T('Where should backups go?'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: tr('Your Gmail address'),
            helperText: tr('Saved for next time. You can change it in Settings.'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const T('Continue')),
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
        content: Text(tr(how == 'gmail'
            ? 'Gmail opened with the backup attached. Tap Send to finish.'
            : 'Choose your mail app, then tap Send to finish.')),
      ));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not open email: {e}', {'e': e}))));
    }
  }
}

/// Pick a backup file and restore it (used by onboarding too).
Future<void> restoreBackupFlow(BuildContext context) => const SettingsScreen()._restore(context);

/// Pick a statement CSV and import it, skipping entries already in the app.
Future<void> importStatementFlow(BuildContext context) => const SettingsScreen()._importFile(context);

// ---------------------------------------------------------------- backup

/// Backup to Gmail, restore from a file, and spreadsheet export in one place.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  Future<void> _emailCsv(BuildContext context) async {
    try {
      await Native.emailFile(
        content: app.exportCsv(),
        fileName: 'household-ledger-${isoDate(DateTime.now())}.csv',
        to: app.settings['backupEmail'] ?? '',
        subject: tr('Household Ledger entries {d}', {'d': isoDate(DateTime.now())}),
        body: tr('All entries as CSV.'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not open email: {e}', {'e': e}))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final email = app.settings['backupEmail'] ?? '';
        final days = app.daysSinceBackup;
        Widget card(List<Widget> children) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            );
        return Scaffold(
          appBar: AppBar(title: const T('Backup & restore')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: warnColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: warnColor),
                const SizedBox(width: 12),
                Expanded(
                  child: T('Your data lives only on this phone. Uninstalling the app or changing phones deletes it unless you keep a backup.',
                      style: TextStyle(height: 1.45, color: cs.onSurface)),
                ),
              ]),
            ),
            card([
              const T('Back up to Gmail', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.alternate_email),
                title: const T('Send backups to'),
                subtitle: Text(email.isEmpty ? tr('Not set — Gmail opens with an empty "To"') : email),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => const SettingsScreen()._editText(context, 'Backup email', 'backupEmail',
                    help: 'Backups are emailed here, usually your own Gmail address.'),
              ),
              Text(
                days == null
                    ? tr('Never backed up')
                    : days == 0
                        ? tr('Last backup: today')
                        : trn(days, 'Last backup: {n} day ago', 'Last backup: {n} days ago'),
                style: TextStyle(color: app.backupDue ? warnColor : cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => emailBackupFlow(context),
                icon: const Icon(Icons.backup_outlined),
                label: const T('Email a backup now'),
              ),
              const SizedBox(height: 6),
              T('Gmail opens with the backup attached — tap Send to finish.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
            card([
              const T('Restore', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              T('Pick a backup file saved from Gmail, Downloads or Drive. It replaces everything currently in the app.',
                  style: TextStyle(height: 1.45, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => const SettingsScreen()._restore(context),
                icon: const Icon(Icons.settings_backup_restore),
                label: const T('Choose backup file'),
              ),
            ]),
            card([
              const T('Export for spreadsheets', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(tr('{n} entries · opens in Excel or Google Sheets', {'n': app.txns.length}),
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () => _emailCsv(context),
                    icon: const Icon(Icons.mail_outline),
                    label: const T('Email CSV'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: app.exportCsv()));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('CSV copied to clipboard.')));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const T('Copy CSV'),
                  ),
                ),
              ]),
            ]),
          ]),
        );
      },
    );
  }
}
