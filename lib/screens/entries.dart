import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../widgets.dart';
import '../theme.dart';
import '../tour.dart';
import 'home.dart' show EntryRow;
import 'profile.dart' show accountIcon;

class EntriesScreen extends StatefulWidget {
  const EntriesScreen({super.key});
  @override
  State<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends State<EntriesScreen> {
  String query = '';
  int? categoryFilter;
  int? accountFilter;
  String kindFilter = 'all';
  final searchCtl = TextEditingController();

  void _external() {
    if (app.entrySearch.value.isEmpty) return;
    setState(() {
      searchCtl.text = app.entrySearch.value;
      query = app.entrySearch.value;
    });
    app.entrySearch.value = '';
  }

  @override
  void initState() {
    super.initState();
    app.entrySearch.addListener(_external);
    WidgetsBinding.instance.addPostFrameCallback((_) => _external());
  }

  @override
  void dispose() {
    app.entrySearch.removeListener(_external);
    searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final s = statsFor(app.period);
        final q = query.trim().toLowerCase();
        final list = s.list.where((t) {
          if (kindFilter != 'all' && t.kind != kindFilter) return false;
          if (categoryFilter != null && t.categoryId != categoryFilter) return false;
          if (accountFilter == -1 && app.account(t.accountId) != null) return false; // -1 = no account
          if (accountFilter != null && accountFilter != -1 && t.accountId != accountFilter) return false;
          if (q.isEmpty) return true;
          final c = '${app.cat(t.categoryId)?.name.toLowerCase() ?? ''} ${app.cat(t.categoryId)?.display.toLowerCase() ?? ''}';
          return t.merchant.toLowerCase().contains(q) || t.note.toLowerCase().contains(q) || c.contains(q) ||
              fmtAuto(t.amount).replaceAll(',', '').contains(q);
        }).toList();
        final total = list.fold<double>(0, (a, t) => a + (t.kind == 'income' ? t.amount : -t.amount));

        final c = lc;
        final now = DateTime.now();
        String dayLabel(String iso) {
          final d = parseIso(iso);
          final today = DateTime(now.year, now.month, now.day);
          final diff = today.difference(d).inDays;
          if (diff == 0) return tr('Today');
          if (diff == 1) return tr('Yesterday');
          return '${weekdayShort(d)}, ${shortDate(d)}';
        }
        final rows = <Widget>[];
        var i = 0;
        while (i < list.length) {
          final day = list[i].date;
          final group = <Txn>[];
          while (i < list.length && list[i].date == day) {
            group.add(list[i]);
            i++;
          }
          final net = group.fold<double>(0, (a, x) => a + (x.kind == 'income' ? x.amount : -x.amount));
          rows.add(Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(children: [
              Expanded(child: Text(dayLabel(day), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.muted))),
              Text(ltr('${net >= 0 ? '+' : '−'}${fmtAuto(net.abs())}'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.muted, fontFeatures: tabular)),
            ]),
          ));
          rows.add(Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [for (final t in group) EntryRow(t, showDate: false)]),
          ));
        }

        // the first day's card is what the tour points at
        if (rows.length >= 2) rows[1] = TourTarget(id: 'entries.list', inset: const EdgeInsets.symmetric(horizontal: 16), child: rows[1]);

        return Container(
          color: c.bg,
          child: Column(children: [
            TourTarget(id: 'entries.search', inset: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: searchCtl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Search merchant, item, category or amount'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr('Clear'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            searchCtl.clear();
                            query = '';
                          }),
                        ),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            )),
            TourTarget(id: 'entries.filters', inset: const EdgeInsets.symmetric(horizontal: 12), child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final k in const [('all', 'All'), ('expense', 'Expenses'), ('income', 'Income')])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(tr(k.$2)),
                      selected: kindFilter == k.$1,
                      onSelected: (_) => setState(() => kindFilter = k.$1),
                    ),
                  ),
                if (app.activeAccounts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: InputChip(
                      label: Text(accountFilter == null
                          ? tr('Any account')
                          : accountFilter == -1
                              ? tr('No account')
                              : app.account(accountFilter)?.name ?? ''),
                      avatar: Icon(
                          accountFilter == null || accountFilter == -1
                              ? Icons.credit_card
                              : accountIcon(app.account(accountFilter)?.type ?? 'bank'),
                          size: 18),
                      onDeleted: accountFilter == null ? null : () => setState(() => accountFilter = null),
                      onPressed: () async {
                        final id = await showModalBottomSheet<int>(
                          context: context,
                          builder: (c) => SafeArea(
                            child: ListView(shrinkWrap: true, children: [
                              for (final a in app.activeAccounts)
                                ListTile(
                                  leading: Icon(accountIcon(a.type)),
                                  title: Text(a.name),
                                  onTap: () => Navigator.pop(c, a.id),
                                ),
                              ListTile(
                                leading: const Icon(Icons.help_outline),
                                title: const T('No account'),
                                subtitle: const T('Entries not linked to any account yet'),
                                onTap: () => Navigator.pop(c, -1),
                              ),
                            ]),
                          ),
                        );
                        if (id != null) setState(() => accountFilter = id);
                      },
                    ),
                  ),
                InputChip(
                  label: Text(categoryFilter == null ? tr('Any category') : app.cat(categoryFilter!)?.display ?? tr('Category')),
                  avatar: const Icon(Icons.filter_list, size: 18),
                  onDeleted: categoryFilter == null ? null : () => setState(() => categoryFilter = null),
                  onPressed: () async {
                    final id = await showModalBottomSheet<int>(
                      context: context,
                      isScrollControlled: true,
                      builder: (c) => SafeArea(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
                          child: ListView(shrinkWrap: true, children: [
                            for (final cat in app.categories.where((x) => !x.archived))
                              ListTile(
                                leading: CategoryDot(cat.color, size: 12),
                                title: Text(cat.display),
                                trailing: Text(cat.kind == 'income' ? tr('Income') : ''),
                                onTap: () => Navigator.pop(c, cat.id),
                              ),
                          ]),
                        ),
                      ),
                    );
                    if (id != null) setState(() => categoryFilter = id);
                  },
                ),
              ]),
            )),
            if (accountFilter == -1 && list.isNotEmpty && app.activeAccounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.credit_card),
                  label: Text(trn(list.length, 'Assign this entry to an account', 'Assign these {n} entries to an account')),
                  onPressed: () async {
                    final id = await showModalBottomSheet<int>(
                      context: context,
                      builder: (c) => SafeArea(
                        child: ListView(shrinkWrap: true, children: [
                          for (final a in app.activeAccounts)
                            ListTile(leading: Icon(accountIcon(a.type)), title: Text(a.name), onTap: () => Navigator.pop(c, a.id)),
                        ]),
                      ),
                    );
                    if (id == null) return;
                    final n = list.length;
                    await app.assignAccount(list, id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('{n} entries moved to {a}.', {'n': n, 'a': app.account(id)?.name ?? ''}))));
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Text(trn(list.length, '{n} entry', '{n} entries'), style: TextStyle(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text(tr('Net {a} {cur}', {'a': fmt(total), 'cur': app.currency}), style: TextStyle(color: cs.onSurfaceVariant, fontFeatures: tabular)),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          s.list.isEmpty
                              ? tr('No entries in {m}. Tap + to add one, or confirm SMS in Review.', {'m': app.period.label})
                              : tr('No entries match these filters.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
            ),
          ]),
        );
      },
    );
  }
}
