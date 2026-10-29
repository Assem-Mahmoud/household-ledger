import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n.dart';

import 'screens/activity.dart';
import 'screens/analytics.dart';
import 'screens/budget.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'screens/quick_add.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  runApp(const LedgerApp());
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Changing the language rebuilds the whole app so every screen picks up the new texts.
    return ListenableBuilder(
      listenable: Listenable.merge([app.language, app.resets, app.appearance]),
      builder: (context, _) {
        // light/dark: the user's choice, or follow the phone
        final mode = app.appearance.value;
        final dark = mode == 'dark' || (mode != 'light' && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        setDarkMode(dark);
        return MaterialApp(
        key: ValueKey('$lang-${app.resets.value}-$dark'),
        title: 'Household Ledger',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? darkColors : lightColors),
        themeMode: ThemeMode.light,
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Shell(),
      );
      },
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  static const _pages = [HomeScreen(), ActivityScreen(), AnalyticsScreen(), BudgetScreen()];

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
    // not during first-run setup: the permission dialog itself pauses and resumes the app
    if (state == AppLifecycleState.resumed && app.flag('onboarded')) {
      app.checkPlanReminders();
      if (app.flag('smsOn')) app.scanSms();
      app.autoBackupIfDue();
    }
  }

  Future<void> _firstRun() async {
    if (app.firstRunDone || !app.flag('onboarded')) return; // runs once, after setup is done
    app.firstRunDone = true;
    await app.applyReminder();
    await app.checkPlanReminders();
    if (app.flag('smsOn')) {
      final msg = await app.scanSms();
      if (mounted && msg.isNotEmpty && app.pending.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
    await app.autoBackupIfDue();
  }

  @override
  Widget build(BuildContext context) {
    if (!app.flag('onboarded')) {
      return OnboardingScreen(onDone: () {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
      });
    }
    return ValueListenableBuilder<int>(
      valueListenable: app.tab,
      builder: (context, index, _) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          body: IndexedStack(index: index, children: _pages),
          bottomNavigationBar: _BottomBar(index: index),
        ),
      ),
    );
  }
}

/// Home · Activity · (+) · Insights · Plan, with the add button raised in the middle.
class _BottomBar extends StatelessWidget {
  final int index;
  const _BottomBar({required this.index});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    Widget item(int i, IconData icon, IconData activeIcon, String label, {int badge = 0}) {
      final on = index == i;
      return Expanded(
        child: InkWell(
          onTap: () => app.tab.value = i,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Badge(
              isLabelVisible: badge > 0,
              backgroundColor: c.secondary,
              textColor: c.onSecondary,
              label: Text('$badge'),
              child: Icon(on ? activeIcon : icon, color: on ? c.primary : c.muted),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? c.primary : c.muted)),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.divider))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(children: [
            item(0, Icons.home_outlined, Icons.home_rounded, tr('Home')),
            item(1, Icons.receipt_long_outlined, Icons.receipt_long, tr('Activity'), badge: app.pending.length),
            Expanded(
              child: Center(
                child: Semantics(
                  button: true,
                  label: tr('Add entry'),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QuickAddScreen())),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: c.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
                      ),
                      child: Icon(Icons.add, size: 28, color: c.onPrimary),
                    ),
                  ),
                ),
              ),
            ),
            item(2, Icons.insights_outlined, Icons.insights, tr('Insights')),
            item(3, Icons.event_available_outlined, Icons.event_available, tr('Plan')),
          ]),
        ),
      ),
    );
  }
}
