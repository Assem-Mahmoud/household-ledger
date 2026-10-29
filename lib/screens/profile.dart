import 'package:flutter/material.dart' hide Category;

import '../accounts.dart';
import '../format.dart';
import '../i18n.dart';
import '../state.dart';
import '../widgets.dart';
import 'settings.dart' show rescanAfterChange;

/// Your name, how your money month works, and the accounts and cards you spend from.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final name = app.userName;
        final spend = app.byAccount(app.period);
        return Scaffold(
          appBar: AppBar(title: const T('Profile')),
          body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            const SizedBox(height: 8),
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: cs.primaryContainer,
                child: name.isEmpty
                    ? Icon(Icons.person_outline, size: 36, color: cs.onPrimaryContainer)
                    : Text(name.characters.first.toUpperCase(),
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => _editName(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(name.isEmpty ? tr('Add your name') : name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),

            _header(context, 'Your money month'),
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
              subtitle: Text(app.cycleStartDay == 1
                  ? tr('Calendar months')
                  : tr('Day {a} to day {b} of the next month (salary to salary)',
                      {'a': app.cycleStartDay, 'b': app.cycleStartDay - 1})),
              trailing: DropdownButton<int>(
                value: app.cycleStartDay,
                items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                onChanged: (v) => app.setSetting('cycleDay', '${v ?? 1}'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const T('Expected monthly income'),
              subtitle: const T('Salary plus allowances, used for planning'),
              trailing: Text(app.expectedIncome > 0 ? '${fmt(app.expectedIncome)} ${app.currency}' : tr('Not set'),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
              onTap: () => _editIncome(context),
            ),

            _header(context, 'Accounts & cards'),
            if (app.accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: T(
                    'Name the accounts and cards you spend from, like Main account, Credit card or Savings. '
                    'Bank SMS are matched to them by the card or account digits, so you can see what each one spends.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5, height: 1.4)),
              ),
            for (final a in app.accounts)
              ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(a.color).withOpacity(0.15),
                  child: Icon(accountIcon(a.type), size: 18, color: Color(a.color)),
                ),
                title: Text(a.name, style: TextStyle(color: a.archived ? cs.onSurfaceVariant : null)),
                subtitle: Text([
                  tr(accountTypes.firstWhere((t) => t.$1 == a.type, orElse: () => accountTypes.first).$2),
                  if (a.digitList.isNotEmpty) tr('ending {d}', {'d': a.digitList.join(', ')}),
                ].join(' · ')),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmt(spend[a.id]?.$1 ?? 0), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: tabular)),
                  T('spent this month', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ]),
                onTap: () => editAccount(context, a),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: OutlinedButton.icon(
                onPressed: () => editAccount(context, null),
                icon: const Icon(Icons.add_card),
                label: const T('Add account or card'),
              ),
            ),
            const _UnnamedCards(),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
        child: Text(tr(text), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
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
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: badColor))),
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
