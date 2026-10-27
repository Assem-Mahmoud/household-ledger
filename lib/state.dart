import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'defaults.dart';
import 'format.dart';
import 'models.dart';
import 'native.dart';
import 'periods.dart';
import 'sms_parser.dart';
import 'stats.dart';

final app = AppState();

class AppState extends ChangeNotifier {
  late Database db;
  List<Category> categories = [];
  List<Txn> txns = [];
  Map<String, Map<int, double>> overrides = {};
  Map<String, String> settings = {};
  List<SmsItem> pending = [];
  List<Rule> rules = [];
  late Period period;
  bool scanning = false;

  /// Bottom-navigation index, so any screen can jump to another tab.
  final tab = ValueNotifier<int>(0);

  // ---------------------------------------------------------------- setup

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'ledger.db');
    db = await openDatabase(path, version: 1, onCreate: _create);
    await _loadSettings();
    await _loadCategories();
    await _loadTxns();
    await _loadOverrides();
    await _loadRules();
    await _loadPending();
    period = periodFor(DateTime.now(), cycleStartDay);
  }

  Future<void> _create(Database d, int version) async {
    await d.execute('''CREATE TABLE categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL, grp TEXT NOT NULL,
      budget REAL NOT NULL DEFAULT 0, color INTEGER NOT NULL, sort INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('''CREATE TABLE txns(
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, amount REAL NOT NULL,
      category_id INTEGER NOT NULL, date TEXT NOT NULL, note TEXT, merchant TEXT, source TEXT,
      sms_key TEXT UNIQUE, created_at INTEGER)''');
    await d.execute('CREATE INDEX txns_date ON txns(date)');
    await d.execute('''CREATE TABLE budget_overrides(
      period TEXT NOT NULL, category_id INTEGER NOT NULL, amount REAL NOT NULL,
      PRIMARY KEY(period, category_id))''');
    await d.execute('''CREATE TABLE sms_inbox(
      id INTEGER PRIMARY KEY AUTOINCREMENT, sms_key TEXT NOT NULL UNIQUE, sender TEXT, body TEXT,
      received_at INTEGER, amount REAL, kind TEXT, merchant TEXT, status TEXT, category_id INTEGER)''');
    await d.execute('''CREATE TABLE rules(
      id INTEGER PRIMARY KEY AUTOINCREMENT, keyword TEXT NOT NULL UNIQUE, category_id INTEGER NOT NULL,
      learned INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
    await d.execute('''CREATE TABLE alerts(
      period TEXT NOT NULL, scope TEXT NOT NULL, level INTEGER NOT NULL,
      PRIMARY KEY(period, scope, level))''');

    final ids = <String, int>{};
    for (var i = 0; i < seedCategories.length; i++) {
      final c = seedCategories[i];
      ids[c.name] = await d.insert('categories', {
        'name': c.name, 'kind': c.kind, 'grp': c.grp, 'budget': 0,
        'color': palette[i % palette.length], 'sort': i, 'archived': 0,
      });
    }
    for (final e in seedRules.entries) {
      final id = ids[e.value];
      if (id != null) {
        await d.insert('rules', {'keyword': e.key, 'category_id': id, 'learned': 0},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    final defaults = <String, String>{
      'currency': 'SAR',
      'cycleDay': '1',
      'alertPct': '80',
      'reminderOn': '1',
      'reminderH': '21',
      'reminderM': '0',
      'smsOn': '1',
      'smsAlerts': '1',
      'senders': '',
      'blockedSenders': '',
      'ignoreKw': defaultIgnoreKeywords.join('\n'),
      'incomeKw': defaultIncomeKeywords.join('\n'),
      'expectedIncome': '0',
      'onboarded': '0',
    };
    for (final e in defaults.entries) {
      await d.insert('settings', {'key': e.key, 'value': e.value});
    }
  }

  Future<void> _loadSettings() async {
    final rows = await db.query('settings');
    settings = {for (final r in rows) r['key'] as String: (r['value'] as String?) ?? ''};
  }

  Future<void> _loadCategories() async {
    final rows = await db.query('categories', orderBy: 'sort, id');
    categories = rows.map(Category.fromMap).toList();
  }

  Future<void> _loadTxns() async {
    final rows = await db.query('txns', orderBy: 'date DESC, created_at DESC');
    txns = rows.map(Txn.fromMap).toList();
  }

  Future<void> _loadOverrides() async {
    final rows = await db.query('budget_overrides');
    overrides = {};
    for (final r in rows) {
      overrides.putIfAbsent(r['period'] as String, () => {})[r['category_id'] as int] =
          (r['amount'] as num).toDouble();
    }
  }

  Future<void> _loadRules() async {
    final rows = await db.query('rules');
    rules = rows.map(Rule.fromMap).toList()
      ..sort((a, b) {
        if (a.learned != b.learned) return a.learned ? -1 : 1;
        return b.keyword.length.compareTo(a.keyword.length);
      });
  }

  Future<void> _loadPending() async {
    final rows = await db.query('sms_inbox', where: 'status = ?', whereArgs: ['pending'], orderBy: 'received_at DESC');
    pending = rows.map(SmsItem.fromMap).toList();
  }

  // ------------------------------------------------------------- settings

  String get currency => settings['currency']?.trim().isNotEmpty == true ? settings['currency']!.trim() : 'SAR';
  int get cycleStartDay => (int.tryParse(settings['cycleDay'] ?? '1') ?? 1).clamp(1, 28).toInt();
  int get alertPct => (int.tryParse(settings['alertPct'] ?? '80') ?? 80).clamp(50, 95).toInt();
  bool flag(String key) => settings[key] == '1';
  double get expectedIncome => parseAmount(settings['expectedIncome'] ?? '0') ?? 0;

  List<String> lines(String key) => (settings[key] ?? '')
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> setSetting(String key, String value, {bool notify = true}) async {
    settings[key] = value;
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    if (key == 'cycleDay') period = periodFor(DateTime.now(), cycleStartDay);
    if (notify) notifyListeners();
  }

  Future<void> applyReminder() async {
    if (flag('reminderOn')) {
      await Native.scheduleReminder(int.tryParse(settings['reminderH'] ?? '21') ?? 21,
          int.tryParse(settings['reminderM'] ?? '0') ?? 0);
    } else {
      await Native.cancelReminder();
    }
    await Native.setPref('smsAlerts', flag('smsAlerts') && flag('smsOn'));
  }

  // -------------------------------------------------------------- periods

  void goPrev() {
    period = period.prev;
    notifyListeners();
  }

  void goNext() {
    period = period.next;
    notifyListeners();
  }

  void goToday() {
    period = periodFor(DateTime.now(), cycleStartDay);
    notifyListeners();
  }

  Period periodOf(String iso) => periodFor(parseIso(iso), cycleStartDay);

  // ----------------------------------------------------------- categories

  Category? cat(int id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Category? catByName(String name) {
    final n = name.trim().toLowerCase();
    for (final c in categories) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  List<Category> active(String kind) => categories.where((c) => c.kind == kind && !c.archived).toList();

  /// Expense categories that count as spending (excludes savings transfers).
  List<Category> get spendingCategories => active('expense').where((c) => !c.isSaving).toList();

  Future<Category> addCategory(String name, String kind, String grp) async {
    final sort = categories.isEmpty ? 0 : categories.map((c) => c.sort).reduce(max) + 1;
    final c = Category(id: 0, name: name.trim(), kind: kind, grp: grp,
        color: palette[categories.length % palette.length], sort: sort);
    c.id = await db.insert('categories', c.toMap());
    await _loadCategories();
    notifyListeners();
    return cat(c.id)!;
  }

  Future<void> updateCategory(Category c) async {
    await db.update('categories', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    await _loadCategories();
    notifyListeners();
  }

  // --------------------------------------------------------------- budgets

  double budgetFor(Period per, int catId) => overrides[per.key]?[catId] ?? cat(catId)?.budget ?? 0;
  bool isOverridden(Period per, int catId) => overrides[per.key]?.containsKey(catId) ?? false;

  double totalBudget(Period per) =>
      spendingCategories.fold(0.0, (s, c) => s + budgetFor(per, c.id));

  double templateTotal({bool includeSavings = false}) => active('expense')
      .where((c) => includeSavings || !c.isSaving)
      .fold(0.0, (s, c) => s + c.budget);

  Future<void> setMonthBudget(Period per, int catId, double amount) async {
    await db.insert('budget_overrides', {'period': per.key, 'category_id': catId, 'amount': amount},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadOverrides();
    notifyListeners();
  }

  Future<void> resetMonthBudget(Period per, int catId) async {
    await db.delete('budget_overrides', where: 'period = ? AND category_id = ?', whereArgs: [per.key, catId]);
    await _loadOverrides();
    notifyListeners();
  }

  /// Updates the template. Optionally clears this period's override so it follows the template.
  Future<void> setTemplateBudget(int catId, double amount, {Period? clearFor}) async {
    await db.update('categories', {'budget': amount}, where: 'id = ?', whereArgs: [catId]);
    if (clearFor != null) {
      await db.delete('budget_overrides', where: 'period = ? AND category_id = ?', whereArgs: [clearFor.key, catId]);
      await _loadOverrides();
    }
    await _loadCategories();
    notifyListeners();
  }

  Future<void> setTemplateBudgets(Map<int, double> values) async {
    final batch = db.batch();
    values.forEach((id, v) => batch.update('categories', {'budget': v}, where: 'id = ?', whereArgs: [id]));
    await batch.commit(noResult: true);
    await _loadCategories();
    notifyListeners();
  }

  // ---------------------------------------------------------- transactions

  Future<void> saveTxn(Txn t) async {
    if (t.id == null) {
      t.id = await db.insert('txns', t.toMap());
    } else {
      await db.update('txns', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
    }
    await _loadTxns();
    notifyListeners();
    await checkAlerts(t);
  }

  Future<void> deleteTxn(Txn t) async {
    if (t.id == null) return;
    await db.delete('txns', where: 'id = ?', whereArgs: [t.id]);
    if (t.smsKey != null) {
      // let the message come back to the review list
      await db.update('sms_inbox', {'status': 'pending'}, where: 'sms_key = ?', whereArgs: [t.smsKey]);
      await _loadPending();
    }
    await _loadTxns();
    notifyListeners();
  }

  // ---------------------------------------------------------------- alerts

  Future<void> checkAlerts(Txn t) async {
    if (t.kind != 'expense') return;
    final c = cat(t.categoryId);
    if (c == null || c.isSaving) return;
    final per = periodOf(t.date);
    final st = statsFor(per);
    final pct = alertPct / 100;

    Future<void> fire(String scope, int level, String title, String body) async {
      final seen = await db.query('alerts',
          where: 'period = ? AND scope = ? AND level = ?', whereArgs: [per.key, scope, level]);
      if (seen.isNotEmpty) return;
      await db.insert('alerts', {'period': per.key, 'scope': scope, 'level': level});
      await Native.notify(10000 + (scope.hashCode.abs() % 50000) * 2 + level, title, body);
    }

    final daysLeft = per.isCurrent ? per.days - per.elapsed : 0;
    final spent = st.byCat[c.id] ?? 0;
    final budget = budgetFor(per, c.id);
    if (budget > 0) {
      if (spent >= budget) {
        await fire('cat${c.id}', 2, '${c.name} is over budget',
            'Spent ${fmt(spent)} of ${fmt(budget)} $currency this month (${fmt(spent - budget)} over).');
      } else if (spent >= budget * pct) {
        await fire('cat${c.id}', 1, '${c.name} at ${(spent / budget * 100).round()}% of budget',
            '${fmt(budget - spent)} $currency left${daysLeft > 0 ? ' with $daysLeft days to go' : ''}.');
      }
    }
    final total = totalBudget(per);
    if (total > 0) {
      if (st.spend >= total) {
        await fire('total', 2, 'Monthly budget exceeded',
            'Spending is ${fmt(st.spend)} against ${fmt(total)} $currency budgeted.');
      } else if (st.spend >= total * pct) {
        await fire('total', 1, '${(st.spend / total * 100).round()}% of the monthly budget used',
            '${fmt(total - st.spend)} $currency left${daysLeft > 0 ? ' for the next $daysLeft days' : ''}.');
      }
    }
  }

  // ------------------------------------------------------------------ SMS

  int? suggestCategory(String merchant, String body, String kind) {
    final m = merchant.toLowerCase();
    final b = body.toLowerCase();
    Category? ok(Rule r) {
      final c = cat(r.categoryId);
      if (c == null || c.archived || c.kind != kind) return null;
      return c;
    }

    if (m.isNotEmpty) {
      for (final r in rules) {
        final c = ok(r);
        if (c != null && m.contains(r.keyword)) return c.id;
      }
    }
    for (final r in rules) {
      final c = ok(r);
      if (c != null && b.contains(r.keyword) && (m.isEmpty || r.learned)) return c.id;
    }
    return null;
  }

  /// Reads new SMS since the last scan and adds bank transactions to the review list.
  Future<String> scanSms({DateTime? from}) async {
    if (scanning) return '';
    scanning = true;
    notifyListeners();
    try {
      final perm = await Native.requestPermissions(sms: true);
      if (perm['sms'] != true) {
        return 'SMS access is off. Allow it when asked, or in Android Settings → Apps → Household Ledger → Permissions.';
      }
      int since;
      if (from != null) {
        since = from.millisecondsSinceEpoch;
      } else {
        since = int.tryParse(settings['smsLastScan'] ?? '') ?? periodFor(DateTime.now(), cycleStartDay).start.millisecondsSinceEpoch;
      }
      final messages = await Native.readSms(since);
      final allow = lines('senders');
      final block = lines('blockedSenders');
      final ignore = lines('ignoreKw');
      final income = lines('incomeKw');
      var added = 0;
      var newest = int.tryParse(settings['smsLastScan'] ?? '') ?? 0;

      for (final msg in messages) {
        final date = (msg['date'] as num).toInt();
        newest = max(newest, date);
        final sender = (msg['address'] ?? '').toString();
        final body = (msg['body'] ?? '').toString();
        final s = sender.toLowerCase();
        if (block.contains(s)) continue;
        if (allow.isNotEmpty && !allow.contains(s)) continue;
        if (allow.isEmpty && !looksLikeTransaction(body)) continue;
        final parsed = parseSms(body, ignore: ignore, income: income);
        if (parsed == null) continue;
        final key = '$sender|$date';
        final exists = await db.query('sms_inbox', columns: ['id'], where: 'sms_key = ?', whereArgs: [key]);
        if (exists.isNotEmpty) continue;
        await db.insert('sms_inbox', {
          'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
          'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'pending',
          'category_id': suggestCategory(parsed.merchant, body, parsed.kind),
        });
        added++;
      }
      await setSetting('smsLastScan', '$newest', notify: false);
      await _loadPending();
      if (added == 0) return 'No new bank transactions found.';
      return '$added new transaction${added == 1 ? '' : 's'} to review.';
    } catch (e) {
      return 'Could not read messages ($e).';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> confirmSms(SmsItem it,
      {required double amount,
      required String kind,
      required int categoryId,
      required String merchant,
      required String date,
      String note = '',
      bool remember = true}) async {
    final t = Txn(kind: kind, amount: amount, categoryId: categoryId, date: date,
        merchant: merchant.trim(), note: note.trim(), source: 'sms', smsKey: it.smsKey);
    await db.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update('sms_inbox', {'status': 'confirmed', 'category_id': categoryId}, where: 'id = ?', whereArgs: [it.id]);
    if (remember) await learnRule(merchant, categoryId, notify: false);
    await _loadTxns();
    await _loadPending();
    notifyListeners();
    await checkAlerts(t);
  }

  Future<void> ignoreSms(SmsItem it, {bool blockSender = false}) async {
    await db.update('sms_inbox', {'status': 'ignored'}, where: 'id = ?', whereArgs: [it.id]);
    if (blockSender && it.sender.isNotEmpty) {
      final list = lines('blockedSenders')..add(it.sender.toLowerCase());
      await setSetting('blockedSenders', list.toSet().join('\n'), notify: false);
      await db.update('sms_inbox', {'status': 'ignored'},
          where: 'sender = ? AND status = ?', whereArgs: [it.sender, 'pending']);
    }
    await _loadPending();
    notifyListeners();
  }

  Future<int> confirmAllSuggested() async {
    var n = 0;
    for (final it in List<SmsItem>.from(pending)) {
      if (it.categoryId == null || cat(it.categoryId!) == null) continue;
      await confirmSms(it,
          amount: it.amount, kind: it.kind, categoryId: it.categoryId!, merchant: it.merchant,
          date: isoDate(DateTime.fromMillisecondsSinceEpoch(it.receivedAt)), remember: false);
      n++;
    }
    return n;
  }

  // ----------------------------------------------------------------- rules

  Future<void> learnRule(String merchant, int categoryId, {bool notify = true}) async {
    final key = merchantKey(merchant);
    if (key.length < 3) return;
    await db.insert('rules', {'keyword': key, 'category_id': categoryId, 'learned': 1},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadRules();
    if (notify) notifyListeners();
  }

  Future<void> addRule(String keyword, int categoryId) async {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return;
    await db.insert('rules', {'keyword': k, 'category_id': categoryId, 'learned': 1},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadRules();
    notifyListeners();
  }

  Future<void> deleteRule(Rule r) async {
    await db.delete('rules', where: 'id = ?', whereArgs: [r.id]);
    await _loadRules();
    notifyListeners();
  }

  // ------------------------------------------------------------ CSV export

  String exportCsv() {
    String q(String v) => RegExp(r'[",\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    final out = StringBuffer('date,type,category,amount,merchant,note\n');
    for (final t in txns.reversed) {
      out.writeln([t.date, t.kind, cat(t.categoryId)?.name ?? '', fmtAuto(t.amount).replaceAll(',', ''),
        t.merchant, t.note].map((v) => q(v.toString())).join(','));
    }
    return out.toString();
  }

  /// Accepts this app's export and the web ledger export (date,type,category,amount_sar,note).
  Future<String> importCsv(String text) async {
    final rows = _parseCsv(text.trim());
    if (rows.length < 2) return 'Nothing to import. Paste rows with a header line first.';
    final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(List<String> names) => head.indexWhere((h) => names.contains(h));
    final iDate = col(['date']), iType = col(['type', 'kind']), iCat = col(['category']);
    final iAmt = col(['amount', 'amount_sar']), iNote = col(['note']), iMer = col(['merchant']);
    if (iDate < 0 || iAmt < 0) return 'The header needs at least "date" and "amount" columns.';
    var added = 0, skipped = 0;
    final batch = db.batch();
    for (final r in rows.skip(1)) {
      String at(int i) => i >= 0 && i < r.length ? r[i].trim() : '';
      final date = at(iDate);
      final amount = parseAmount(at(iAmt));
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || amount == null || amount == 0) {
        skipped++;
        continue;
      }
      var kind = at(iType).toLowerCase() == 'income' ? 'income' : 'expense';
      final name = at(iCat);
      var c = name.isEmpty ? null : catByName(name);
      if (c == null && name.isNotEmpty) c = await addCategory(name, kind, kind == 'income' ? 'income' : 'want');
      c ??= catByName(kind == 'income' ? 'Other income' : 'Other') ?? active(kind).first;
      kind = c.kind;
      batch.insert('txns', Txn(kind: kind, amount: amount.abs(), categoryId: c.id, date: date,
          note: at(iNote), merchant: at(iMer), source: 'import').toMap());
      added++;
    }
    await batch.commit(noResult: true);
    await _loadTxns();
    notifyListeners();
    return 'Imported $added entr${added == 1 ? 'y' : 'ies'}${skipped > 0 ? ', skipped $skipped' : ''}.';
  }

  List<List<String>> _parseCsv(String s) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQ = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inQ) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQ = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQ = true;
      } else if (ch == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString().replaceAll('\r', ''));
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    row.add(cell.toString().replaceAll('\r', ''));
    rows.add(row);
    return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  }
}
