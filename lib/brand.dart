// Shahri brand pieces: the wallet icon, the "Shahri | شهري" wordmark with gold dots,
// the opening animation and a few small entrance helpers used by the welcome steps.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand_paths.dart';
import 'i18n.dart';
import 'theme.dart';

const brandGold = Color(0xFFE8912D);
const brandGoldDeep = Color(0xFF8A4E06);
const brandGoldOnDark = Color(0xFFF0A848);
const brandGoldOnLight = Color(0xFFD9821F);

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

Path _path(List<double> ops) {
  final p = Path();
  var i = 0;
  while (i < ops.length) {
    switch (ops[i++].toInt()) {
      case 0:
        p.moveTo(ops[i], ops[i + 1]);
        i += 2;
      case 1:
        p.lineTo(ops[i], ops[i + 1]);
        i += 2;
      case 2:
        p.quadraticBezierTo(ops[i], ops[i + 1], ops[i + 2], ops[i + 3]);
        i += 4;
      case 3:
        p.cubicTo(ops[i], ops[i + 1], ops[i + 2], ops[i + 3], ops[i + 4], ops[i + 5]);
        i += 6;
      default:
        p.close();
    }
  }
  return p;
}

final Path _en = _path(wmEnglish);
final Path _ar = _path(wmArabic);
final List<Path> _dots = [for (final d in wmDots) _path(d)];

/// Vertical offset (font units) of a dropping dot: falls, bounces once, settles.
double _dropY(double p) {
  if (p < 0.55) {
    final q = p / 0.55;
    return -300 * (1 - q * q);
  }
  if (p < 0.78) {
    final q = (p - 0.55) / 0.23;
    return -70 * math.sin(q * math.pi / 2);
  }
  final q = (p - 0.78) / 0.22;
  return -70 * (1 - q * q);
}

// ---------------------------------------------------------------- wordmark

class WordmarkPainter extends CustomPainter {
  final Color ink, arInk, dot, divider;
  final double reveal, line;
  final List<double> dots; // 0..1 per dot, in drop order
  WordmarkPainter({
    required this.ink,
    required this.arInk,
    required this.dot,
    required this.divider,
    this.reveal = 1,
    this.line = 1,
    this.dots = const [1, 1, 1, 1, 1, 1],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / wmHeight;
    canvas.save();
    canvas.scale(s);
    canvas.translate(-wmLeft, -wmTop);
    final fill = Paint()..isAntiAlias = true;
    // English writes in from the left, Arabic from the right
    if (reveal > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(wmLeft, wmTop, wmLeft + (wmEnRight - wmLeft + 60) * reveal, wmTop + wmHeight));
      canvas.drawPath(_en, fill..color = ink);
      canvas.restore();
      final right = wmLeft + wmWidth;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(right - (right - wmArLeft + 60) * reveal, wmTop, right, wmTop + wmHeight));
      canvas.drawPath(_ar, fill..color = arInk);
      canvas.restore();
    }
    if (line > 0) {
      final h = wmDividerHeight * line;
      final cy = wmDividerTop + wmDividerHeight / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(wmDividerX, cy - h / 2, wmDividerWidth, h), const Radius.circular(22)),
        Paint()..color = divider.withOpacity(0.4),
      );
    }
    for (var k = 0; k < _dots.length; k++) {
      final p = k < dots.length ? dots[k] : 1.0;
      if (p <= 0) continue;
      canvas.save();
      canvas.translate(0, p >= 1 ? 0 : _dropY(p));
      canvas.drawPath(_dots[k], Paint()..color = dot.withOpacity((p * 6).clamp(0.0, 1.0).toDouble()));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WordmarkPainter old) =>
      old.reveal != reveal || old.line != line || old.dots != dots || old.ink != ink || old.dot != dot;
}

/// The "Shahri | شهري" title. [progress] null = fully drawn; 0..1 runs the write-in + dot drop.
class Wordmark extends StatelessWidget {
  final double height;
  final Color? ink, arInk, dot, divider;
  final double? progress;
  const Wordmark({super.key, this.height = 40, this.ink, this.arInk, this.dot, this.divider, this.progress});

  static WordmarkPainter painterAt(double t, {required Color ink, required Color arInk, required Color dot, required Color divider}) {
    // timeline within the wordmark's own 0..1
    return WordmarkPainter(
      ink: ink,
      arInk: arInk,
      dot: dot,
      divider: divider,
      line: Curves.easeOut.transform(_seg(t, 0, 0.15)),
      reveal: Curves.easeInOut.transform(_seg(t, 0.05, 0.45)),
      dots: [for (var k = 0; k < 6; k++) _seg(t, 0.42 + k * 0.08, 0.42 + k * 0.08 + 0.18)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final i = ink ?? c.text;
    final painter = progress == null
        ? WordmarkPainter(ink: i, arInk: arInk ?? c.primary, dot: dot ?? brandGoldOnLight, divider: divider ?? i)
        : painterAt(progress!, ink: i, arInk: arInk ?? c.primary, dot: dot ?? brandGoldOnLight, divider: divider ?? i);
    return Semantics(
      label: 'Shahri شهري',
      child: SizedBox(
        height: height,
        width: height * wmWidth / wmHeight,
        child: CustomPaint(painter: painter),
      ),
    );
  }
}

// ---------------------------------------------------------------- wallet

class WalletPainter extends CustomPainter {
  /// Background the art sits on (used to outline the coin).
  final Color bg;
  final bool dark, tile;
  final double wallet, note1, note2, coin;
  WalletPainter({required this.bg, this.dark = false, this.tile = false, this.wallet = 1, this.note1 = 1, this.note2 = 1, this.coin = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final fg = dark ? const Color(0xFFF1F5F3) : Colors.white;
    final stitch = dark ? const Color(0xFF8FBFB0) : const Color(0xFF9CCFC0);
    final strap = dark ? const Color(0xFFBDEBDD) : const Color(0xFFDDF0EA);
    final accent = dark ? brandGoldOnDark : brandGold;
    final deep = dark ? const Color(0xFF6B3F07) : brandGoldDeep;
    final note = dark ? const Color(0xFFBDEBDD) : const Color(0xFFCFEBDD);
    final noteLine = dark ? const Color(0xFF2E7A63) : const Color(0xFF3E8C74);

    canvas.save();
    if (tile) {
      canvas.scale(size.width / 100);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(24)), Paint()..color = bg);
    } else {
      // art spans about x 8..96, y 6..94
      canvas.scale(size.width / 88);
      canvas.translate(-8, -6);
    }
    final p = Paint()..isAntiAlias = true;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // banknotes rise out of the wallet (drawn first so the wallet hides them)
    final n1 = Curves.easeOutCubic.transform(note1);
    if (note1 > 0) {
      canvas.save();
      canvas.translate(0, 24 * (1 - n1));
      canvas.translate(47, 30);
      canvas.rotate(-10 * math.pi / 180);
      canvas.translate(-47, -30);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(25, 16, 44, 26), const Radius.circular(4)), p..color = accent);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(29, 20, 36, 18), const Radius.circular(2.5)), line..color = deep);
      canvas.restore();
    }
    final n2 = Curves.easeOutCubic.transform(note2);
    if (note2 > 0) {
      canvas.save();
      canvas.translate(0, 24 * (1 - n2));
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 21, 46, 26), const Radius.circular(4)), p..color = note);
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 25, 38, 18), const Radius.circular(2.5)), line..color = noteLine);
      canvas.drawCircle(const Offset(53, 32), 4.2, p..color = noteLine);
      canvas.restore();
    }

    // wallet body
    if (wallet > 0) {
      final w = Curves.easeOutBack.transform(wallet);
      canvas.saveLayer(null, Paint()..color = Colors.white.withOpacity(wallet.clamp(0.0, 1.0).toDouble()));
      canvas.translate(50, 60);
      canvas.scale(0.9 + 0.1 * w);
      canvas.translate(-50, -60 + 8 * (1 - w));
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 36, 72, 48), const Radius.circular(12)), p..color = fg);
      final dash = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(19, 41, 62, 38), const Radius.circular(8)));
      final st = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = stitch;
      for (final m in dash.computeMetrics()) {
        for (double d = 0; d < m.length; d += 5.6) {
          canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), st);
        }
      }
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(58, 50, 32, 20), const Radius.circular(10)), p..color = strap);
      canvas.drawCircle(const Offset(68, 60), 5.2, p..color = accent);
      canvas.drawCircle(const Offset(68, 60), 2.2, p..color = deep);
      canvas.restore();
    }

    // gold $ coin drops in with a half spin and a small bounce
    if (coin > 0) {
      double y, sx;
      if (coin < 0.5) {
        final q = coin / 0.5;
        y = -60 * (1 - q * q);
        sx = 1 - 0.88 * math.sin(q * math.pi);
      } else if (coin < 0.75) {
        y = -7 * math.sin((coin - 0.5) / 0.25 * math.pi / 2);
        sx = 1;
      } else {
        final q = (coin - 0.75) / 0.25;
        y = -7 * (1 - q * q);
        sx = 1;
      }
      canvas.save();
      canvas.translate(30, 72 + y);
      canvas.scale(sx, 1);
      canvas.drawCircle(Offset.zero, 14 + 1.25, p..color = bg);
      canvas.drawCircle(Offset.zero, 14 - 1.25, p..color = accent);
      canvas.drawCircle(Offset.zero, 10.5, line
        ..color = deep
        ..strokeWidth = 1.5);
      final tp = TextPainter(
        text: TextSpan(text: r'$', style: TextStyle(fontFamily: 'IBMPlexSansArabic', fontWeight: FontWeight.w700, fontSize: 17, color: deep, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 + 0.5));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(WalletPainter o) =>
      o.wallet != wallet || o.note1 != note1 || o.note2 != note2 || o.coin != coin || o.bg != bg || o.dark != dark;
}

/// The app icon as a widget: green rounded tile with the wallet. [progress] null = static.
class BrandTile extends StatelessWidget {
  final double size;
  final double? progress;
  const BrandTile({super.key, this.size = 96, this.progress});

  @override
  Widget build(BuildContext context) {
    final t = progress;
    final pop = t == null ? 1.0 : Curves.easeOutBack.transform(_seg(t, 0, 0.35));
    final painter = WalletPainter(
      bg: lightColors.hero,
      tile: true,
      coin: t == null ? 1 : _seg(t, 0.35, 0.8),
    );
    return Opacity(
      opacity: t == null ? 1 : _seg(t, 0, 0.15),
      child: Transform.scale(
        scale: t == null ? 1 : 0.55 + 0.45 * pop,
        child: SizedBox.square(dimension: size, child: CustomPaint(painter: painter)),
      ),
    );
  }
}

// ---------------------------------------------------------------- opening animation

/// Plays once at launch on the brand green: wallet rises, notes slide out, the $ coin drops in,
/// the title writes in and its gold dots drop, then the slogan. Calls [onDone] at the end.
class ShahriIntro extends StatefulWidget {
  final VoidCallback onDone;
  const ShahriIntro({super.key, required this.onDone});
  @override
  State<ShahriIntro> createState() => _ShahriIntroState();
}

class _ShahriIntroState extends State<ShahriIntro> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    c.forward().whenComplete(() => Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted) widget.onDone();
        }));
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final col = lc;
    final dark = col.hero != lightColors.hero;
    final text = col.heroText;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: col.hero,
        child: Center(
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final t = c.value;
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox.square(
                  dimension: 180,
                  child: CustomPaint(
                    painter: WalletPainter(
                      bg: col.hero,
                      dark: dark,
                      wallet: _seg(t, 0, 0.2),
                      note1: _seg(t, 0.16, 0.38),
                      note2: _seg(t, 0.22, 0.44),
                      coin: _seg(t, 0.28, 0.55),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SizedBox(
                    height: 50,
                    width: 50 * wmWidth / wmHeight,
                    child: CustomPaint(
                      painter: Wordmark.painterAt(_seg(t, 0.4, 0.96),
                          ink: text, arInk: text, dot: brandGoldOnDark, divider: text),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: _seg(t, 0.82, 1) * 0.88,
                  child: Text(tr('Your month, under control'),
                      style: TextStyle(color: text, fontSize: lang == 'ar' ? 17 : 15.5, fontWeight: FontWeight.w500)),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- entrance helpers

/// Fades and floats its child up after [delay]; plays once when first built.
class Entrance extends StatefulWidget {
  final Widget child;
  final int delay; // ms
  final double dy;
  const Entrance({super.key, required this.child, this.delay = 0, this.dy = 18});
  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) {
          final v = Curves.easeOutCubic.transform(c.value);
          return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, widget.dy * (1 - v)), child: child));
        },
      );
}

/// Runs a 0..1 animation once over [ms] and hands the value to [builder]. Tap to replay if [replay].
class Play extends StatefulWidget {
  final int ms, delay;
  final bool replay;
  final Widget Function(BuildContext, double) builder;
  const Play({super.key, required this.ms, this.delay = 0, this.replay = false, required this.builder});
  @override
  State<Play> createState() => _PlayState();
}

class _PlayState extends State<Play> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = AnimatedBuilder(animation: c, builder: (context, _) => widget.builder(context, c.value));
    if (!widget.replay) return w;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => c.forward(from: 0), child: w);
  }
}

double brandSeg(double t, double a, double b) => _seg(t, a, b);
