// Guided page tours: a dimmed screen with a moving spotlight and a gold pulsing ring around
// one real widget at a time, plus a bubble with Skip / Next. Each page tour plays the first
// time the page is opened (unless switched off) and can be replayed with the ⓘ button.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand.dart' show brandGold;
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';

class TourStep {
  final String target, title, body;
  final double radius;
  const TourStep(this.target, this.title, this.body, {this.radius = 20});
}

class TourDef {
  final String id, name, requires;
  final IconData icon;
  final List<TourStep> steps;
  const TourDef(this.id, this.name, this.icon, this.requires, this.steps);
}

/// All tours. Built on demand so the texts follow the current language.
List<TourDef> tourDefs() => [
      TourDef('home', tr('Home'), Icons.home_outlined, 'home.hero', [
        TourStep('home.hero', tr('Left to spend this month'), tr('Your budget minus what you spent so far. It turns red if you go over.'), radius: 24),
        TourStep('home.strip', tr('New bank messages'), tr('Bank SMS land here. Tap to review them in a few seconds.'), radius: 18),
        TourStep('home.where', tr('Where your money went'), tr('Each category against its budget. Tap See all for the full picture.')),
        TourStep('home.coming', tr('Coming up'), tr('Bills and yearly expenses that are due soon, so nothing surprises you.')),
        TourStep('nav.add', tr('Add in one tap'), tr('Paid cash or no SMS came? Tap + to add it yourself.'), radius: 27),
        TourStep('info.home', tr('Replay any time'), tr('Tap ⓘ on any page to see its tour again.'), radius: 24),
      ]),
      TourDef('review', tr('To review'), Icons.mark_chat_unread_outlined, 'review.card', [
        TourStep('review.card', tr('Each bank SMS becomes a card'), tr('Amount, merchant, card and time are read for you.'), radius: 24),
        TourStep('review.amount', tr('Fix anything with a tap'), tr('Tap the amount or the merchant to correct it.'), radius: 12),
        TourStep('review.cats', tr('Pick a category'), tr('Your usual ones come first. With remember ticked, this merchant is sorted for you next time.'), radius: 12),
        TourStep('review.actions', tr('Confirm or skip'), tr('Confirm to count it. Not spending is for refunds and moves between your own accounts.'), radius: 16),
        TourStep('review.filter', tr('Filter by card'), tr('Show only one card\'s or account\'s messages.'), radius: 18),
        TourStep('info.activity', tr('Replay any time'), tr('Tap ⓘ to see this page\'s tour again.'), radius: 24),
      ]),
      TourDef('quickadd', tr('Quick add (+)'), Icons.add_circle_outline, 'qa.amount', [
        TourStep('qa.amount', tr('Type the amount'), tr('Use the number pad. Tap the amount any time to bring the pad back.'), radius: 16),
        TourStep('qa.merchant', tr('Where did you pay?'), tr('Pick a recent merchant or type one. Its usual category is picked for you.'), radius: 14),
        TourStep('qa.cats', tr('Choose a category'), tr('Tap one, or More for the full list.'), radius: 14),
        TourStep('qa.paid', tr('Paid from'), tr('Which card or account it came from, so each one\'s spending adds up.'), radius: 12),
        TourStep('qa.save', tr('Save'), tr('That\'s it. It shows up in your entries and budgets straight away.'), radius: 16),
      ]),
      TourDef('entries', tr('All entries'), Icons.receipt_long_outlined, 'entries.search', [
        TourStep('entries.search', tr('Search everything'), tr('Find entries by merchant, item, category or amount.'), radius: 14),
        TourStep('entries.filters', tr('Filter'), tr('Show only expenses or income, one account, entries with no account, or one category.'), radius: 18),
        TourStep('entries.list', tr('Your entries by day'), tr('Tap an entry to edit or delete it.'), radius: 18),
        TourStep('info.activity', tr('Replay any time'), tr('Tap ⓘ to see this page\'s tour again.'), radius: 24),
      ]),
      TourDef('insights', tr('Insights'), Icons.insights_outlined, 'ins.donut', [
        TourStep('ins.donut', tr('Where the money went'), tr('Your spending split by category for this period.')),
        TourStep('ins.tips', tr('What stands out'), tr('Budgets you\'re close to, unusual spending and what went well.'), radius: 18),
        TourStep('ins.top', tr('Top items'), tr('What you buy most. Tap an item to see all its entries.')),
        TourStep('info.insights', tr('Replay any time'), tr('Tap ⓘ to see this page\'s tour again.'), radius: 24),
      ]),
      TourDef('plan', tr('Plan'), Icons.event_note_outlined, 'plan.tabs', [
        TourStep('plan.tabs', tr('Three parts'), tr('Checklist for this month, Budgets per category, and the Template every month starts from.'), radius: 14),
        TourStep('plan.progress', tr('This month\'s plan'), tr('How much of your must-do list is done, and what\'s left for day-to-day spending.')),
        TourStep('plan.yearly', tr('Yearly expenses'), tr('School fees, insurance and the like. Set the due date and the app works out what to put aside each month.')),
        TourStep('plan.add', tr('Add to plan'), tr('Rent, fees, savings: anything that must happen each month.'), radius: 16),
        TourStep('info.plan', tr('Replay any time'), tr('Tap ⓘ to see this page\'s tour again.'), radius: 24),
      ]),
      TourDef('profile', tr('Profile & accounts'), Icons.person_outline, 'profile.add', [
        TourStep('profile.add', tr('Your accounts and cards'), tr('Add each card with its last 4 digits. Bank SMS are then matched to it automatically.'), radius: 20),
        TourStep('profile.backup', tr('Backup'), tr('Your entries live only on this phone. Turn on automatic backup to keep them safe.'), radius: 12),
        TourStep('profile.help', tr('Help & tutorials'), tr('Replay any tour from here.'), radius: 12),
      ]),
    ];

TourDef? tourDef(String id) {
  for (final d in tourDefs()) {
    if (d.id == id) return d;
  }
  return null;
}

/// Marks a widget as a tour target. [inset] removes outer margins so the spotlight hugs the visible box.
class TourTarget extends StatefulWidget {
  final String id;
  final EdgeInsets inset;
  final Widget child;
  const TourTarget({super.key, required this.id, this.inset = EdgeInsets.zero, required this.child});

  static final Map<String, _TourTargetState> _reg = {};

  static BuildContext? contextOf(String id) {
    final s = _reg[id];
    return s != null && s.mounted ? s.context : null;
  }

  static Rect? rectOf(String id) {
    final s = _reg[id];
    if (s == null || !s.mounted) return null;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final r = box.localToGlobal(Offset.zero) & box.size;
    return s.widget.inset.deflateRect(r);
  }

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  @override
  void initState() {
    super.initState();
    TourTarget._reg[widget.id] = this;
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (TourTarget._reg[old.id] == this) TourTarget._reg.remove(old.id);
      TourTarget._reg[widget.id] = this;
    }
  }

  @override
  void dispose() {
    if (TourTarget._reg[widget.id] == this) TourTarget._reg.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class Tours {
  static bool running = false;

  /// Set by Help & tutorials: the page that should play its tour as soon as it is shown.
  static final request = ValueNotifier<String?>(null);

  static bool get enabled => app.settings['toursOn'] != '0';
  static bool seen(String id) => app.flag('tour_$id');

  static Future<void> resetAll() async {
    for (final d in tourDefs()) {
      await app.setSetting('tour_${d.id}', '0');
    }
  }

  /// Plays [id] if it hasn't been seen yet (or [force]), once its main element is on screen.
  static Future<void> maybeStart(BuildContext context, String id, {bool force = false}) async {
    if (running || !app.flag('onboarded')) return;
    if (!force && (!enabled || seen(id))) return;
    final def = tourDef(id);
    if (def == null) return;
    final main = TourTarget.contextOf(def.requires);
    if (main == null) return; // e.g. nothing to review yet: try again on a later visit
    final route = ModalRoute.of(main);
    if (route != null && !route.isCurrent) return;
    final steps = def.steps.where((s) => TourTarget.contextOf(s.target) != null).toList();
    if (steps.isEmpty) return;
    running = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _TourOverlay(steps: steps),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    } finally {
      running = false;
      await app.setSetting('tour_$id', '1');
    }
  }
}

/// The ⓘ button that replays a page's tour.
class TourButton extends StatelessWidget {
  final String tour, target;
  const TourButton({super.key, required this.tour, required this.target});

  @override
  Widget build(BuildContext context) => TourTarget(
        id: target,
        inset: const EdgeInsets.all(4),
        child: IconButton(
          tooltip: tr('Page tour'),
          icon: Icon(Icons.info_outline, color: lc.primary),
          onPressed: () => Tours.maybeStart(context, tour, force: true),
        ),
      );
}

/// Starts a page's tour shortly after the page first appears (for pushed pages like Quick add and Profile).
class TourAutoStart extends StatefulWidget {
  final String tour;
  final Widget child;
  const TourAutoStart({super.key, required this.tour, required this.child});
  @override
  State<TourAutoStart> createState() => _TourAutoStartState();
}

class _TourAutoStartState extends State<TourAutoStart> {
  void _check({bool requested = false}) {
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      Tours.maybeStart(context, widget.tour, force: requested);
    });
  }

  void _onRequest() {
    if (Tours.request.value == widget.tour) {
      Tours.request.value = null;
      _check(requested: true);
    }
  }

  @override
  void initState() {
    super.initState();
    Tours.request.addListener(_onRequest);
    if (Tours.request.value == widget.tour) {
      _onRequest();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    Tours.request.removeListener(_onRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------- overlay

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  const _TourOverlay({required this.steps});
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  late final AnimationController move = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController bubble = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  int i = 0;
  Rect? from, to;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go(0));
  }

  @override
  void dispose() {
    move.dispose();
    pulse.dispose();
    bubble.dispose();
    super.dispose();
  }

  Future<void> _go(int n) async {
    if (busy) return;
    busy = true;
    try {
      while (n < widget.steps.length && TourTarget.contextOf(widget.steps[n].target) == null) {
        n++;
      }
      if (n >= widget.steps.length) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (to != null) await bubble.reverse();
      final id = widget.steps[n].target;
      final size = MediaQuery.of(context).size;
      final pad = MediaQuery.of(context).padding;
      var r = TourTarget.rectOf(id);
      final ctx = TourTarget.contextOf(id);
      final visible = r != null && r.top >= pad.top + 8 && r.bottom <= size.height - pad.bottom - 8;
      if (!visible && ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.25, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
        await WidgetsBinding.instance.endOfFrame;
        r = TourTarget.rectOf(id);
      }
      if (!mounted || r == null) return;
      setState(() {
        from = to ?? r;
        to = r;
        i = n;
      });
      await move.forward(from: 0);
      if (mounted) await bubble.forward(from: 0);
    } finally {
      busy = false;
    }
  }

  void _next() => i + 1 >= widget.steps.length ? Navigator.pop(context) : _go(i + 1);

  @override
  Widget build(BuildContext context) {
    final c = lc;
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    final step = widget.steps[i];
    final last = i == widget.steps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _next,
            child: AnimatedBuilder(
              animation: Listenable.merge([move, pulse]),
              builder: (context, _) {
                final rect = (from == null || to == null)
                    ? null
                    : Rect.lerp(from, to, Curves.easeInOutCubic.transform(move.value));
                return CustomPaint(painter: _SpotPainter(rect: rect, radius: step.radius, pulse: pulse.value, dim: c.dark ? 0.72 : 0.62));
              },
            ),
          ),
        ),
        if (to != null) _bubble(context, step, last, size, pad),
      ]),
    );
  }

  Widget _bubble(BuildContext context, TourStep step, bool last, Size size, EdgeInsets pad) {
    final c = lc;
    final r = to!;
    const gap = 22.0, approx = 190.0;
    final below = r.bottom + gap + approx <= size.height - pad.bottom;
    final above = !below && r.top - gap - approx >= pad.top;
    final arrowX = (r.center.dx - 16 - 7).clamp(18.0, size.width - 32 - 32);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('{a} of {b}', {'a': i + 1, 'b': widget.steps.length}).toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFC2701A), letterSpacing: 0.4)),
        const SizedBox(height: 4),
        Text(step.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(step.body, style: TextStyle(fontSize: 14, height: 1.45, color: c.muted)),
        const SizedBox(height: 10),
        Row(children: [
          for (var k = 0; k < widget.steps.length; k++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsetsDirectional.only(end: 4),
              width: k == i ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(color: k == i ? c.primary : c.outline, borderRadius: BorderRadius.circular(3)),
            ),
          const Spacer(),
          if (!last) TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Skip'), style: TextStyle(color: c.muted))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 18)),
            onPressed: _next,
            child: Text(tr(last ? 'Got it' : 'Next')),
          ),
        ]),
      ]),
    );
    final arrow = Positioned(
      left: arrowX,
      top: below ? -6 : null,
      bottom: below ? null : -6,
      child: Transform.rotate(angle: math.pi / 4, child: Container(width: 14, height: 14, color: c.card)),
    );
    final body = Stack(clipBehavior: Clip.none, children: [card, if (below || above) arrow]);
    return Positioned(
      left: 16,
      right: 16,
      top: below ? r.bottom + gap : null,
      bottom: below ? null : above ? size.height - r.top + gap : pad.bottom + 16,
      child: FadeTransition(
        opacity: bubble,
        child: AnimatedBuilder(
          animation: bubble,
          child: body,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (below ? 8 : -8) * (1 - Curves.easeOut.transform(bubble.value))),
            child: Transform.scale(scale: 0.97 + 0.03 * bubble.value, child: child),
          ),
        ),
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  final Rect? rect;
  final double radius, pulse, dim;
  _SpotPainter({required this.rect, required this.radius, required this.pulse, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final shade = Paint()..color = Color.fromRGBO(8, 22, 18, dim);
    if (rect == null) {
      canvas.drawPath(full, shade);
      return;
    }
    const pad = 8.0;
    final hole = RRect.fromRectAndRadius(rect!.inflate(pad), Radius.circular(radius + pad));
    canvas.drawPath(Path.combine(PathOperation.difference, full, Path()..addRRect(hole)), shade);
    // steady gold ring, plus one that grows out and fades
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = brandGold;
    canvas.drawRRect(hole.inflate(3), ring);
    final p = Curves.easeOut.transform(pulse);
    canvas.drawRRect(hole.inflate(3 + 7 * p), ring..color = brandGold.withOpacity(0.7 * (1 - p)));
  }

  @override
  bool shouldRepaint(_SpotPainter o) => o.rect != rect || o.pulse != pulse || o.radius != radius;
}
