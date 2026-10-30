import 'package:flutter/material.dart' hide Category;

import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../tour.dart';
import 'quick_add.dart';

/// Profile → Help & tutorials: every page tour, whether it was seen, replay one or all.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  void _play(BuildContext context, String id) {
    final nav = Navigator.of(context);
    if (id == 'profile') {
      Tours.request.value = id;
      nav.pop(); // back to Profile, which plays its tour
      return;
    }
    nav.popUntil((r) => r.isFirst);
    Tours.request.value = id;
    if (id == 'quickadd') {
      nav.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QuickAddScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = lc;
        final defs = tourDefs();
        return Scaffold(
          appBar: AppBar(title: const T('Help & tutorials')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.heroChip, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.info_outline, color: Color(0xFFF0A848)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    T('Learn each page', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.heroText)),
                    const SizedBox(height: 2),
                    T('Short guided tours. You can also tap ⓘ at the top of any page.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: c.heroSub)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Material(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                value: Tours.enabled,
                onChanged: (v) => app.setSetting('toursOn', v ? '1' : '0'),
                title: const T('Show tours on first visit'),
                subtitle: const T('Each page explains itself the first time you open it'),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                for (final (k, d) in defs.indexed) ...[
                  if (k > 0) Divider(height: 1, indent: 66, color: c.divider),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(d.icon, size: 20, color: c.onPrimarySoft),
                    ),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text.rich(TextSpan(children: [
                      TextSpan(text: '${tr('{n} steps', {'n': d.steps.length})} · '),
                      Tours.seen(d.id)
                          ? TextSpan(text: tr('Seen'))
                          : TextSpan(text: tr('Not seen yet'), style: const TextStyle(color: Color(0xFFC2701A), fontWeight: FontWeight.w600)),
                    ])),
                    trailing: IconButton.filled(
                      tooltip: tr('Play'),
                      style: IconButton.styleFrom(
                        backgroundColor: Tours.seen(d.id) ? c.raised : c.primary,
                        foregroundColor: Tours.seen(d.id) ? c.primary : c.onPrimary,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                      onPressed: () => _play(context, d.id),
                    ),
                    onTap: () => _play(context, d.id),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.replay),
              label: const T('Replay all tours'),
              onPressed: () async {
                await Tours.resetAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Each page will show its tour again the next time you open it.'))));
                }
              },
            ),
            const SizedBox(height: 6),
            T('Handy before handing the phone to someone new', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.muted)),
          ]),
        );
      },
    );
  }
}
