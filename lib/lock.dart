// App lock: a 4-digit PIN (stored only as a salted hash) with optional fingerprint / face unlock.
// Locks when the app opens and when it comes back after more than 30 seconds in the background.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'i18n.dart';
import 'native.dart';
import 'state.dart';
import 'theme.dart';

class AppLock {
  /// Settings that belong to this phone only: never exported in a backup or taken from one.
  static const keys = ['lockOn', 'pinHash', 'pinSalt', 'lockBio'];
  static final locked = ValueNotifier<bool>(false);
  static DateTime? _away;
  static bool bioAvailable = false;

  static bool get enabled => app.settings['lockOn'] == '1' && (app.settings['pinHash'] ?? '').isNotEmpty;
  static bool get useBio => enabled && app.settings['lockBio'] == '1' && bioAvailable;

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> init() async => bioAvailable = await Native.biometricAvailable();

  static Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await app.setSetting('pinSalt', salt, notify: false);
    await app.setSetting('pinHash', _hash(pin, salt), notify: false);
    await app.setSetting('lockOn', '1');
  }

  static bool check(String pin) => _hash(pin, app.settings['pinSalt'] ?? '') == app.settings['pinHash'];

  static Future<void> turnOff() async {
    await app.setSetting('pinHash', '', notify: false);
    await app.setSetting('pinSalt', '', notify: false);
    await app.setSetting('lockBio', '0', notify: false);
    await app.setSetting('lockOn', '0');
  }

  static void lockNow() {
    if (enabled) locked.value = true;
  }

  static void wentAway() => _away ??= DateTime.now();
  static void cameBack() {
    final a = _away;
    _away = null;
    if (a != null && DateTime.now().difference(a).inSeconds >= 30) lockNow();
  }

  static Future<bool> biometric() => Native.authenticate(
        title: tr('Unlock Shahri'),
        subtitle: tr('Use your fingerprint or face'),
        cancel: tr('Use PIN'),
      );
}

/// Full-screen PIN pad. [onDone] gets the 4 digits.
class _PinPad extends StatelessWidget {
  final int length;
  final String entered;
  final bool error;
  final ValueChanged<String> onKey;
  final VoidCallback? onBio;
  const _PinPad({required this.entered, required this.onKey, this.length = 4, this.error = false, this.onBio});

  @override
  Widget build(BuildContext context) {
    final c = lc;
    Widget key(String k) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: k.isEmpty
                ? const SizedBox(height: 64)
                : Material(
                    color: k == 'bio' || k == 'del' ? Colors.transparent : c.card,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => k == 'bio' ? onBio?.call() : onKey(k),
                      child: SizedBox(
                        height: 64,
                        child: Center(
                          child: k == 'del'
                              ? Icon(Icons.backspace_outlined, color: c.text, semanticLabel: tr('Delete'))
                              : k == 'bio'
                                  ? Icon(Icons.fingerprint, size: 34, color: c.primary, semanticLabel: tr('Use fingerprint'))
                                  : Text(k, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.text)),
                        ),
                      ),
                    ),
                  ),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 9),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: error ? c.bad : (i < entered.length ? c.primary : Colors.transparent),
                border: Border.all(color: error ? c.bad : c.primary, width: 2),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 28),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], [onBio != null ? 'bio' : '', '0', 'del']])
            Row(children: [for (final k in row) key(k)]),
        ]),
      ),
    ]);
  }
}

/// Shown over the app while it is locked.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  String pin = '';
  bool error = false;
  int wrong = 0;
  DateTime? waitUntil;
  late final AnimationController shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    if (AppLock.useBio) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  @override
  void dispose() {
    shake.dispose();
    super.dispose();
  }

  Future<void> _bio() async {
    if (await AppLock.biometric()) _unlock();
  }

  void _unlock() {
    HapticFeedback.lightImpact();
    AppLock.locked.value = false;
  }

  void _key(String k) {
    if (waitUntil != null && DateTime.now().isBefore(waitUntil!)) return;
    setState(() {
      error = false;
      if (k == 'del') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
        return;
      }
      if (pin.length < 4) pin += k;
    });
    if (pin.length == 4) {
      if (AppLock.check(pin)) {
        _unlock();
      } else {
        HapticFeedback.heavyImpact();
        shake.forward(from: 0);
        setState(() {
          error = true;
          pin = '';
          wrong++;
          if (wrong >= 5) {
            waitUntil = DateTime.now().add(const Duration(seconds: 30));
            wrong = 0;
            Future.delayed(const Duration(seconds: 30), () {
              if (mounted) setState(() => waitUntil = null);
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final waiting = waitUntil != null && DateTime.now().isBefore(waitUntil!);
    return PopScope(
      canPop: false,
      child: Material(
        color: c.bg,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BrandTile(size: 76),
                const SizedBox(height: 16),
                const Directionality(textDirection: TextDirection.ltr, child: Wordmark(height: 30)),
                const SizedBox(height: 28),
                Text(
                  waiting
                      ? tr('Too many tries. Wait 30 seconds.')
                      : error
                          ? tr('Wrong PIN, try again')
                          : tr('Enter your PIN'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: error || waiting ? c.bad : c.text),
                ),
                const SizedBox(height: 18),
                AnimatedBuilder(
                  animation: shake,
                  builder: (context, child) => Transform.translate(offset: Offset(12 * sin(shake.value * pi * 5) * (1 - shake.value), 0), child: child),
                  child: _PinPad(entered: pin, error: error, onKey: _key, onBio: AppLock.useBio ? _bio : null),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const T('Forgot your PIN?'),
                      content: const T(
                          'For your privacy the PIN can\'t be recovered. Unlock with your fingerprint if it is on. Otherwise clear the app\'s data in Android settings and restore your latest backup.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const T('OK'))],
                    ),
                  ),
                  child: const T('Forgot PIN?'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Create (or change) the PIN: enter it twice. Returns true when saved.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String first = '', pin = '';
  bool mismatch = false;

  void _key(String k) {
    setState(() {
      mismatch = false;
      if (k == 'del') {
        if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1);
        return;
      }
      if (pin.length < 4) pin += k;
    });
    if (pin.length < 4) return;
    if (first.isEmpty) {
      setState(() {
        first = pin;
        pin = '';
      });
    } else if (pin == first) {
      AppLock.setPin(pin).then((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        mismatch = true;
        first = '';
        pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    return Scaffold(
      appBar: AppBar(title: const T('Set a PIN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 44, color: c.primary),
            const SizedBox(height: 14),
            Text(
              mismatch ? tr('The PINs didn\'t match. Start again.') : tr(first.isEmpty ? 'Choose a 4-digit PIN' : 'Enter it again to confirm'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: mismatch ? c.bad : c.text),
            ),
            const SizedBox(height: 22),
            _PinPad(entered: pin, error: mismatch, onKey: _key),
          ]),
        ),
      ),
    );
  }
}

/// Settings rows for the app lock (used in Settings and Profile).
List<Widget> appLockTiles(BuildContext context) => [
      SwitchListTile(
        secondary: const Icon(Icons.lock_outline),
        title: const T('App lock'),
        subtitle: const T('Ask for a PIN when the app opens'),
        value: AppLock.enabled,
        onChanged: (v) async {
          if (v) {
            await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PinSetupScreen()));
          } else {
            await AppLock.turnOff();
          }
        },
      ),
      if (AppLock.enabled && AppLock.bioAvailable)
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const T('Unlock with fingerprint'),
          subtitle: const T('Or face unlock, if your phone has it'),
          value: app.settings['lockBio'] == '1',
          onChanged: (v) async {
            if (v && !await AppLock.biometric()) return;
            await app.setSetting('lockBio', v ? '1' : '0');
          },
        ),
      if (AppLock.enabled)
        ListTile(
          leading: const Icon(Icons.pin_outlined),
          title: const T('Change PIN'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const PinSetupScreen())),
        ),
    ];
