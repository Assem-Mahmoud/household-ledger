import 'package:flutter/material.dart' hide Category;
import 'package:flutter/services.dart';

import '../defaults.dart';
import '../i18n.dart';
import '../models.dart';
import '../native.dart';
import '../periods.dart';
import '../sms_parser.dart';
import '../state.dart';
import '../theme.dart';
import '../lock.dart';
import '../cloud.dart';
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
            SwitchListTile(
              secondary: const Icon(Icons.music_note_outlined),
              title: const T('Opening sound'),
              subtitle: const T('A short sound with the opening animation, also in silent mode.'),
              value: app.settings['introSound'] != '0',
              onChanged: (v) => app.setSetting('introSound', v ? '1' : '0'),
            ),

            _header(context, 'Security'),
            ...appLockTiles(context),

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
              title: const T('Your banks'),
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
                  'Data is stored only on this phone. Turn on automatic backup so a copy is kept on Google Drive.',
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
          const SnackBar(content: T('That file is not a Shahri backup (.json from "Email a backup").')));
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

/// Sender names that are almost certainly banks or wallets; used to pre-tick them.
const _bankHints = [
  'bank', 'rajhi', 'ahli', 'snb', 'riyad', 'sabb', 'anb', 'bilad', 'inma', 'jazira', 'saib', 'fransi', 'bsf',
  'stcpay', 'urpay', 'barq', 'd360', 'meem', 'nbe', 'cib', 'misr', 'qnb', 'alex', 'hsbc', 'enbd', 'adcb', 'fab',
  'mashreq', 'kfh', 'nbk', 'boubyan', 'emirates', 'mada',
];
bool looksLikeBank(String sender) {
  final s = sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _bankHints.any(s.contains);
}

/// The list of senders found in the phone's messages, to tick the user's banks. Used in setup, Review and Settings.
class BankPicker extends StatefulWidget {
  final Set<String> selected; // lower-case sender names; edited in place
  final VoidCallback onChanged;
  final bool preselect; // tick likely banks when nothing is chosen yet
  const BankPicker({super.key, required this.selected, required this.onChanged, this.preselect = false});
  @override
  State<BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<BankPicker> {
  List<(String, int)>? found;
  final manualCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    app.detectSenders().then((v) {
      if (!mounted) return;
      setState(() => found = v);
      if (widget.preselect && widget.selected.isEmpty) {
        widget.selected.addAll(v.where((f) => looksLikeBank(f.$1)).map((f) => f.$1.toLowerCase()));
        widget.onChanged();
      }
    });
  }

  @override
  void dispose() {
    manualCtl.dispose();
    super.dispose();
  }

  void _toggle(String s, bool on) {
    setState(() => on ? widget.selected.add(s) : widget.selected.remove(s));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final sel = widget.selected;
    final known = found?.map((e) => e.$1.toLowerCase()).toSet() ?? <String>{};
    final extra = sel.where((s) => !known.contains(s)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: sel.isEmpty ? c.attnBg : c.primarySoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(sel.isEmpty ? Icons.auto_awesome : Icons.account_balance, size: 20, color: sel.isEmpty ? c.attnText : c.onPrimarySoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              sel.isEmpty
                  ? tr('No bank picked: any message that looks like a bank transaction is read.')
                  : trn(sel.length, 'Only messages from {n} bank are read.', 'Only messages from these {n} banks are read.'),
              style: TextStyle(fontSize: 13, height: 1.35, color: sel.isEmpty ? c.attnText : c.onPrimarySoft),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      if (found == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (found!.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: T('No bank messages found on this phone yet. Add your bank\'s sender name below, or skip for now.',
              style: TextStyle(color: c.muted, height: 1.4)),
        )
      else
        for (final f in found!)
          CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: sel.contains(f.$1.toLowerCase()),
            secondary: CircleAvatar(
              backgroundColor: looksLikeBank(f.$1) ? c.primarySoft : c.raised,
              child: Icon(looksLikeBank(f.$1) ? Icons.account_balance : Icons.sms_outlined, size: 20, color: looksLikeBank(f.$1) ? c.onPrimarySoft : c.muted),
            ),
            title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(trn(f.$2, '{n} transaction message in the last 4 months', '{n} transaction messages in the last 4 months')),
            onChanged: (v) => _toggle(f.$1.toLowerCase(), v == true),
          ),
      for (final e in extra)
        CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: true,
          secondary: CircleAvatar(backgroundColor: c.primarySoft, child: Icon(Icons.account_balance, size: 20, color: c.onPrimarySoft)),
          title: Text(e),
          subtitle: const T('Added manually'),
          onChanged: (_) => _toggle(e, false),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: manualCtl,
            decoration: InputDecoration(isDense: true, labelText: tr('Add a sender name'), hintText: tr('e.g. AlRajhiBank'), border: const OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: () {
            final t = manualCtl.text.trim().toLowerCase();
            if (t.isEmpty) return;
            manualCtl.clear();
            _toggle(t, true);
          },
          child: const T('Add'),
        ),
      ]),
    ]);
  }
}

/// Choose which SMS senders are banks, from the senders found in the phone's messages.
class SendersScreen extends StatefulWidget {
  const SendersScreen({super.key});
  @override
  State<SendersScreen> createState() => _SendersScreenState();
}

class _SendersScreenState extends State<SendersScreen> {
  late Set<String> selected = app.lines('senders').toSet();

  Future<void> _save() async {
    await app.setSetting('senders', selected.join('\n'));
    if (!mounted) return;
    final nav = Navigator.of(context);
    await rescanAfterChange(context);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const T('Your banks'),
          actions: [TextButton(onPressed: _save, child: const T('Save'))],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          BankPicker(selected: selected, onChanged: () => setState(() {})),
        ]),
      );
}

/// Opens the share sheet with a backup file (WhatsApp, email, Drive…).
Future<void> shareBackupFlow(BuildContext context) async {
  try {
    await app.shareBackup();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not share the backup: {e}', {'e': e}))));
    }
  }
}

/// Pick a backup file and restore it (used by onboarding too).
Future<void> restoreBackupFlow(BuildContext context) => const SettingsScreen()._restore(context);

/// Pick a statement CSV and import it, skipping entries already in the app.
Future<void> importStatementFlow(BuildContext context) => const SettingsScreen()._importFile(context);

// ---------------------------------------------------------------- backup

/// Automatic backup to a chosen place (e.g. Google Drive), sharing, restore, export and start fresh.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  Future<void> _shareCsv(BuildContext context) async {
    try {
      await Native.shareFile(
        content: app.exportCsv(),
        fileName: 'shahri-entries-${isoDate(DateTime.now())}.csv',
        subject: tr('Shahri entries {d}', {'d': isoDate(DateTime.now())}),
        body: tr('All entries as CSV.'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not share the backup: {e}', {'e': e}))));
      }
    }
  }

  Future<void> _choose(BuildContext context) async {
    final ok = await app.chooseBackupLocation();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: T('Backup saved. It will be updated automatically every day.')));
    } else if (app.backupUri.isNotEmpty && app.backupFailed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Could not write the backup there. Try another place.')));
    }
  }

  Future<void> _backupNow(BuildContext context) async {
    final ok = await app.backupNow();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: T(ok ? 'Backup updated.' : 'Could not write the backup. Choose the location again.')));
    }
  }

  Future<void> _deleteEntries(BuildContext context) async {
    final now = DateTime.now();
    var from = 'month';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const T('Delete all entries?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const T('All entries and the SMS review list are deleted. Your categories, accounts, budgets, plan, '
                'yearly expenses and merchant rules are kept. Take a backup first if you may need the data.'),
            const SizedBox(height: 14),
            const T('Read bank SMS again from', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'month',
              groupValue: from,
              title: Text(tr('The start of this month ({d})', {'d': shortDate(periodFor(now, app.cycleStartDay).start)})),
              onChanged: (v) => setState(() => from = v!),
            ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: 'today',
              groupValue: from,
              title: const T('Today'),
              onChanged: (v) => setState(() => from = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: badColor),
              onPressed: () => Navigator.pop(c, true),
              child: const T('Delete entries'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await app.deleteAllEntries(from == 'today' ? now : periodFor(now, app.cycleStartDay).start);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('All entries deleted. Starting fresh.')));
    if (app.flag('smsOn')) {
      final msg = await app.scanSms();
      if (context.mounted && msg.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _resetApp(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Reset the app?'),
        content: const T('Everything is deleted: entries, categories, accounts, budgets, plan and settings. '
            'The app starts again with first-time setup. This cannot be undone unless you have a backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: badColor),
            onPressed: () => Navigator.pop(c, true),
            child: const T('Reset everything'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    // a reset phone starts at the sign-in screen; the cloud copy stays in the Google account
    if (Cloud.signedIn) await Cloud.signOut();
    await app.resetApp();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final days = app.daysSinceBackup;
        final hasPlace = app.backupUri.isNotEmpty;
        Widget card(List<Widget> children, {Color? border}) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: border ?? cs.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            );
        final last = days == null
            ? tr('Never backed up')
            : days == 0
                ? tr('Last backup: today')
                : trn(days, 'Last backup: {n} day ago', 'Last backup: {n} days ago');
        return Scaffold(
          appBar: AppBar(title: const T('Backup & restore')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            card([
              const T('Automatic backup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              T(
                  hasPlace
                      ? 'The backup file is updated every day when you open the app. On a new phone, install the app and restore it from there.'
                      : 'Like WhatsApp: choose a place once, ideally Google Drive, and the app keeps a backup file there, updated every day. On a new phone, restore from that file.',
                  style: TextStyle(height: 1.45, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (hasPlace) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(app.backupWhere.contains('Drive') ? Icons.add_to_drive : Icons.folder_outlined),
                  title: Text(app.backupWhere.isEmpty ? tr('Chosen location') : app.backupWhere),
                  subtitle: Text(app.backupFailed ? tr('The last backup could not be written') : last,
                      style: TextStyle(color: app.backupFailed ? badColor : null)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const T('Back up automatically every day'),
                  value: app.flag('autoBackup'),
                  onChanged: (v) => app.setSetting('autoBackup', v ? '1' : '0'),
                ),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => _backupNow(context),
                      icon: const Icon(Icons.backup_outlined),
                      label: const T('Back up now'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: () => _choose(context),
                    child: const T('Change place'),
                  ),
                ]),
              ] else
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _choose(context),
                  icon: const Icon(Icons.add_to_drive),
                  label: const T('Choose where to keep it'),
                ),
              if (!hasPlace) ...[
                const SizedBox(height: 6),
                T('In the window that opens, tap ☰ and choose Drive, pick a folder, then Save.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ]),
            card([
              const T('Send a copy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              T('Send the backup file to yourself on WhatsApp or by email, or save it anywhere.',
                  style: TextStyle(height: 1.45, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => shareBackupFlow(context),
                icon: const Icon(Icons.share_outlined),
                label: const T('Share backup file'),
              ),
            ]),
            card([
              const T('Restore', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              T('Pick a backup file from Google Drive, WhatsApp, email or Downloads. It replaces everything currently in the app.',
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
                    onPressed: () => _shareCsv(context),
                    icon: const Icon(Icons.share_outlined),
                    label: const T('Share CSV'),
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
            card(border: badColor.withOpacity(0.5), [
              T('Start fresh', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: badColor)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: badColor),
                onPressed: () => _deleteEntries(context),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const T('Delete all entries (keep my setup)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: badColor),
                onPressed: () => _resetApp(context),
                icon: const Icon(Icons.restart_alt),
                label: const T('Reset the app completely'),
              ),
            ]),
          ]),
        );
      },
    );
  }
}
