import 'package:flutter/material.dart' hide Category;

import '../accounts.dart';
import '../format.dart';
import '../i18n.dart';
import '../state.dart';
import '../widgets.dart';
import '../theme.dart';
import '../tour.dart';
import 'help.dart';
import 'settings.dart' show BackupScreen, SettingsScreen, rescanAfterChange;

/// Your name, how your money month works, and the accounts and cards you spend from.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final name = app.userName;
        final spend = app.byAccount(app.period);
        return TourAutoStart(tour: 'profile', child: Scaffold(
          appBar: AppBar(title: const T('Profile'), actions: const [TourButton(tour: 'profile', target: 'info.profile'), SizedBox(width: 8)]),
          body: ListView(cacheExtent: 3000, padding: const EdgeInsets.only(bottom: 40), children: [
            SectionCard(
              child: Row(children: [
                const Avatar(size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? tr('Add your name') : name,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: name.isEmpty ? lc.primary : lc.text)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        app.currencyCode,
                        app.cycleStartDay == 1
                            ? tr('Calendar months')
                            : tr('Day {a} to day {b} of the next month (salary to salary)', {'a': app.cycleStartDay, 'b': app.cycleStartDay - 1}),
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: lc.muted),
                    ),
                  ]),
                ),
                IconButton(tooltip: tr('Your name'), icon: const Icon(Icons.edit_outlined), onPressed: () => _editName(context)),
              ]),
            ),

            _header(context, 'Your money month'),
            _group([
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const T('Currency'),
                subtitle: const T('Used to read amounts in bank SMS'),
                trailing: CurrencyPicker(onChanged: (code) async {
                  await app.setSetting('currency', code);
                  if (context.mounted) await rescanAfterChange(context);
                }),
              ),
              ListTile(
                leading: const Icon(Icons.event_repeat),
                title: const T('Month starts on day'),
                trailing: DropdownButton<int>(
                  value: app.cycleStartDay,
                  items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                  onChanged: (v) => app.setSetting('cycleDay', '${v ?? 1}'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const T('Expected monthly income'),
                trailing: Text(app.expectedIncome > 0 ? '${fmt(app.expectedIncome)} ${app.currency}' : tr('Not set'),
                    style: TextStyle(color: lc.primary, fontWeight: FontWeight.w600)),
                onTap: () => _editIncome(context),
              ),
            ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(children: [
                Expanded(child: Text(tr('Accounts & cards'), style: TextStyle(color: lc.text, fontSize: 16, fontWeight: FontWeight.w700))),
                if (app.accounts.isNotEmpty) Text(tr('spent this month'), style: TextStyle(fontSize: 12.5, color: lc.muted)),
              ]),
            ),
            if (app.accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: T(
                    'Name the accounts and cards you spend from, like Main account, Credit card or Savings. '
                    'Bank SMS are matched to them by the card or account digits, so you can see what each one spends.',
                    style: TextStyle(color: lc.muted, fontSize: 13.5, height: 1.4)),
              ),
            if (app.accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(builder: (context, box) {
                  final w = (box.maxWidth - 10) / 2;
                  return Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final a in app.accounts) SizedBox(width: w, child: _AccountTile(a, spend[a.id]?.$1 ?? 0)),
                  ]);
                }),
              ),
            TourTarget(
              id: 'profile.add',
              inset: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: OutlinedButton.icon(
                  onPressed: () => editAccount(context, null),
                  icon: const Icon(Icons.add_card),
                  label: const T('Add account or card'),
                ),
              ),
            ),
            const _UnnamedCards(),

            _header(context, 'App'),
            _group([
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const T('Appearance'),
                trailing: DropdownButton<String>(
                  value: app.appearance.value,
                  items: [
                    DropdownMenuItem(value: 'system', child: T('Phone setting')),
                    DropdownMenuItem(value: 'light', child: T('Light')),
                    DropdownMenuItem(value: 'dark', child: T('Dark')),
                  ],
                  onChanged: (v) {
                    if (v != null) app.setAppearance(v);
                  },
                ),
              ),
              TourTarget(id: 'profile.backup', child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const T('Backup & restore'),
                subtitle: Text(app.backupUri.isNotEmpty
                    ? '${app.backupWhere.isEmpty ? tr('Automatic backup') : app.backupWhere} · ${app.daysSinceBackup == 0 ? tr('Last backup: today') : app.daysSinceBackup == null ? tr('Never backed up') : trn(app.daysSinceBackup!, 'Last backup: {n} day ago', 'Last backup: {n} days ago')}'
                    : tr('Turn on automatic backup')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
              )),
              TourTarget(id: 'profile.help', child: ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const T('Help & tutorials'),
                subtitle: const T('Guided tours of each page'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
              )),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const T('All settings'),
                subtitle: const T('Language, bank messages, categories, reminders'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
          ]),
        ));
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text(tr(text), style: TextStyle(color: lc.text, fontSize: 16, fontWeight: FontWeight.w700)),
      );

  Widget _group(List<Widget> tiles) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: lc.card, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: lc.divider),
            tiles[i],
          ],
        ]),
      );

  Future<void> _editName(BuildContext context) async {
    final ctl = TextEditingController(text: app.userName);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Your name'),
        content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const T('Save')),
        ],
      ),
    );
    if (v != null) await app.setSetting('userName', v);
  }

  Future<void> _editIncome(BuildContext context) async {
    final ctl = TextEditingController(text: app.expectedIncome > 0 ? fmtAuto(app.expectedIncome).replaceAll(',', '') : '');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Expected monthly income'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: app.currency),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const T('Save')),
        ],
      ),
    );
    if (v != null) await app.setSetting('expectedIncome', '${parseAmount(v) ?? 0}');
  }
}

IconData accountIcon(String type) => switch (type) {
      'credit' => Icons.credit_card,
      'savings' => Icons.savings_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'cash' => Icons.payments_outlined,
      _ => Icons.account_balance_outlined,
    };

/// Card numbers seen in bank SMS that have no name yet.
class _UnnamedCards extends StatelessWidget {
  const _UnnamedCards();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<(String, int)>>(
      future: app.unnamedCards(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            T('Found in your bank messages', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (d, n) in list.take(6))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(tr('Card or account {d} · {n} messages', {'d': d, 'n': n})),
                  onPressed: () => editAccount(context, null, digits: d),
                ),
            ]),
          ]),
        );
      },
    );
  }
}

/// Add or edit an account or card. Returns true when something was saved.
Future<bool> editAccount(BuildContext context, Account? existing, {String? digits}) async {
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final digitsCtl = TextEditingController(text: existing?.digits ?? digits ?? '');
  var type = existing?.type ?? 'bank';
  String? error;
  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(existing == null ? 'Add account or card' : 'Edit account or card'),
                style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtl,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Name'),
                hintText: tr('e.g. Main account, Credit card, Savings'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Type'), border: const OutlineInputBorder()),
              items: [
                for (final t in accountTypes)
                  DropdownMenuItem(
                    value: t.$1,
                    child: Row(children: [Icon(accountIcon(t.$1), size: 18), const SizedBox(width: 8), Text(tr(t.$2))]),
                  ),
              ],
              onChanged: (v) => setState(() => type = v ?? 'bank'),
            ),
            const SizedBox(height: 12),
            if (type != 'cash')
              TextField(
                controller: digitsCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Last 4 digits (optional)'),
                  helperText: tr('As shown in your bank SMS, e.g. 1946. Separate several cards with commas.'),
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: badColor))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (nameCtl.text.trim().isEmpty) {
                  setState(() => error = tr('Give it a name.'));
                  return;
                }
                Navigator.pop(c, 'save');
              },
              child: const T('Save'),
            ),
            if (existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: badColor),
                onPressed: () => Navigator.pop(c, 'delete'),
                child: const T('Remove (entries are kept)'),
              ),
            ],
          ]),
        ),
      ),
    ),
  );
  if (action == null) return false;
  if (action == 'delete') {
    await app.deleteAccount(existing!);
    return true;
  }
  final a = existing ?? Account(id: 0, name: '');
  a
    ..name = nameCtl.text.trim()
    ..type = type
    ..digits = type == 'cash' ? '' : digitsCtl.text.trim();
  final linked = await app.saveAccount(a);
  if (linked > 0 && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('{n} earlier entries were linked to {a}.', {'n': linked, 'a': a.name}))));
  }
  return true;
}


/// An account shown as a small card: colour by type, name, digits and this month's spending.
class _AccountTile extends StatelessWidget {
  final Account a;
  final double spent;
  const _AccountTile(this.a, this.spent);
  @override
  Widget build(BuildContext context) {
    final c = lc;
    final (bg, fg, sub) = switch (a.type) {
      'credit' => (c.dark ? const Color(0xFF2A3531) : const Color(0xFF1E2A26), Colors.white, const Color(0xFF9FB3AC)),
      'bank' => (c.hero, c.heroText, c.heroSub),
      'savings' => (c.attnBg, c.text, c.attnText),
      _ => (c.card, c.text, c.muted),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => editAccount(context, a),
        child: Container(
          height: 124,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Expanded(
                child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
              ),
              Icon(accountIcon(a.type), size: 20, color: sub),
            ]),
            Text(a.digitList.isEmpty ? tr(accountTypes.firstWhere((t) => t.$1 == a.type, orElse: () => accountTypes.first).$2) : '•••• ${a.digitList.first}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: sub, letterSpacing: a.digitList.isEmpty ? 0 : 2)),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(fmt(spent), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: fg, fontFeatures: tabular)),
                ),
              ),
              const SizedBox(width: 4),
              Text(app.currency, style: TextStyle(fontSize: 12, color: sub)),
            ]),
          ]),
        ),
      ),
    );
  }
}
