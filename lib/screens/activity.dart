import 'package:flutter/material.dart' hide Category;

import '../i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entries.dart';
import 'review.dart';
import 'settings.dart' show scanRange;

/// Review and Entries together: "To review" bank messages and "All entries".
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.activitySub,
      builder: (context, sub, _) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = lc;
          return Scaffold(
            body: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
                  child: Row(children: [
                    Expanded(child: Text(tr('Activity'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.text))),
                    if (sub == 0) ...[
                      if (app.scanning)
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else ...[
                        IconButton(tooltip: tr('Scan a date range'), icon: const Icon(Icons.date_range), onPressed: () => scanRange(context)),
                        IconButton(
                          tooltip: tr('Scan new SMS'),
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            final msg = await app.scanSms();
                            if (context.mounted && msg.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                            }
                          },
                        ),
                      ],
                    ] else ...[
                      const PeriodSwitcher(),
                      const SizedBox(width: 8),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentTabs(
                    selected: sub,
                    onSelect: (i) => app.activitySub.value = i,
                    labels: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr('To review')),
                        if (app.pending.isNotEmpty) ...[const SizedBox(width: 6), CountBadge(app.pending.length)],
                      ]),
                      Text(tr('All entries')),
                    ],
                  ),
                ),
                Expanded(child: IndexedStack(index: sub, children: const [ReviewScreen(), EntriesScreen()])),
              ]),
            ),
          );
        },
      ),
    );
  }
}
