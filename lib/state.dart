import 'dart:convert';
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

  /// Sub-tab of the Budget screen: 0 this period, 1 plan, 2 template.
  final budgetTab = ValueNotifier<int>(0);

  // ---------------------------------------------------------------- setup

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'ledger.db');
    db = await openDatabase(path, version: 2, onCreate: _create, onUpgrade: (d, from, to) async {
      if (from < 2) await _createPlanTables(d);
    });
    await _loadSettings();
    await _loadCategories();
    await _loadTxns();
    await _loadOverrides();
    await _loadRules();
    await _loadPending();
    await _loadPlans();
    period = periodFor(DateTime.now(), cycleStartDay);
    if (pending.isNotEmpty) await reparsePending(notify: false);
  }

  Future<void> _createPlanTables(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS plan_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, kind TEXT NOT NULL, amount REAL NOT NULL,
      due_day INTEGER, category_id INTEGER, start_period TEXT NOT NULL, end_period TEXT, only_period TEXT,
      sort INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS plan_status(
      period TEXT NOT NULL, item_id INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0, amount REAL,
      PRIMARY KEY(period, item_id))''');
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
    await _createPlanTables(d);

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
      // a card purchase typed in by hand clears its matching bank SMS from Review
      if (t.smsKey == null && await _linkPendingToEntries() > 0) await _loadPending();
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

  static String _normSender(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]'), '');

  /// Flexible sender match: "AlRajhiBank", "alrajhi bank" and "AlRajhi" all match the same sender.
  bool _senderIn(String sender, List<String> list) {
    final s = _normSender(sender);
    if (s.isEmpty) return false;
    for (final e in list) {
      final n = _normSender(e);
      if (n.isNotEmpty && (s == n || s.contains(n))) return true;
    }
    return false;
  }

  /// Whether a message passes the sender filters and keyword rules. Returns the parse result if it does.
  ParsedSms? _accept(String sender, String body) {
    final allow = lines('senders');
    if (_senderIn(sender, lines('blockedSenders'))) return null;
    if (allow.isNotEmpty && !_senderIn(sender, allow)) return null;
    if (allow.isEmpty && !looksLikeTransaction(body)) return null;
    return parseSms(body, ignore: lines('ignoreKw'), income: lines('incomeKw'));
  }

  /// Reads SMS and adds bank transactions to the review list.
  /// Without a range it continues from the last scan; with [from]/[to] it reads exactly that window.
  Future<String> scanSms({DateTime? from, DateTime? to, bool filterReview = false}) async {
    if (scanning) return '';
    scanning = true;
    notifyListeners();
    try {
      final perm = await Native.requestPermissions(sms: true);
      if (perm['sms'] != true) {
        return 'SMS access is off. Allow it when asked, or in Android Settings → Apps → Household Ledger → Permissions.';
      }
      final ranged = from != null || to != null;
      var since = from != null
          ? DateTime(from.year, from.month, from.day).millisecondsSinceEpoch - 1
          : int.tryParse(settings['smsLastScan'] ?? '') ?? periodFor(DateTime.now(), cycleStartDay).start.millisecondsSinceEpoch;
      final until = to != null ? DateTime(to.year, to.month, to.day, 23, 59, 59, 999).millisecondsSinceEpoch : null;
      if (filterReview && ranged) reviewWindow = (from ?? DateTime(2000), to ?? DateTime.now());
      // Messages before the SMS start date are never read (statements/CSV cover that time).
      final start = smsStartDate;
      if (start != null) {
        final cut = start.millisecondsSinceEpoch - 1;
        if (until != null && until <= cut) {
          return 'SMS before ${shortDate(start)} ${start.year} are switched off, because imported statements cover that time. '
              'Change it in Settings → SMS start date.';
        }
        since = max(since, cut);
      }
      final messages = await Native.readSms(since, untilMillis: until);
      var added = 0, matched = 0, linked = 0;
      var newest = int.tryParse(settings['smsLastScan'] ?? '') ?? 0;

      for (final msg in messages) {
        final date = (msg['date'] as num).toInt();
        newest = max(newest, date);
        final sender = (msg['address'] ?? '').toString();
        final body = (msg['body'] ?? '').toString();
        final parsed = _accept(sender, body);
        if (parsed == null) continue;
        matched++;
        final key = '$sender|$date';
        final exists = await db.query('sms_inbox', columns: ['id'], where: 'sms_key = ?', whereArgs: [key]);
        if (exists.isNotEmpty) continue;
        // Already entered by hand or imported from a statement? Link it instead of adding it twice.
        final linkedId = await _linkToExisting(key, date, parsed);
        if (linkedId != null) {
          await db.insert('sms_inbox', {
            'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
            'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'confirmed',
            'category_id': linkedId,
          });
          linked++;
          continue;
        }
        await db.insert('sms_inbox', {
          'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
          'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'pending',
          'category_id': suggestCategory(parsed.merchant, body, parsed.kind),
        });
        added++;
      }
      if (!ranged || until == null || until >= newest) {
        await setSetting('smsLastScan', '$newest', notify: false);
      }
      await _loadPending();
      if (linked > 0) await _loadTxns();
      final window = ranged
          ? ' between ${from != null ? shortDate(from) : 'the start'} and ${to != null ? shortDate(to) : 'today'}'
          : '';
      final linkNote = linked > 0 ? ' $linked matched entries you already had, so they weren\'t added again.' : '';
      if (added == 0) {
        return matched == 0
            ? 'No bank transactions found$window (${messages.length} messages checked).'
            : 'No new transactions$window.$linkNote${linked == 0 ? ' $matched were already reviewed.' : ''}';
      }
      return '$added new transaction${added == 1 ? '' : 's'} to review$window.$linkNote';
    } catch (e) {
      return 'Could not read messages ($e).';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// Finds an imported or manual entry with the same day, direction and amount that no SMS is linked to yet,
  /// links this SMS to it, and returns its category id. Returns null when there is no such entry.
  Future<int?> _linkToExisting(String key, int receivedAt, ParsedSms parsed) async {
    final day = isoDate(DateTime.fromMillisecondsSinceEpoch(receivedAt));
    final rows = await db.query('txns',
        columns: ['id', 'category_id', 'merchant'],
        where: "date = ? AND kind = ? AND ABS(amount - ?) < 0.01 AND sms_key IS NULL AND source IN ('import', 'manual')",
        whereArgs: [day, parsed.kind, parsed.amount],
        orderBy: 'id',
        limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    await db.update(
        'txns',
        {
          'sms_key': key,
          if (((r['merchant'] as String?) ?? '').isEmpty && parsed.merchant.isNotEmpty) 'merchant': parsed.merchant,
        },
        where: 'id = ?',
        whereArgs: [r['id']]);
    return r['category_id'] as int;
  }

  /// Date range of the last manual range scan; Review shows only items in it until cleared.
  (DateTime, DateTime)? reviewWindow;

  void clearReviewWindow() {
    reviewWindow = null;
    notifyListeners();
  }

  List<SmsItem> get visiblePending {
    final w = reviewWindow;
    if (w == null) return pending;
    final a = DateTime(w.$1.year, w.$1.month, w.$1.day).millisecondsSinceEpoch;
    final b = DateTime(w.$2.year, w.$2.month, w.$2.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    return pending.where((p) => p.receivedAt >= a && p.receivedAt <= b).toList();
  }

  /// SMS received before this date are ignored. Null means no cut-off.
  DateTime? get smsStartDate {
    final ms = int.tryParse(settings['smsStartFrom'] ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Start fresh: ignore every SMS before [from] (and clear them from Review); scanning continues from there.
  Future<int> setSmsStartDate(DateTime? from) async {
    if (from == null) {
      await setSetting('smsStartFrom', '', notify: false);
      notifyListeners();
      return 0;
    }
    final start = DateTime(from.year, from.month, from.day);
    final ms = start.millisecondsSinceEpoch;
    final n = await db.update('sms_inbox', {'status': 'ignored'},
        where: 'status = ? AND received_at < ?', whereArgs: ['pending', ms]);
    await setSetting('smsStartFrom', '$ms', notify: false);
    final last = int.tryParse(settings['smsLastScan'] ?? '') ?? 0;
    if (last < ms) await setSetting('smsLastScan', '${ms - 1}', notify: false);
    reviewWindow = null;
    await _loadPending();
    notifyListeners();
    return n;
  }

  /// Waiting SMS that match an existing (imported or manual) entry are linked to it and leave the review list.
  Future<int> _linkPendingToEntries() async {
    final rows = await db.query('sms_inbox', where: 'status = ?', whereArgs: ['pending']);
    var n = 0;
    for (final r in rows) {
      final it = SmsItem.fromMap(r);
      final catId = await _linkToExisting(it.smsKey, it.receivedAt, ParsedSms(it.amount, it.kind, it.merchant));
      if (catId == null) continue;
      await db.update('sms_inbox', {'status': 'confirmed', 'category_id': catId}, where: 'id = ?', whereArgs: [it.id]);
      n++;
    }
    return n;
  }

  /// Re-reads waiting items with the current parser and filters (after a settings change or app update).
  Future<void> reparsePending({bool notify = true}) async {
    final rows = await db.query('sms_inbox', where: 'status = ?', whereArgs: ['pending']);
    for (final r in rows) {
      final it = SmsItem.fromMap(r);
      final parsed = _accept(it.sender, it.body);
      if (parsed == null) {
        // no longer matches the filters: drop it so a later scan can pick it up again if filters change back
        await db.delete('sms_inbox', where: 'id = ?', whereArgs: [it.id]);
        continue;
      }
      await db.update('sms_inbox', {
        'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant,
        'category_id': suggestCategory(parsed.merchant, it.body, parsed.kind),
      }, where: 'id = ?', whereArgs: [it.id]);
    }
    await _loadPending();
    if (notify) notifyListeners();
  }

  /// Called after any SMS setting changes: re-check the waiting list, then rescan the current period.
  Future<String> applySmsSettings() async {
    await reparsePending(notify: false);
    reviewWindow = null;
    final per = periodFor(DateTime.now(), cycleStartDay);
    return scanSms(from: per.start, to: DateTime.now());
  }

  /// Senders with transaction-looking messages in the last [days] days, most active first.
  Future<List<(String, int)>> detectSenders({int days = 120}) async {
    final perm = await Native.requestPermissions(sms: true);
    if (perm['sms'] != true) return [];
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final messages = await Native.readSms(since);
    final counts = <String, int>{};
    for (final m in messages) {
      final sender = (m['address'] ?? '').toString();
      if (sender.isEmpty) continue;
      if (looksLikeTransaction((m['body'] ?? '').toString())) counts[sender] = (counts[sender] ?? 0) + 1;
    }
    final out = counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
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

  Future<void> ignoreMany(List<SmsItem> items) async {
    final batch = db.batch();
    for (final it in items) {
      batch.update('sms_inbox', {'status': 'ignored'}, where: 'id = ?', whereArgs: [it.id]);
    }
    await batch.commit(noResult: true);
    await _loadPending();
    notifyListeners();
  }

  Future<int> confirmAllSuggested({List<SmsItem>? only}) async {
    var n = 0;
    for (final it in List<SmsItem>.from(only ?? pending)) {
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
    var added = 0, skipped = 0, duplicates = 0;
    // How many entries already exist per day/direction/amount, so re-importing or overlapping
    // with SMS-confirmed entries never double-counts.
    String dupKey(String date, String kind, double amount) => '$date|$kind|${(amount * 100).round()}';
    final existing = <String, int>{};
    for (final t in txns) {
      final k = dupKey(t.date, t.kind, t.amount);
      existing[k] = (existing[k] ?? 0) + 1;
    }
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
      final dk = dupKey(date, kind, amount.abs());
      if ((existing[dk] ?? 0) > 0) {
        existing[dk] = existing[dk]! - 1;
        duplicates++;
        continue;
      }
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
    final linkedPending = await _linkPendingToEntries();
    await _loadTxns();
    await _loadPending();
    notifyListeners();
    final parts = <String>[
      'Imported $added entr${added == 1 ? 'y' : 'ies'}',
      if (duplicates > 0) '$duplicates already in the app were skipped',
      if (skipped > 0) '$skipped unreadable rows ignored',
      if (linkedPending > 0) '$linkedPending waiting SMS matched imported entries and were cleared from Review',
    ];
    return '${parts.join(', ')}.';
  }

  // ------------------------------------------------------------ monthly plan

  List<PlanItem> planItems = [];
  Map<String, Map<int, (bool, double?)>> planStatus = {};

  Future<void> _loadPlans() async {
    planItems = (await db.query('plan_items', orderBy: 'sort, id')).map(PlanItem.fromMap).toList();
    planStatus = {};
    for (final r in await db.query('plan_status')) {
      planStatus.putIfAbsent(r['period'] as String, () => {})[r['item_id'] as int] =
          (((r['done'] as int?) ?? 0) == 1, (r['amount'] as num?)?.toDouble());
    }
  }

  DateTime? _dueDate(Period per, int? day) {
    if (day == null) return null;
    // the due day falls inside the period (handles salary-to-salary periods)
    var d = DateTime(per.start.year, per.start.month, day);
    if (d.isBefore(per.start)) d = DateTime(per.start.year, per.start.month + 1, day);
    if (d.isAfter(per.end)) d = per.end;
    return d;
  }

  List<PlanLine> planFor(Period per) {
    final st = planStatus[per.key] ?? {};
    final s = statsFor(per);
    final out = <PlanLine>[];
    for (final it in planItems.where((i) => i.appliesTo(per.key))) {
      final status = st[it.id];
      final target = status?.$2 ?? it.amount;
      var progress = 0.0;
      if (it.categoryId != null) {
        for (final t in s.list) {
          if (t.categoryId == it.categoryId && t.kind == 'expense') progress += t.amount;
        }
      }
      out.add(PlanLine(it, target, progress, status?.$1 ?? false, status?.$2 != null, _dueDate(per, it.dueDay)));
    }
    out.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.item.sort.compareTo(b.item.sort);
    });
    return out;
  }

  double planTotal(Period per) => planFor(per).fold(0.0, (a, l) => a + l.target);

  Future<void> _setStatus(Period per, int itemId, {bool? done, double? amount, bool clearAmount = false}) async {
    final cur = planStatus[per.key]?[itemId];
    final newDone = done ?? cur?.$1 ?? false;
    final newAmount = clearAmount ? null : (amount ?? cur?.$2);
    await db.insert('plan_status', {'period': per.key, 'item_id': itemId, 'done': newDone ? 1 : 0, 'amount': newAmount},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadPlans();
    notifyListeners();
  }

  Future<void> setPlanDone(Period per, PlanItem it, bool done) => _setStatus(per, it.id, done: done);

  Future<void> setPlanAmountForPeriod(Period per, PlanItem it, double? amount) =>
      _setStatus(per, it.id, amount: amount, clearAmount: amount == null);

  Future<void> savePlanItem(PlanItem it) async {
    if (it.id == 0) {
      it.sort = planItems.isEmpty ? 0 : planItems.map((e) => e.sort).reduce(max) + 1;
      it.id = await db.insert('plan_items', it.toMap());
    } else {
      await db.update('plan_items', it.toMap(), where: 'id = ?', whereArgs: [it.id]);
    }
    await _loadPlans();
    notifyListeners();
  }

  /// One-off items are deleted. Recurring items stop after the previous period, so past months keep their history.
  Future<void> removePlanItem(PlanItem it, Period from) async {
    if (!it.recurring || from.key.compareTo(it.startPeriod) <= 0) {
      await db.delete('plan_items', where: 'id = ?', whereArgs: [it.id]);
      await db.delete('plan_status', where: 'item_id = ?', whereArgs: [it.id]);
    } else {
      it.endPeriod = from.prev.key;
      await db.update('plan_items', it.toMap(), where: 'id = ?', whereArgs: [it.id]);
    }
    await _loadPlans();
    notifyListeners();
  }

  /// Reminds once per period about plan items that are due today or overdue.
  Future<void> checkPlanReminders() async {
    final per = periodFor(DateTime.now(), cycleStartDay);
    for (final l in planFor(per)) {
      if (l.done || (l.status != 'overdue' && l.due == null)) continue;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (l.due == null || l.due!.isAfter(today)) continue;
      final scope = 'plan${l.item.id}';
      final seen = await db.query('alerts', where: 'period = ? AND scope = ?', whereArgs: [per.key, scope]);
      if (seen.isNotEmpty) continue;
      await db.insert('alerts', {'period': per.key, 'scope': scope, 'level': 1});
      final verb = l.item.kind == 'save' ? 'Set aside' : 'Pay';
      await Native.notify(30000 + l.item.id, '$verb: ${l.item.title}',
          '${fmt(l.remaining > 0 ? l.remaining : l.target)} $currency ${l.due!.isBefore(today) ? 'was due on ${shortDate(l.due!)}' : 'is due today'}. Tick it in your plan once done.');
    }
  }

  // ------------------------------------------------------- backup / restore

  static const _backupTables = [
    'categories', 'txns', 'budget_overrides', 'sms_inbox', 'rules', 'settings', 'alerts', 'plan_items', 'plan_status',
  ];

  Future<String> backupJson() async {
    final data = <String, Object?>{
      'app': 'household_ledger',
      'format': 1,
      'createdAt': DateTime.now().toIso8601String(),
    };
    for (final t in _backupTables) {
      data[t] = await db.query(t);
    }
    return const JsonEncoder.withIndent(' ').convert(data);
  }

  /// Opens Gmail with a full backup attached. The user taps Send.
  Future<String> emailBackup() async {
    final now = DateTime.now();
    final name = 'household-ledger-backup-${isoDate(now)}.json';
    final json = await backupJson();
    final how = await Native.emailFile(
      content: json,
      fileName: name,
      to: settings['backupEmail'] ?? '',
      subject: 'Household Ledger backup ${isoDate(now)}',
      body: 'Backup of ${txns.length} entries, created ${isoDate(now)} ${two(now.hour)}:${two(now.minute)}.\n'
          'To restore: save the attached file, then in the app open Settings → Restore from backup.',
    );
    await setSetting('lastBackup', '${now.millisecondsSinceEpoch}');
    return how;
  }

  int? get daysSinceBackup {
    final ms = int.tryParse(settings['lastBackup'] ?? '');
    if (ms == null) return null;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays;
  }

  bool get backupDue => txns.isNotEmpty && (daysSinceBackup == null || daysSinceBackup! >= 7);

  /// Summary of a backup file before restoring, or null if it isn't one.
  String? describeBackup(String text) {
    try {
      final d = jsonDecode(text);
      if (d is! Map || d['app'] != 'household_ledger') return null;
      final n = (d['txns'] as List?)?.length ?? 0;
      final created = (d['createdAt'] as String?)?.substring(0, 10) ?? 'unknown date';
      return 'Backup from $created with $n entries.';
    } catch (_) {
      return null;
    }
  }

  /// Replaces everything in the app with the backup's contents.
  Future<String> restoreBackup(String text) async {
    final d = jsonDecode(text) as Map<String, dynamic>;
    if (d['app'] != 'household_ledger') return 'This file is not a Household Ledger backup.';
    final keepBackupInfo = {'backupEmail': settings['backupEmail'], 'lastBackup': settings['lastBackup']};
    await db.transaction((tx) async {
      for (final t in _backupTables) {
        final rows = d[t];
        if (rows is! List) continue;
        await tx.delete(t);
        for (final r in rows) {
          await tx.insert(t, Map<String, Object?>.from(r as Map), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    await _loadSettings();
    for (final e in keepBackupInfo.entries) {
      if (e.value != null && (settings[e.key] ?? '').isEmpty) await setSetting(e.key, e.value!, notify: false);
    }
    await _loadCategories();
    await _loadTxns();
    await _loadOverrides();
    await _loadRules();
    await _loadPending();
    await _loadPlans();
    period = periodFor(DateTime.now(), cycleStartDay);
    await applyReminder();
    notifyListeners();
    return 'Restored ${txns.length} entries.';
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
