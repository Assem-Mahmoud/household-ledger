import 'package:flutter/material.dart' hide Category;

import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../periods.dart';
import '../state.dart';
import '../stats.dart';
import '../widgets.dart';
import 'entry_form.dart';
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
          if (accountFilter != null && t.accountId != accountFilter) return false;
          if (q.isEmpty) return true;
          final c = '${app.cat(t.categoryId)?.name.toLowerCase() ?? ''} ${app.cat(t.categoryId)?.display.toLowerCase() ?? ''}';
          return t.merchant.toLowerCase().contains(q) || t.note.toLowerCase().contains(q) || c.contains(q) ||
              fmtAuto(t.amount).replaceAll(',', '').contains(q);
        }).toList();
        final total = list.fold<double>(0, (a, t) => a + (t.kind == 'income' ? t.amount : -t.amount));

        final rows = <Widget>[];
        String? lastDate;
        for (final t in list) {
          if (t.date != lastDate) {
            lastDate = t.date;
            final d = parseIso(t.date);
            final dayTotal = list.where((x) => x.date == t.date && x.kind == 'expense').fold<double>(0, (a, x) => a + x.amount);
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(children: [
                Expanded(child: Eyebrow('${weekdayShort(d)} ${shortDate(d)}')),
                if (dayTotal > 0)
                  Text(ltr('−${fmtAuto(dayTotal)}'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, fontFeatures: tabular)),
              ]),
            ));
          }
          rows.add(_tile(context, t));
        }

        return Scaffold(
          appBar: AppBar(title: const PeriodSwitcher(), centerTitle: true),
          floatingActionButton: FloatingActionButton(
            tooltip: tr('Add entry'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntryForm())),
            child: const Icon(Icons.add),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Search merchant, note, category or amount'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            SingleChildScrollView(
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
                      label: Text(accountFilter == null ? tr('Any account') : app.account(accountFilter)?.name ?? ''),
                      avatar: Icon(accountFilter == null ? Icons.credit_card : accountIcon(app.account(accountFilter)?.type ?? 'bank'), size: 18),
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
                  : ListView(padding: const EdgeInsets.only(bottom: 88), children: rows),
            ),
          ]),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Txn t) {
    final cs = Theme.of(context).colorScheme;
    final c = app.cat(t.categoryId);
    final title = t.label.isEmpty ? (c?.display ?? '') : t.label;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Color(c?.color ?? 0xFF888888).withOpacity(0.15),
        child: Icon(t.source == 'sms' ? Icons.sms_outlined : Icons.edit_note, size: 18, color: Color(c?.color ?? 0xFF888888)),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        c?.display ?? '',
        if (app.account(t.accountId) != null) app.account(t.accountId)!.name,
        if (t.note.isNotEmpty && t.merchant.isNotEmpty) t.note,
      ].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(ltr('${t.kind == 'income' ? '+' : '−'}${fmtAuto(t.amount)}'),
          style: TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600, fontSize: 15,
              color: t.kind == 'income' ? cs.primary : null)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryForm(existing: t))),
    );
  }
}
