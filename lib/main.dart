import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n.dart';

import 'native.dart';
import 'screens/analytics.dart';
import 'screens/budget.dart';
import 'screens/entries.dart';
import 'screens/home.dart';
import 'screens/review.dart';
import 'state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  runApp(const LedgerApp());
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6B5B), brightness: b),
        appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
      );

  @override
  Widget build(BuildContext context) {
    // Changing the language rebuilds the whole app so every screen picks up the new texts.
    return ValueListenableBuilder<String>(
      valueListenable: app.language,
      builder: (context, _, __) => MaterialApp(
        key: ValueKey(lang),
        title: 'Household Ledger',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Shell(),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  static const _pages = [HomeScreen(), ReviewScreen(), EntriesScreen(), AnalyticsScreen(), BudgetScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.checkPlanReminders();
      if (app.flag('smsOn')) app.scanSms();
    }
  }

  static bool _started = false;

  Future<void> _firstRun() async {
    if (_started) return; // the shell is rebuilt when the language changes
    _started = true;
    if (!app.flag('onboarded')) {
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const T('Welcome to Household Ledger'),
          content: const T(
            'The app can read your bank SMS to capture card purchases, transfers and salary automatically. '
            'You confirm each one and pick its category. Messages are read on this phone only.\n\n'
            'It also sends budget warnings and a daily reminder to log cash spending.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Manual entry only')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Allow SMS & notifications')),
          ],
        ),
      );
      await app.setSetting('onboarded', '1');
      if (go != true) {
        await app.setSetting('smsOn', '0');
        await Native.requestPermissions(sms: false);
        await app.applyReminder();
        return;
      }
    }
    await app.applyReminder();
    await app.checkPlanReminders();
    if (app.flag('smsOn')) {
      final msg = await app.scanSms();
      if (mounted && msg.isNotEmpty && app.pending.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, index, _) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          body: IndexedStack(index: index, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => app.tab.value = i,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.space_dashboard_outlined), selectedIcon: const Icon(Icons.space_dashboard), label: tr('Home')),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: app.pending.isNotEmpty,
                  label: Text('${app.pending.length}'),
                  child: const Icon(Icons.inbox_outlined),
                ),
                selectedIcon: const Icon(Icons.inbox),
                label: tr('Review'),
              ),
              NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: tr('Entries')),
              NavigationDestination(icon: const Icon(Icons.insights_outlined), selectedIcon: const Icon(Icons.insights), label: tr('Analytics')),
              NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: tr('Plan')),
            ],
          ),
        ),
      ),
    );
  }
}
