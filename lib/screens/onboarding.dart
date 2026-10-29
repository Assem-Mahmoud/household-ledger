import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../native.dart';
import '../periods.dart';
import '../state.dart';
import '../widgets.dart';
import 'settings.dart' show importStatementFlow, restoreBackupFlow;

/// First-run setup: language → SMS disclosure → month & income → categories → where to start.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _steps = 5;
  int step = 0;
  bool smsAllowed = false;
  bool payday = false;
  int paydayDay = 27;
  bool reminderOn = true;
  final incomeCtl = TextEditingController();
  late Set<int> off;
  String start = 'month';
  DateTime? picked;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    off = app.categories.where((c) => c.archived).map((c) => c.id).toSet();
    if (app.txns.isEmpty) {
      // fresh install: start with the less common categories switched off
      for (final n in const ['Education', 'Travel', 'Consulting / freelance']) {
        final c = app.catByName(n);
        if (c != null) off.add(c.id);
      }
    }
    final d = app.cycleStartDay;
    if (d != 1) {
      payday = true;
      paydayDay = d;
    }
    if (app.expectedIncome > 0) incomeCtl.text = fmtAuto(app.expectedIncome).replaceAll(',', '');
  }

  @override
  void dispose() {
    incomeCtl.dispose();
    super.dispose();
  }

  void _next() => setState(() => step = (step + 1).clamp(0, _steps - 1).toInt());
  void _back() => setState(() => step = (step - 1).clamp(0, _steps - 1).toInt());

  Future<void> _sms(bool allow) async {
    setState(() => busy = true);
    final r = await Native.requestPermissions(sms: allow);
    smsAllowed = allow && r['sms'] == true;
    if (allow && !smsAllowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('SMS access was not granted. You can turn it on later in Settings.')));
    }
    setState(() => busy = false);
    _next();
  }

  Future<void> _finish() async {
    setState(() => busy = true);
    await app.setSetting('cycleDay', '${payday ? paydayDay : 1}', notify: false);
    final income = parseAmount(incomeCtl.text) ?? 0;
    if (income > 0) await app.setSetting('expectedIncome', '$income', notify: false);
    await app.setSetting('reminderOn', reminderOn ? '1' : '0', notify: false);
    for (final c in app.categories) {
      final hide = off.contains(c.id);
      if (c.archived != hide) {
        c.archived = hide;
        await app.updateCategory(c);
      }
    }
    await app.setSetting('smsOn', smsAllowed ? '1' : '0', notify: false);
    if (smsAllowed) {
      final now = DateTime.now();
      final from = switch (start) {
        'today' => now,
        'pick' => picked ?? now,
        _ => periodFor(now, app.cycleStartDay).start,
      };
      await app.setSmsStartDate(from);
    }
    await app.setSetting('onboarded', '1');
    await app.applyReminder();
    app.goToday();
    if (smsAllowed && start != 'today') app.openActivity(0);
    widget.onDone();
  }

  Future<void> _restore() async {
    await restoreBackupFlow(context);
    if (app.txns.isNotEmpty || app.flag('onboarded')) {
      await app.setSetting('onboarded', '1');
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = [_language, _disclosure, _month, _categories, _start];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Step {a} of {b}', {'a': step + 1, 'b': _steps}),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < _steps; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? cs.primary : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: pages[step](context))),
            const SizedBox(height: 12),
            _buttons(context),
          ]),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    if (step == 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _primary(tr('Get started'), _next),
        const SizedBox(height: 6),
        TextButton(onPressed: busy ? null : _restore, child: const T('I have a backup — restore it')),
      ]);
    }
    if (step == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _primary(tr('Allow SMS & notifications'), () => _sms(true)),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: busy ? null : () => _sms(false),
          child: const T('Use manual entry only'),
        ),
      ]);
    }
    final last = step == _steps - 1;
    return Row(children: [
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(96, 52)),
        onPressed: busy ? null : _back,
        child: const T('Back'),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _primary(
          last ? tr(smsAllowed && start != 'today' ? 'Start reviewing' : 'Go to Home') : tr('Continue'),
          last ? _finish : _next,
        ),
      ),
    ]);
  }

  Widget _primary(String label, VoidCallback onTap) => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        onPressed: busy ? null : onTap,
        child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
      );

  Widget _title(BuildContext context, String title, [String? body]) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(title), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(tr(body), style: TextStyle(fontSize: 15, height: 1.45, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 20),
        ],
      );

  // ---------------------------------------------------------------- steps

  Widget _language(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(24)),
          child: Icon(Icons.account_balance_wallet_outlined, size: 44, color: cs.onPrimaryContainer),
        ),
      ),
      const SizedBox(height: 16),
      Text(tr('Household Ledger'), textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      T('Track income and spending from your bank SMS, plan each month, and see where your money goes. Everything stays on your phone.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurfaceVariant)),
      const SizedBox(height: 28),
      T('Choose your language', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      _Choice(
        title: 'العربية',
        subtitle: tr('Right-to-left layout'),
        selected: lang == 'ar',
        onTap: () => app.setLanguagePref('ar'),
        raw: true,
      ),
      _Choice(title: 'English', selected: lang == 'en', onTap: () => app.setLanguagePref('en'), raw: true),
    ]);
  }

  Widget _disclosure(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget point(String bold, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsetsDirectional.only(end: 12, top: 1),
              decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              child: Icon(Icons.check, size: 15, color: cs.onPrimary),
            ),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${tr(bold)} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: tr(text)),
              ]), style: const TextStyle(fontSize: 14.5, height: 1.45)),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
          child: Icon(Icons.sms_outlined, size: 30, color: cs.onPrimaryContainer),
        ),
      ),
      const SizedBox(height: 18),
      _title(context, 'Capture spending from your bank SMS',
          'Household Ledger reads SMS from your bank to record card purchases, transfers and salary. You confirm each one before it counts.'),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          point('Reads:', 'messages that look like bank transactions — amount, merchant, date.'),
          point('Ignores:', 'personal messages and one-time passwords.'),
          point('Stays on this phone:', 'nothing is uploaded or shared. Backups go only where you send them.'),
          point('Notifications:', 'budget warnings, new-transaction alerts and a daily reminder.'),
        ]),
      ),
      const SizedBox(height: 12),
      T('Android asks for permission next. You can change this any time in Settings.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]);
  }

  Widget _month(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(context, 'How does your month run?', 'This decides how totals, budgets and the plan are grouped.'),
      T('My month starts', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
      const SizedBox(height: 10),
      _Choice(
        title: 'On the 1st (calendar month)',
        subtitle: 'Best when salary dates move around',
        selected: !payday,
        onTap: () => setState(() => payday = false),
      ),
      _Choice(
        title: 'On payday',
        subtitle: 'Salary to salary, e.g. 27th → 26th',
        selected: payday,
        onTap: () => setState(() => payday = true),
        trailing: payday
            ? DropdownButton<int>(
                value: paydayDay,
                items: [for (var d = 2; d <= 28; d++) DropdownMenuItem(value: d, child: Text(tr('Day {n}', {'n': d})))],
                onChanged: (v) => setState(() => paydayDay = v ?? 27),
              )
            : null,
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: T('My currency', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
        CurrencyPicker(onChanged: (code) async {
          await app.setSetting('currency', code, notify: false);
          setState(() {});
        }),
      ]),
      const SizedBox(height: 10),
      TextField(
        controller: incomeCtl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          labelText: tr('Expected monthly income (optional)'),
          helperText: tr('Salary plus allowances. Used for planning only — your real salary comes from SMS.'),
          helperMaxLines: 2,
          suffixText: app.currency,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const T('Daily reminder'),
        subtitle: Text(tr('Log cash spending at {t}', {'t': '${two(int.tryParse(app.settings['reminderH'] ?? '21') ?? 21)}:${two(int.tryParse(app.settings['reminderM'] ?? '0') ?? 0)}'})),
        value: reminderOn,
        onChanged: (v) => setState(() => reminderOn = v),
      ),
    ]);
  }

  Widget _categories(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const groups = [('need', 'Needs', 'essentials'), ('want', 'Wants', 'lifestyle'), ('save', 'Savings', 'money you keep'), ('income', 'Income', 'money in')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(context, 'Ready-made categories', 'Untick what you don\'t need. Rename, add or hide categories any time.'),
      for (final g in groups) ...[
        Row(children: [
          Eyebrow(g.$2),
          const SizedBox(width: 8),
          Text(tr(g.$3), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in app.categories.where((c) => c.grp == g.$1))
            FilterChip(
              avatar: off.contains(c.id) ? null : CategoryDot(c.color),
              label: Text(c.display),
              selected: !off.contains(c.id),
              showCheckmark: false,
              onSelected: (v) => setState(() => v ? off.remove(c.id) : off.add(c.id)),
            ),
        ]),
        const SizedBox(height: 18),
      ],
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: T('Common merchants (Lulu, Panda, Jahez, STC, Nahdi…) are already linked to these categories. Budgets can be set later from the Plan tab.',
                style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
          ),
        ]),
      ),
    ]);
  }

  Widget _start(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final importBox = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Have older history?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        T('Import a bank or card statement (CSV). Entries already in the app are skipped, so nothing is counted twice.',
            style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: busy ? null : () => importStatementFlow(context),
          icon: const Icon(Icons.upload_file),
          label: const T('Import a statement file'),
        ),
      ]),
    );
    if (!smsAllowed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(context, 'You\'re all set', 'Add entries with the + button. You can switch on SMS capture later in Settings.'),
        importBox,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(context, 'Where should your ledger start?', 'Bank SMS from this day on will be read. Earlier days can come from a statement.'),
      _Choice(
        title: 'From the start of this month',
        subtitle: 'Review this month\'s transactions now',
        selected: start == 'month',
        onTap: () => setState(() => start = 'month'),
      ),
      _Choice(
        title: 'From today',
        subtitle: 'Clean start, nothing to review',
        selected: start == 'today',
        onTap: () => setState(() => start = 'today'),
      ),
      _Choice(
        title: 'Pick a date',
        subtitle: picked == null ? 'e.g. the day after your last imported statement' : '${shortDate(picked!)} ${picked!.year}',
        rawSubtitle: picked != null,
        selected: start == 'pick',
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: picked ?? DateTime.now().subtract(const Duration(days: 30)),
            firstDate: DateTime(2018),
            lastDate: DateTime.now(),
          );
          if (d != null) setState(() {
            picked = d;
            start = 'pick';
          });
        },
      ),
      const SizedBox(height: 8),
      importBox,
    ]);
  }
}

/// A large selectable option card.
class _Choice extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool raw; // title already final (not a translation key)
  final bool rawSubtitle;

  const _Choice({
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.raw = false,
    this.rawSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? cs.primaryContainer.withOpacity(0.55) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? cs.primary : cs.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(raw ? title : tr(title), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(rawSubtitle ? subtitle! : tr(subtitle!),
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      ),
    );
  }
}
