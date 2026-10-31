import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'brand.dart';
import 'cloud.dart';
import 'i18n.dart';
import 'lock.dart';

import 'screens/activity.dart';
import 'screens/analytics.dart';
import 'screens/budget.dart';
import 'screens/home.dart';
import 'screens/onboarding.dart';
import 'screens/quick_add.dart';
import 'state.dart';
import 'theme.dart';
import 'tour.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  await AppLock.init();
  await Cloud.init();
  AppLock.lockNow(); // the PIN is asked for once the opening animation ends
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
        title: 'Shahri',
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
        home: const _Root(),
      );
      },
    );
  }
}

/// Shows the opening animation once per launch, then fades into the app.
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  static bool introShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AppLock.wentAway();
      Cloud.saveIfChanged(); // keep the cloud copy current whenever the app is left
    }
    if (state == AppLifecycleState.resumed) AppLock.cameBack();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) introShown = true;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.easeOut,
      child: introShown
          ? ValueListenableBuilder<bool>(
              valueListenable: AppLock.locked,
              builder: (context, locked, child) => Stack(children: [
                child!,
                if (locked) const Positioned.fill(child: LockScreen()),
              ]),
              child: const Shell(),
            )
          : ShahriIntro(onDone: () => setState(() => introShown = true)),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstRun();
      _autoTour();
    });
    app.tab.addListener(_autoTour);
    app.activitySub.addListener(_autoTour);
    Tours.request.addListener(_onTourRequest);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.tab.removeListener(_autoTour);
    app.activitySub.removeListener(_autoTour);
    Tours.request.removeListener(_onTourRequest);
    super.dispose();
  }

  static const _tabTours = {'home': 0, 'review': 1, 'entries': 1, 'insights': 2, 'plan': 3};

  String _tourForTab() => switch (app.tab.value) {
        0 => 'home',
        1 => app.activitySub.value == 0 ? 'review' : 'entries',
        2 => 'insights',
        _ => 'plan',
      };

  /// Plays the visible page's tour the first time it is shown (or when Help & tutorials asked for it).
  void _autoTour() {
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted || !app.flag('onboarded')) return;
      var id = _tourForTab();
      var force = false;
      final req = Tours.request.value;
      if (req != null && _tabTours.containsKey(req)) {
        Tours.request.value = null;
        id = req;
        force = true;
      }
      Tours.maybeStart(context, id, force: force);
    });
  }

  void _onTourRequest() {
    final r = Tours.request.value;
    if (r == null || !_tabTours.containsKey(r)) return;
    if (r == 'review') app.activitySub.value = 0;
    if (r == 'entries') app.activitySub.value = 1;
    app.tab.value = _tabTours[r]!;
    _autoTour();
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
    await Cloud.autoBackupIfDue();
  }

  @override
  Widget build(BuildContext context) {
    if (!app.flag('onboarded')) {
      return OnboardingScreen(onDone: () {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _firstRun();
          _autoTour();
        });
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
                    child: TourTarget(id: 'nav.add', child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: c.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: c.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
                      ),
                      child: Icon(Icons.add, size: 28, color: c.onPrimary),
                    )),
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
