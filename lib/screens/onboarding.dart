import 'package:flutter/material.dart' hide Category;

import '../brand.dart';
import '../cloud.dart';
import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../native.dart';
import '../periods.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings.dart' show BankPicker, importStatementFlow, restoreBackupFlow;

/// First-run setup: language → SMS disclosure → month & income → categories → where to start.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  /// After restoring a backup (Google or file) only the phone-specific steps remain: SMS permission and banks.
  /// Static, so it survives the rebuild when the restored backup switches the language.
  static bool _restored = false;
  bool restored = false;
  List<Widget Function(BuildContext)> get _pages => restored
      ? [_language, _disclosure, if (smsAllowed) _banks]
      : [_language, _disclosure, if (smsAllowed) _banks, _month, _categories, _start];
  int get _steps => _pages.length;
  final Set<String> banks = {};
  int step = 0;
  int _dir = 1; // slide direction between steps
  static bool _brandPlayed = false; // the logo animation plays once, not on every language switch
  bool smsAllowed = false;
  bool payday = false;
  int paydayDay = 27;
  bool reminderOn = true;
  final incomeCtl = TextEditingController();
  final nameCtl = TextEditingController(text: app.userName);
  late Set<int> off;
  String start = 'month';
  DateTime? picked;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    off = app.categories.where((c) => c.archived).map((c) => c.id).toSet();
    if (_restored) {
      restored = true;
      step = 1;
      banks.addAll(app.lines('senders'));
    }
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
    nameCtl.dispose();
    super.dispose();
  }

  void _next() => setState(() {
        _dir = 1;
        step = (step + 1).clamp(0, _steps - 1).toInt();
      });
  void _back() => setState(() {
        _dir = -1;
        step = (step - 1).clamp(0, _steps - 1).toInt();
      });

  Future<void> _sms(bool allow) async {
    setState(() => busy = true);
    final r = await Native.requestPermissions(sms: allow);
    smsAllowed = allow && r['sms'] == true;
    if (allow && !smsAllowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('SMS access was not granted. You can turn it on later in Settings.')));
    }
    setState(() => busy = false);
    if (restored && !smsAllowed) {
      await _finishRestored();
    } else {
      _next();
    }
  }

  void _enterRestored() {
    _restored = true;
    if (!mounted) return; // the language switch rebuilt setup; the new screen picks it up
    setState(() {
      restored = true;
      step = 1;
      _dir = 1;
      banks
        ..clear()
        ..addAll(app.lines('senders'));
    });
  }

  /// Ends setup after a restore: keeps the restored settings, only adds what belongs to this phone.
  Future<void> _finishRestored() async {
    setState(() => busy = true);
    await app.setSetting('smsOn', smsAllowed ? '1' : '0', notify: false);
    if (smsAllowed) await app.setSetting('senders', banks.join('\n'), notify: false);
    _restored = false;
    app.setupRestore = false;
    await app.setSetting('onboarded', '1');
    await app.applyReminder();
    app.goToday();
    if (smsAllowed) app.openActivity(0);
    widget.onDone();
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
    if (smsAllowed) await app.setSetting('senders', banks.join('\n'), notify: false);
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
    app.setupRestore = true;
    await restoreBackupFlow(context);
    if (app.txns.isNotEmpty) {
      _enterRestored();
    } else {
      app.setupRestore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = _pages;
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
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(step);
                  final rtl = Directionality.of(context) == TextDirection.rtl;
                  final dx = (incoming ? 0.25 : -0.25) * _dir * (rtl ? -1 : 1);
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim), child: child),
                  );
                },
                child: SingleChildScrollView(key: ValueKey(step), child: pages[step](context)),
              ),
            ),
            const SizedBox(height: 12),
            _buttons(context),
          ]),
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    if (step == 0) return const SizedBox.shrink(); // sign-in buttons are part of the first page

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
          last ? (restored ? tr('Go to Home') : tr(smsAllowed && start != 'today' ? 'Start reviewing' : 'Go to Home')) : tr('Continue'),
          last ? (restored ? _finishRestored : _finish) : _next,
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
    final c = lc;
    if (!_brandPlayed) Future.delayed(const Duration(milliseconds: 2000), () => _brandPlayed = true);
    Widget langChip(String code, String label) {
      final on = lang == code;
      return Material(
        color: on ? c.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => app.setLanguagePref(code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: on ? c.onPrimary : c.text)),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // language switch, always reachable at the top
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(21)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [langChip('en', 'English'), langChip('ar', 'العربية')]),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: _brandPlayed
            ? const BrandTile(size: 92)
            : Play(ms: 1100, builder: (context, t) => BrandTile(size: 92, progress: t)),
      ),
      const SizedBox(height: 18),
      Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: _brandPlayed
              ? const Wordmark(height: 42)
              : Play(ms: 1500, delay: 250, builder: (context, t) => Wordmark(height: 42, progress: t)),
        ),
      ),
      const SizedBox(height: 12),
      Entrance(
        delay: _brandPlayed ? 0 : 450,
        child: T('Track income and spending from your bank SMS, plan each month, and see where your money goes.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurfaceVariant)),
      ),
      const SizedBox(height: 26),
      if (Cloud.ready) ...[
        Entrance(
          delay: _brandPlayed ? 0 : 600,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: busy ? null : _google,
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF4285F4))),
                    ),
                    const SizedBox(width: 10),
                    Text(tr('Continue with Google'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
          ),
        ),
        const SizedBox(height: 6),
        Entrance(
          delay: _brandPlayed ? 0 : 650,
          child: T('Your data is backed up to your Google account and comes back on a new phone.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.muted)),
        ),
        const SizedBox(height: 18),
        Entrance(
          delay: _brandPlayed ? 0 : 700,
          child: Row(children: [
            Expanded(child: Divider(color: c.divider)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: T('or continue without signing in', style: TextStyle(fontSize: 13, color: c.muted))),
            Expanded(child: Divider(color: c.divider)),
          ]),
        ),
        const SizedBox(height: 14),
      ],
      Entrance(
        delay: _brandPlayed ? 0 : 750,
        child: TextField(
          controller: nameCtl,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          // saved as you type, so switching the language doesn't lose it
          onChanged: (v) {
            app.setSetting('userName', v.trim(), notify: false);
            setState(() {});
          },
          onSubmitted: (_) => _withoutAccount(),
          decoration: InputDecoration(
            labelText: tr('Your name'),
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Entrance(
        delay: _brandPlayed ? 0 : 800,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: busy || nameCtl.text.trim().isEmpty ? null : _withoutAccount,
          child: Text(tr('Continue without signing in'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        ),
      ),
      const SizedBox(height: 4),
      TextButton(onPressed: busy ? null : _restore, child: const T('I have a backup file')),
    ]);
  }

  Future<void> _withoutAccount() async {
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    await app.setSetting('userName', name, notify: false);
    _next();
  }

  /// Google sign-in on the first screen: brings back the cloud copy if there is one, otherwise continues setup.
  Future<void> _google() async {
    final m = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final err = await Cloud.signIn();
      if (err != null) {
        if (err.isNotEmpty) m.showSnackBar(SnackBar(content: Text(tr('Could not sign in: {e}', {'e': err}))));
        return;
      }
      if (await Cloud.info() != null) {
        app.setupRestore = true;
        _restored = true; // set first: the restore may switch the language and rebuild this screen
        final err = await Cloud.restore();
        if (err != null) {
          _restored = false;
          app.setupRestore = false;
          if (mounted) m.showSnackBar(SnackBar(content: Text(err)));
          return;
        }
        if (mounted) m.showSnackBar(SnackBar(content: Text(tr('Welcome back. Your data was restored from the cloud.'))));
        _enterRestored();
        return;
      }
      final name = nameCtl.text.trim().isNotEmpty ? nameCtl.text.trim() : Cloud.name;
      if (name.isNotEmpty) await app.setSetting('userName', name, notify: false);
      _next();
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
      if (restored)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: lc.primarySoft, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.check_circle, color: lc.onPrimarySoft),
            const SizedBox(width: 10),
            Expanded(
              child: T('Your data is back. One more step on this phone: allow reading your bank SMS.',
                  style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: lc.onPrimarySoft)),
            ),
          ]),
        ),
      const SmsDemo(),
      const SizedBox(height: 18),
      _title(context, 'Capture spending from your bank SMS',
          'Shahri reads SMS from your bank to record card purchases, transfers and salary. You confirm each one before it counts.'),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Entrance(delay: 350, child: point('Reads:', 'messages that look like bank transactions — amount, merchant, date.')),
          Entrance(delay: 450, child: point('Ignores:', 'personal messages and one-time passwords.')),
          Entrance(delay: 550, child: point('Stays on this phone:', 'nothing is uploaded or shared. Backups go only where you send them.')),
          Entrance(delay: 650, child: point('Notifications:', 'budget warnings, new-transaction alerts and a daily reminder.')),
        ]),
      ),
      const SizedBox(height: 12),
      T('Android asks for permission next. You can change this any time in Settings.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]);
  }

  Widget _banks(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _title(context, 'Which banks do you use?',
          'Pick your banks so only their messages are read. We ticked the ones that look like banks. Not sure? Leave it empty and any message that looks like a bank transaction is read.'),
      BankPicker(selected: banks, preselect: true, onChanged: () => setState(() {})),
      const SizedBox(height: 10),
      T('You can change this any time from the To review page or Settings.', style: TextStyle(fontSize: 12.5, color: lc.muted)),
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

/// Step 2 illustration: a bank SMS arrives, gets read, and becomes a neat entry. Tap to replay.
class SmsDemo extends StatelessWidget {
  const SmsDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    return Play(
      ms: 2600,
      delay: 150,
      replay: true,
      builder: (context, t) {
        final smsIn = Curves.easeOutCubic.transform(brandSeg(t, 0, 0.15));
        final scan = brandSeg(t, 0.17, 0.42);
        final dim = brandSeg(t, 0.45, 0.58);
        final arrow = brandSeg(t, 0.48, 0.58);
        final entry = Curves.easeOutBack.transform(brandSeg(t, 0.55, 0.75));
        final tick = brandSeg(t, 0.76, 0.88);
        final tickScale = tick < 0.6 ? tick / 0.6 * 1.2 : 1.2 - 0.2 * (tick - 0.6) / 0.4;
        return Container(
          height: 262,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Opacity(
              opacity: smsIn * (1 - 0.6 * dim),
              child: Transform.translate(
                offset: Offset(-30 * (1 - smsIn), -6 * dim),
                child: Transform.scale(
                  scale: 1 - 0.05 * dim,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: const BorderRadiusDirectional.only(
                        topStart: Radius.circular(16), topEnd: Radius.circular(16),
                        bottomEnd: Radius.circular(16), bottomStart: Radius.circular(4),
                      ),
                      boxShadow: [BoxShadow(color: c.primary.withOpacity(0.10), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Stack(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          T('Your bank · 08:15', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted)),
                          const SizedBox(height: 4),
                          T('Purchase: SAR 45.50 at LULU HYPERMARKET. Card ending 1234.',
                              style: TextStyle(fontSize: 13.5, height: 1.45, color: c.text)),
                        ]),
                      ),
                      if (scan > 0 && scan < 1)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 70 * scan,
                          child: Container(
                            height: 3,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [Color(0x00E8912D), brandGold, Color(0x00E8912D)]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: arrow,
              child: Transform.translate(
                offset: Offset(0, -6 * (1 - arrow)),
                child: Icon(Icons.arrow_downward_rounded, color: c.primary, size: 24),
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: entry.clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - entry)),
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: c.primary.withOpacity(0.16), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: c.attnBg, borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.shopping_cart_outlined, color: brandGold, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          T('Lulu Hypermarket', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.text)),
                          T('Groceries · Main card ··1234', style: TextStyle(fontSize: 12.5, color: c.muted)),
                        ]),
                      ),
                      Text('45.50', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.text)),
                    ]),
                  ),
                  PositionedDirectional(
                    top: -9,
                    end: -7,
                    child: Opacity(
                      opacity: tick.clamp(0.0, 1.0).toDouble(),
                      child: Transform.scale(
                        scale: tickScale,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2)),
                          child: Icon(Icons.check, size: 14, color: c.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}
