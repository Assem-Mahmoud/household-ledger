import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier, ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'accounts.dart';
import 'defaults.dart';
import 'format.dart';
import 'funds.dart';
import 'i18n.dart';
import 'models.dart';
import 'native.dart';
import 'periods.dart';
import 'sms_parser.dart';
import 'sms_template.dart';
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

  /// Language preference: 'system', 'en' or 'ar'. Listened to by the app root.
  final language = ValueNotifier<String>('system');

  /// Light/dark: 'system', 'light' or 'dark'.
  final appearance = ValueNotifier<String>('system');

  /// Text to search for when Entries opens (e.g. tapping an item in Insights).
  final entrySearch = ValueNotifier<String>('');

  /// Opens all entries searched for [text].
  void searchEntries(String text) {
    entrySearch.value = text;
    openActivity(1);
  }

  /// Activity tab: 0 = to review, 1 = all entries.
  final activitySub = ValueNotifier<int>(0);

  Future<void> setAppearance(String v) async {
    await setSetting('appearance', v, notify: false);
    appearance.value = v;
  }

  /// Opens the Activity tab on "To review" (0) or "All entries" (1).
  void openActivity(int sub) {
    activitySub.value = sub;
    tab.value = 1;
  }

  /// Opens the Plan tab on one of its sections (0 checklist, 1 budgets, 2 template).
  void openPlan(int section) {
    budgetTab.value = section;
    tab.value = 3;
  }

  /// Sub-tab of the Plan screen: 0 checklist, 1 budgets, 2 template.
  final budgetTab = ValueNotifier<int>(0);

  // ---------------------------------------------------------------- setup

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'ledger.db');
    db = await openDatabase(path, version: 3, onCreate: _create, onUpgrade: (d, from, to) async {
      if (from < 2) await _createPlanTables(d);
      if (from < 3) await _upgradeTo3(d);
    });
    await _loadSettings();
    language.value = settings['lang']?.isNotEmpty == true ? settings['lang']! : 'system';
    appearance.value = settings['appearance']?.isNotEmpty == true ? settings['appearance']! : 'system';
    setLanguage(language.value);
    await _loadCategories();
    await _loadTxns();
    await _loadOverrides();
    await _loadRules();
    await _loadPending();
    await _loadPlans();
    await _loadAccounts();
    await _loadFunds();
    period = periodFor(DateTime.now(), cycleStartDay);
    if (pending.isNotEmpty) await reparsePending(notify: false);
  }

  /// v3: accounts & cards on entries, yearly expenses (funds) in the plan.
  Future<void> _upgradeTo3(Database d) async {
    await d.execute('''CREATE TABLE IF NOT EXISTS accounts(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'bank',
      digits TEXT, color INTEGER, sort INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)''');
    for (final t in ['txns', 'sms_inbox']) {
      final cols = await d.rawQuery('PRAGMA table_info($t)');
      if (!cols.any((c) => c['name'] == 'account_id')) await d.execute('ALTER TABLE $t ADD COLUMN account_id INTEGER');
    }
    await d.execute('''CREATE TABLE IF NOT EXISTS funds(
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, due_date TEXT NOT NULL,
      saved REAL NOT NULL DEFAULT 0, category_id INTEGER, repeat_months INTEGER NOT NULL DEFAULT 12,
      archived INTEGER NOT NULL DEFAULT 0)''');
    await d.execute('''CREATE TABLE IF NOT EXISTS fund_status(
      period TEXT NOT NULL, fund_id INTEGER NOT NULL, kind TEXT NOT NULL, amount REAL NOT NULL,
      prev_due TEXT, prev_saved REAL, PRIMARY KEY(period, fund_id, kind))''');
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
    await _upgradeTo3(d);

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
    _syncAutoKeys();
  }

  /// Tells the Android SMS alert which merchants are added without review, so it stays quiet for them.
  Future<void> _syncAutoKeys() async {
    final keys = autoConfirm ? rules.where((r) => r.learned && r.keyword.length >= 3).map((r) => r.keyword) : const <String>[];
    await Native.setPrefText('autoKeys', keys.join('\n'));
  }

  Future<void> _loadPending() async {
    final rows = await db.query('sms_inbox', where: 'status = ?', whereArgs: ['pending'], orderBy: 'received_at DESC');
    pending = rows.map(SmsItem.fromMap).toList();
  }

  // ------------------------------------------------------------- settings

  /// Home currency code, e.g. SAR, EGP, AED. Drives SMS reading and how amounts are labelled.
  String get currencyCode {
    final c = settings['currency']?.trim() ?? '';
    return c.isEmpty ? 'SAR' : c.toUpperCase();
  }

  static const arabicCurrency = {
    'SAR': 'ر.س', 'EGP': 'ج.م', 'AED': 'د.إ', 'KWD': 'د.ك', 'BHD': 'د.ب', 'QAR': 'ر.ق', 'OMR': 'ر.ع', 'JOD': 'د.أ',
  };

  String get currency => isAr ? (arabicCurrency[currencyCode] ?? currencyCode) : currencyCode;

  Future<void> setLanguagePref(String pref) async {
    await setSetting('lang', pref, notify: false);
    setLanguage(pref);
    await Native.setLang(lang);
    language.value = pref;
    notifyListeners();
  }
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
    // the new-SMS notification (Android side) skips senders you blocked
    if (key == 'blockedSenders') await Native.setPrefText('blockedSenders', value);
    if (key == 'autoConfirm') await _syncAutoKeys();
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
    await Native.setPrefText('blockedSenders', lines('blockedSenders').join('\n'));
    await Native.setPrefText('taughtSenders', templates.map((t) => t.sender).where((s) => s.isNotEmpty).join('\n'));
    await Native.setLang(lang);
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
    if (t.accountId != null && t.source == 'manual') await setSetting('lastAccount', '${t.accountId}', notify: false);
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
        await fire('cat${c.id}', 2, tr('{cat} is over budget', {'cat': c.display}),
            tr('Spent {a} of {b} {cur} this month ({c} over).',
                {'a': fmt(spent), 'b': fmt(budget), 'cur': currency, 'c': fmt(spent - budget)}));
      } else if (spent >= budget * pct) {
        await fire('cat${c.id}', 1, tr('{cat} at {p}% of budget', {'cat': c.display, 'p': (spent / budget * 100).round()}),
            daysLeft > 0
                ? tr('{a} {cur} left with {d} days to go.', {'a': fmt(budget - spent), 'cur': currency, 'd': daysLeft})
                : tr('{a} {cur} left.', {'a': fmt(budget - spent), 'cur': currency}));
      }
    }
    final total = totalBudget(per);
    if (total > 0) {
      if (st.spend >= total) {
        await fire('total', 2, tr('Monthly budget exceeded'),
            tr('Spending is {a} against {b} {cur} budgeted.', {'a': fmt(st.spend), 'b': fmt(total), 'cur': currency}));
      } else if (st.spend >= total * pct) {
        await fire('total', 1, tr('{p}% of the monthly budget used', {'p': (st.spend / total * 100).round()}),
            daysLeft > 0
                ? tr('{a} {cur} left for the next {d} days.', {'a': fmt(total - st.spend), 'cur': currency, 'd': daysLeft})
                : tr('{a} {cur} left.', {'a': fmt(total - st.spend), 'cur': currency}));
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

  // ------------------------------------------------------- taught formats

  String? _templatesJson;
  List<SmsTemplate> _templates = [];

  /// Message formats taught in Settings → Test or teach the SMS reader.
  List<SmsTemplate> get templates {
    final j = settings['smsTemplates'];
    if (j != _templatesJson) {
      _templatesJson = j;
      _templates = SmsTemplate.decodeList(j);
    }
    return _templates;
  }

  Future<void> _saveTemplates(List<SmsTemplate> list) async {
    await setSetting('smsTemplates', SmsTemplate.encodeList(list), notify: false);
    await Native.setPrefText('taughtSenders', list.map((t) => t.sender).where((s) => s.isNotEmpty).join('\n'));
  }

  /// Saves a taught format, re-reads waiting messages, then rescans this period so matching SMS appear.
  Future<String> addTemplate(SmsTemplate t) async {
    await _saveTemplates([t, ...templates]);
    return applySmsSettings();
  }

  Future<void> deleteTemplate(SmsTemplate t) async {
    await _saveTemplates(templates.where((x) => x.id != t.id).toList());
    await reparsePending(notify: false);
    notifyListeners();
  }

  bool _ignored(String body) {
    final lower = normalizeDigits(body).toLowerCase();
    return lines('ignoreKw').any(lower.contains);
  }

  /// What the app would extract from a message: a taught format first, then the built-in reader.
  /// Returns the result and whether a taught format was used.
  (ParsedSms?, bool) readMessage(String body, {String sender = ''}) {
    if (_ignored(body)) return (null, false);
    for (final t in templates) {
      if (!t.senderMatches(sender)) continue;
      final p = t.apply(body, currency: currencyCode);
      if (p != null) return (p, true);
    }
    return (parseSms(body, ignore: lines('ignoreKw'), income: lines('incomeKw'), currency: currencyCode), false);
  }

  /// Whether a message passes the sender filters and keyword rules. Returns the parse result if it does.
  ParsedSms? _accept(String sender, String body) {
    final allow = lines('senders');
    if (_senderIn(sender, lines('blockedSenders'))) return null;
    final allowed = allow.isEmpty || _senderIn(sender, allow);
    // a format you taught wins over the built-in reader (one tied to a sender ignores the sender list)
    if (templates.isNotEmpty && !_ignored(body)) {
      for (final t in templates) {
        if (t.sender.isEmpty ? !allowed : !t.senderMatches(sender)) continue;
        final p = t.apply(body, currency: currencyCode);
        if (p != null) return p;
      }
    }
    if (!allowed) return null;
    if (allow.isEmpty && !looksLikeTransaction(body, currency: currencyCode)) return null;
    return parseSms(body, ignore: lines('ignoreKw'), income: lines('incomeKw'), currency: currencyCode);
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
        return tr('SMS access is off. Allow it when asked, or in Android Settings → Apps → Household Ledger → Permissions.');
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
          return tr('SMS before {date} are switched off, because imported statements cover that time. '
              'Change it in Settings → SMS start date.', {'date': '${shortDate(start)} ${start.year}'});
        }
        since = max(since, cut);
      }
      final messages = await Native.readSms(since, untilMillis: until);
      var added = 0, matched = 0, linked = 0;
      final autoAdded = <Txn>[];
      var newest = int.tryParse(settings['smsLastScan'] ?? '') ?? 0;

      for (final msg in messages) {
        final date = (msg['date'] as num).toInt();
        newest = max(newest, date);
        final sender = (msg['address'] ?? '').toString();
        final body = (msg['body'] ?? '').toString();
        final parsed = _accept(sender, body);
        if (parsed == null) continue;
        matched++;
        final accountId = accountFor(body);
        final key = '$sender|$date';
        final exists = await db.query('sms_inbox', columns: ['id'], where: 'sms_key = ?', whereArgs: [key]);
        if (exists.isNotEmpty) continue;
        // Already entered by hand or imported from a statement? Link it instead of adding it twice.
        final linkedId = await _linkToExisting(key, date, parsed, accountId: accountId);
        if (linkedId != null) {
          await db.insert('sms_inbox', {
            'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
            'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'confirmed',
            'category_id': linkedId, 'account_id': accountId,
          });
          linked++;
          continue;
        }
        // A merchant you've already categorised goes straight into your entries.
        final known = autoConfirm ? learnedCategory(parsed.merchant, parsed.kind) : null;
        if (known != null) {
          final t = Txn(kind: parsed.kind, amount: parsed.amount, categoryId: known,
              date: isoDate(DateTime.fromMillisecondsSinceEpoch(date)), merchant: parsed.merchant,
              source: 'sms', smsKey: key, accountId: accountId);
          await db.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
          await db.insert('sms_inbox', {
            'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
            'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'confirmed',
            'category_id': known, 'account_id': accountId,
          });
          autoAdded.add(t);
          continue;
        }
        await db.insert('sms_inbox', {
          'sms_key': key, 'sender': sender, 'body': body, 'received_at': date,
          'amount': parsed.amount, 'kind': parsed.kind, 'merchant': parsed.merchant, 'status': 'pending',
          'category_id': suggestCategory(parsed.merchant, body, parsed.kind), 'account_id': accountId,
        });
        added++;
      }
      if (!ranged || until == null || until >= newest) {
        await setSetting('smsLastScan', '$newest', notify: false);
      }
      await _loadPending();
      if (linked > 0 || autoAdded.isNotEmpty) await _loadTxns();
      for (final t in autoAdded) {
        await checkAlerts(t);
      }
      if (autoAdded.isNotEmpty) lastAutoAdded += autoAdded.length;
      final window = ranged
          ? ' ${tr('between {a} and {b}', {'a': from != null ? shortDate(from) : tr('the start'), 'b': to != null ? shortDate(to) : tr('today')})}'
          : '';
      var linkNote = linked > 0
          ? ' ${tr('{n} matched entries you already had, so they weren\'t added again.', {'n': linked})}'
          : '';
      if (autoAdded.isNotEmpty) {
        linkNote += ' ${tr('{n} from merchants you\'ve categorised were added automatically.', {'n': autoAdded.length})}';
      }
      if (added == 0) {
        return matched == 0
            ? tr('No bank transactions found{w} ({n} messages checked).', {'w': window, 'n': messages.length})
            : '${tr('No new transactions{w}.', {'w': window})}$linkNote'
                '${linked == 0 ? ' ${tr('{n} were already reviewed.', {'n': matched})}' : ''}';
      }
      return '${trn(added, '{n} new transaction to review{w}.', '{n} new transactions to review{w}.', {'w': window})}$linkNote';
    } catch (e) {
      return tr('Could not read messages ({e}).', {'e': e});
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// Finds an imported or manual entry with the same day, direction and amount that no SMS is linked to yet,
  /// links this SMS to it, and returns its category id. Returns null when there is no such entry.
  Future<int?> _linkToExisting(String key, int receivedAt, ParsedSms parsed, {int? accountId}) async {
    final day = isoDate(DateTime.fromMillisecondsSinceEpoch(receivedAt));
    final rows = await db.query('txns',
        columns: ['id', 'category_id', 'merchant', 'account_id'],
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
          if (r['account_id'] == null && accountId != null) 'account_id': accountId,
        },
        where: 'id = ?',
        whereArgs: [r['id']]);
    return r['category_id'] as int;
  }

  /// Date range of the last manual range scan; Review shows only items in it until cleared.
  (DateTime, DateTime)? reviewWindow;

  /// Account filter on the Review tab: null = all, -1 = messages without an account.
  int? reviewAccount;

  void setReviewAccount(int? id) {
    reviewAccount = id;
    notifyListeners();
  }

  bool _inReviewAccount(SmsItem p) {
    final f = reviewAccount;
    if (f == null) return true;
    if (f == -1) return account(p.accountId) == null;
    return p.accountId == f;
  }

  void clearReviewWindow() {
    reviewWindow = null;
    notifyListeners();
  }

  List<SmsItem> get visiblePending {
    final w = reviewWindow;
    if (w == null) return pending.where(_inReviewAccount).toList();
    final a = DateTime(w.$1.year, w.$1.month, w.$1.day).millisecondsSinceEpoch;
    final b = DateTime(w.$2.year, w.$2.month, w.$2.day, 23, 59, 59, 999).millisecondsSinceEpoch;
    return pending.where((p) => p.receivedAt >= a && p.receivedAt <= b && _inReviewAccount(p)).toList();
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
      final catId = await _linkToExisting(it.smsKey, it.receivedAt, ParsedSms(it.amount, it.kind, it.merchant),
          accountId: it.accountId);
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
        'account_id': it.accountId ?? accountFor(it.body),
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
      if (looksLikeTransaction((m['body'] ?? '').toString(), currency: currencyCode)) counts[sender] = (counts[sender] ?? 0) + 1;
    }
    final out = counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Confirms one SMS. Returns how many other waiting SMS from the same merchant were added automatically.
  Future<int> confirmSms(SmsItem it,
      {required double amount,
      required String kind,
      required int categoryId,
      required String merchant,
      required String date,
      String note = '',
      bool remember = true,
      int? accountId}) async {
    final t = Txn(kind: kind, amount: amount, categoryId: categoryId, date: date,
        merchant: merchant.trim(), note: note.trim(), source: 'sms', smsKey: it.smsKey,
        accountId: accountId ?? it.accountId);
    await db.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update('sms_inbox', {'status': 'confirmed', 'category_id': categoryId}, where: 'id = ?', whereArgs: [it.id]);
    final others = remember ? await learnRule(merchant, categoryId, notify: false) : 0;
    await _loadTxns();
    await _loadPending();
    notifyListeners();
    await checkAlerts(t);
    return others;
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

  bool get autoConfirm => settings['autoConfirm'] != '0';

  /// SMS added automatically since the Review banner was last dismissed.
  int lastAutoAdded = 0;

  void dismissAutoBanner() {
    lastAutoAdded = 0;
    notifyListeners();
  }

  /// Card settlements and moves between your own accounts are not spending.
  static const _transferWords = [
    'between accounts', 'between your accounts', 'own account', 'card payment', 'credit card payment',
    'advance payment', 'transfer to own', 'تحويل بين حسابات', 'تحويل داخلي', 'عملية تحويل داخلية',
    'سداد بطاقة', 'سداد البطاقة', 'دفعة مقدمة',
  ];

  bool looksLikeOwnTransfer(String body) {
    final b = body.toLowerCase();
    return _transferWords.any(b.contains);
  }

  /// Category from a rule you taught (not the built-in keyword list), matched on the merchant name.
  int? learnedCategory(String merchant, String kind) {
    final m = merchant.toLowerCase().trim();
    if (m.isEmpty) return null;
    for (final r in rules) {
      if (!r.learned) continue;
      final c = cat(r.categoryId);
      if (c == null || c.archived || c.kind != kind) continue;
      if (m.contains(r.keyword)) return c.id;
    }
    return null;
  }

  /// Remembers the merchant's category and applies it to SMS still waiting in Review:
  /// they are added automatically (or just re-suggested when auto-adding is off).
  /// Returns how many waiting SMS were added.
  Future<int> learnRule(String merchant, int categoryId, {bool notify = true}) async {
    final key = merchantKey(merchant);
    if (key.length < 3) return 0;
    await db.insert('rules', {'keyword': key, 'category_id': categoryId, 'learned': 1},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _loadRules();
    final n = await _applyRuleToPending(key, categoryId);
    if (notify) notifyListeners();
    return n;
  }

  Future<int> _applyRuleToPending(String key, int categoryId) async {
    final c = cat(categoryId);
    if (c == null) return 0;
    final rows = await db.query('sms_inbox', where: 'status = ?', whereArgs: ['pending']);
    final added = <Txn>[];
    for (final r in rows) {
      final it = SmsItem.fromMap(r);
      if (it.kind != c.kind || !it.merchant.toLowerCase().contains(key)) continue;
      if (autoConfirm) {
        final t = Txn(kind: it.kind, amount: it.amount, categoryId: categoryId,
            date: isoDate(DateTime.fromMillisecondsSinceEpoch(it.receivedAt)), merchant: it.merchant,
            source: 'sms', smsKey: it.smsKey, accountId: it.accountId);
        await db.insert('txns', t.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.update('sms_inbox', {'status': 'confirmed', 'category_id': categoryId}, where: 'id = ?', whereArgs: [it.id]);
        added.add(t);
      } else {
        await db.update('sms_inbox', {'category_id': categoryId}, where: 'id = ?', whereArgs: [it.id]);
      }
    }
    if (added.isNotEmpty) {
      await _loadTxns();
      for (final t in added) {
        await checkAlerts(t);
      }
    }
    await _loadPending();
    return added.length;
  }

  /// Other entries from the same merchant that sit in a different category than [t].
  List<Txn> sameMerchantElsewhere(Txn t) {
    final key = merchantKey(t.merchant);
    if (key.length < 3) return [];
    return txns.where((x) {
      if (x.id == t.id || x.kind != t.kind || x.categoryId == t.categoryId || x.merchant.isEmpty) return false;
      final k = merchantKey(x.merchant);
      return x.merchant.toLowerCase().contains(key) || (k.length >= 4 && key.contains(k));
    }).toList();
  }

  Future<void> moveToCategory(List<Txn> list, int categoryId) async {
    final batch = db.batch();
    for (final t in list) {
      batch.update('txns', {'category_id': categoryId}, where: 'id = ?', whereArgs: [t.id]);
    }
    await batch.commit(noResult: true);
    await _loadTxns();
    notifyListeners();
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
    final out = StringBuffer('date,type,category,amount,merchant,note,account\n');
    for (final t in txns.reversed) {
      out.writeln([t.date, t.kind, cat(t.categoryId)?.name ?? '', fmtAuto(t.amount).replaceAll(',', ''),
        t.merchant, t.note, account(t.accountId)?.name ?? ''].map((v) => q(v.toString())).join(','));
    }
    return out.toString();
  }

  /// Accepts this app's export and the web ledger export (date,type,category,amount_sar,note).
  Future<String> importCsv(String text) async {
    final rows = _parseCsv(text.trim());
    if (rows.length < 2) return tr('Nothing to import. Paste rows with a header line first.');
    final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(List<String> names) => head.indexWhere((h) => names.contains(h));
    final iDate = col(['date']), iType = col(['type', 'kind']), iCat = col(['category']);
    final iAmt = col(['amount', 'amount_sar']), iNote = col(['note']), iMer = col(['merchant']);
    final iAcc = col(['account', 'card']);
    int? accountNamed(String n) {
      final k = n.trim().toLowerCase();
      if (k.isEmpty) return null;
      for (final a in accounts) {
        if (a.name.toLowerCase() == k || a.digitList.contains(k)) return a.id;
      }
      return null;
    }
    if (iDate < 0 || iAmt < 0) return tr('The header needs at least "date" and "amount" columns.');
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
      final fallback = catByName(kind == 'income' ? 'Other income' : 'Other');
      if (c == null || c.id == fallback?.id) {
        final learned = learnedCategory(at(iMer).isNotEmpty ? at(iMer) : at(iNote), kind);
        if (learned != null) c = cat(learned);
      }
      c ??= fallback ?? active(kind).first;
      kind = c.kind;
      batch.insert('txns', Txn(kind: kind, amount: amount.abs(), categoryId: c.id, date: date,
          note: at(iNote), merchant: at(iMer), source: 'import', accountId: accountNamed(at(iAcc))).toMap());
      added++;
    }
    await batch.commit(noResult: true);
    final linkedPending = await _linkPendingToEntries();
    await _loadTxns();
    await _loadPending();
    notifyListeners();
    final parts = <String>[
      trn(added, 'Imported {n} entry', 'Imported {n} entries'),
      if (duplicates > 0) tr('{n} already in the app were skipped', {'n': duplicates}),
      if (skipped > 0) tr('{n} unreadable rows ignored', {'n': skipped}),
      if (linkedPending > 0) tr('{n} waiting SMS matched imported entries and were cleared from Review', {'n': linkedPending}),
    ];
    return '${parts.join(isAr ? '، ' : ', ')}.';
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
    out.addAll(_fundLines(per));
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
      final amount = fmt(l.remaining > 0 ? l.remaining : l.target);
      await Native.notify(
          30000 + l.item.id,
          tr(l.item.kind == 'save' ? 'Set aside: {t}' : 'Pay: {t}', {'t': l.item.title}),
          l.due!.isBefore(today)
              ? tr('{a} {cur} was due on {d}. Tick it in your plan once done.',
                  {'a': amount, 'cur': currency, 'd': shortDate(l.due!)})
              : tr('{a} {cur} is due today. Tick it in your plan once done.', {'a': amount, 'cur': currency}));
    }
  }

  // ------------------------------------------------------- accounts & cards

  List<Account> accounts = [];

  Future<void> _loadAccounts() async {
    accounts = (await db.query('accounts', orderBy: 'sort, id')).map(Account.fromMap).toList();
  }

  List<Account> get activeAccounts => accounts.where((a) => !a.archived).toList();

  Account? account(int? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  int? accountFor(String body) => matchAccount(body, accounts);

  /// Account last used for a manual entry, so the next one starts there.
  int? get lastAccountId {
    final id = int.tryParse(settings['lastAccount'] ?? '');
    return account(id)?.archived == false ? id : null;
  }

  /// Saves an account. Entries and waiting SMS that mention its digits and have no account yet get it.
  /// Returns how many existing entries were linked.
  Future<int> saveAccount(Account a) async {
    if (a.id == 0) {
      a.sort = accounts.isEmpty ? 0 : accounts.map((x) => x.sort).reduce(max) + 1;
      a.color = palette[accounts.length % palette.length];
      a.id = await db.insert('accounts', a.toMap());
    } else {
      await db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
    }
    await _loadAccounts();
    var linked = 0;
    if (a.digitList.isNotEmpty && !a.archived) {
      final rows = await db.query('sms_inbox', columns: ['id', 'sms_key', 'body', 'status'], where: 'account_id IS NULL');
      final batch = db.batch();
      for (final r in rows) {
        if (matchAccount((r['body'] as String?) ?? '', [a]) == null) continue;
        batch.update('sms_inbox', {'account_id': a.id}, where: 'id = ?', whereArgs: [r['id']]);
        if (r['status'] == 'confirmed') {
          batch.update('txns', {'account_id': a.id},
              where: 'sms_key = ? AND account_id IS NULL', whereArgs: [r['sms_key']]);
          linked++;
        }
      }
      await batch.commit(noResult: true);
      await _loadTxns();
      await _loadPending();
    }
    notifyListeners();
    return linked;
  }

  /// Puts the given entries on one account.
  Future<void> assignAccount(List<Txn> list, int accountId) async {
    final batch = db.batch();
    for (final t in list) {
      if (t.id == null) continue;
      batch.update('txns', {'account_id': accountId}, where: 'id = ?', whereArgs: [t.id]);
      if (t.smsKey != null) {
        batch.update('sms_inbox', {'account_id': accountId}, where: 'sms_key = ?', whereArgs: [t.smsKey]);
      }
    }
    await batch.commit(noResult: true);
    await _loadTxns();
    notifyListeners();
  }

  /// Removes an account; its entries stay, without an account.
  Future<void> deleteAccount(Account a) async {
    await db.update('txns', {'account_id': null}, where: 'account_id = ?', whereArgs: [a.id]);
    await db.update('sms_inbox', {'account_id': null}, where: 'account_id = ?', whereArgs: [a.id]);
    await db.delete('accounts', where: 'id = ?', whereArgs: [a.id]);
    await _loadAccounts();
    await _loadTxns();
    await _loadPending();
    notifyListeners();
  }

  /// Card/account numbers seen in bank messages that aren't linked to an account yet, most frequent first.
  Future<List<(String, int)>> unnamedCards() async {
    final known = {for (final a in accounts) ...a.digitList};
    final rows = await db.query('sms_inbox', columns: ['body'], where: "status != 'ignored'");
    final counts = <String, int>{};
    for (final r in rows) {
      for (final d in cardDigitsIn((r['body'] as String?) ?? '')) {
        if (known.any((k) => k.endsWith(d) || d.endsWith(k))) continue;
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    final out = counts.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  /// Spending and income per account in a period. Key null = entries without an account.
  Map<int?, (double, double)> byAccount(Period per) {
    final out = <int?, (double, double)>{};
    for (final t in txns) {
      if (!per.contains(t.date)) continue;
      final cur = out[t.accountId] ?? (0.0, 0.0);
      final saving = t.kind == 'expense' && (cat(t.categoryId)?.isSaving ?? false);
      if (saving) continue;
      out[t.accountId] = t.kind == 'income' ? (cur.$1, cur.$2 + t.amount) : (cur.$1 + t.amount, cur.$2);
    }
    return out;
  }

  String get userName => settings['userName']?.trim() ?? '';

  // ------------------------------------------------------ yearly expenses

  List<Fund> funds = [];
  /// period -> fund id -> kind ('save' | 'pay') -> (amount, previous due date, previous saved)
  Map<String, Map<int, Map<String, (double, String?, double?)>>> fundStatus = {};

  Future<void> _loadFunds() async {
    funds = (await db.query('funds', orderBy: 'due_date, id')).map(Fund.fromMap).toList();
    fundStatus = {};
    for (final r in await db.query('fund_status')) {
      fundStatus
          .putIfAbsent(r['period'] as String, () => {})
          .putIfAbsent(r['fund_id'] as int, () => {})[r['kind'] as String] =
          ((r['amount'] as num).toDouble(), r['prev_due'] as String?, (r['prev_saved'] as num?)?.toDouble());
    }
  }

  List<Fund> get activeFunds => funds.where((f) => !f.archived).toList();

  Future<void> saveFund(Fund f) async {
    if (f.id == 0) {
      f.id = await db.insert('funds', f.toMap());
    } else {
      await db.update('funds', f.toMap(), where: 'id = ?', whereArgs: [f.id]);
    }
    await _loadFunds();
    notifyListeners();
  }

  Future<void> deleteFund(Fund f) async {
    await db.delete('funds', where: 'id = ?', whereArgs: [f.id]);
    await db.delete('fund_status', where: 'fund_id = ?', whereArgs: [f.id]);
    await _loadFunds();
    notifyListeners();
  }

  Period get _currentPeriod => periodFor(DateTime.now(), cycleStartDay);

  /// What to set aside this month for [f] (0 when it is already fully saved).
  double fundMonthly(Fund f, {Period? from}) {
    final cur = _currentPeriod;
    var start = from ?? cur;
    if (from == null && fundStatus[cur.key]?[f.id]?['save'] != null) start = cur.next;
    return monthlySetAside(amount: f.amount, savedBefore: f.saved, from: start, due: f.due, startDay: cycleStartDay);
  }

  List<PlanLine> _fundLines(Period per) {
    final cur = _currentPeriod;
    final out = <PlanLine>[];
    for (final f in funds) {
      final st = fundStatus[per.key]?[f.id];
      PlanLine line(String kind, double target, bool done, DateTime? due, {bool pay = false}) => PlanLine(
          PlanItem(id: -f.id, title: f.title, kind: kind, amount: target, startPeriod: per.key, categoryId: null),
          target, 0, done, false, due, fund: f, fundPay: pay);
      final paid = st?['pay'];
      if (paid != null) {
        out.add(line('pay', paid.$1, true, paid.$2 == null ? null : parseIso(paid.$2!), pay: true));
        continue;
      }
      if (f.archived) continue;
      final duePer = periodFor(f.due, cycleStartDay);
      final cmp = per.key.compareTo(duePer.key);
      if (cmp == 0 || (cmp > 0 && per.key == cur.key)) {
        final need = f.amount - f.saved;
        out.add(line('pay', need > 0 ? need : 0, false, f.due, pay: true));
      } else if (cmp < 0) {
        final saved = st?['save'];
        if (saved != null) {
          out.add(line('save', saved.$1, true, null));
        } else if (per.key.compareTo(cur.key) >= 0) {
          final amount = fundMonthly(f, from: per.key == cur.key ? cur : null);
          if (amount > 0) out.add(line('save', amount, false, null));
        }
      } else if (f.repeatMonths > 0 && per.key.compareTo(cur.key) > 0) {
        // after this due date: the next cycle is already being saved for
        out.add(line('save', (f.amount / f.repeatMonths).ceilToDouble(), false, null));
      }
    }
    return out;
  }

  /// Ticks (or unticks) this month's set-aside for a yearly expense.
  Future<void> setFundSaved(Period per, Fund f, bool done, double amount) async {
    final st = fundStatus[per.key]?[f.id]?['save'];
    if (done && st == null) {
      await db.insert('fund_status', {'period': per.key, 'fund_id': f.id, 'kind': 'save', 'amount': amount},
          conflictAlgorithm: ConflictAlgorithm.replace);
      f.saved += amount;
    } else if (!done && st != null) {
      await db.delete('fund_status', where: 'period = ? AND fund_id = ? AND kind = ?', whereArgs: [per.key, f.id, 'save']);
      f.saved = (f.saved - st.$1).clamp(0, double.infinity).toDouble();
    } else {
      return;
    }
    await db.update('funds', {'saved': f.saved}, where: 'id = ?', whereArgs: [f.id]);
    await _loadFunds();
    notifyListeners();
  }

  /// Marks a yearly expense as paid: it moves to its next due date (or ends if it was one-off).
  Future<void> markFundPaid(Period per, Fund f, bool paid) async {
    final st = fundStatus[per.key]?[f.id]?['pay'];
    if (paid && st == null) {
      await db.insert('fund_status', {
        'period': per.key, 'fund_id': f.id, 'kind': 'pay', 'amount': f.amount,
        'prev_due': f.dueDate, 'prev_saved': f.saved,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (f.repeatMonths > 0) {
        f.dueDate = isoDate(addMonths(f.due, f.repeatMonths));
        f.saved = (f.saved - f.amount).clamp(0, double.infinity).toDouble();
      } else {
        f.archived = true;
      }
    } else if (!paid && st != null) {
      await db.delete('fund_status', where: 'period = ? AND fund_id = ? AND kind = ?', whereArgs: [per.key, f.id, 'pay']);
      if (st.$2 != null) f.dueDate = st.$2!;
      if (st.$3 != null) f.saved = st.$3!;
      f.archived = false;
    } else {
      return;
    }
    await db.update('funds', f.toMap(), where: 'id = ?', whereArgs: [f.id]);
    await _loadFunds();
    notifyListeners();
  }

  // ------------------------------------------------------- backup / restore

  static const _backupTables = [
    'categories', 'txns', 'budget_overrides', 'sms_inbox', 'rules', 'settings', 'alerts', 'plan_items', 'plan_status',
    'accounts', 'funds', 'fund_status',
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

  /// Where the automatic backup is kept (a file the user chose once, e.g. on Google Drive).
  String get backupUri => settings['backupUri'] ?? '';
  String get backupWhere => settings['backupWhere'] ?? '';
  bool get backupFailed => settings['backupFailed'] == '1';

  /// Asks where to keep the backup, then writes the first copy. Returns false if cancelled or it failed.
  Future<bool> chooseBackupLocation() async {
    final uri = await Native.createBackupFile('household-ledger-backup.json');
    if (uri == null || uri.isEmpty) return false;
    final label = await Native.uriLabel(uri);
    final where = [label['where'] ?? '', label['name'] ?? ''].where((x) => x.isNotEmpty).join(' · ');
    await setSetting('backupUri', uri, notify: false);
    await setSetting('backupWhere', where, notify: false);
    await setSetting('autoBackup', '1', notify: false);
    return backupNow();
  }

  /// Overwrites the backup file with everything in the app.
  Future<bool> backupNow() async {
    if (backupUri.isEmpty) return false;
    final ok = await Native.writeUri(backupUri, await backupJson());
    if (ok) await setSetting('lastBackup', '${DateTime.now().millisecondsSinceEpoch}', notify: false);
    await setSetting('backupFailed', ok ? '0' : '1');
    return ok;
  }

  /// Daily automatic backup, run when the app opens.
  Future<void> autoBackupIfDue() async {
    if (backupUri.isEmpty || !flag('autoBackup') || txns.isEmpty) return;
    final d = daysSinceBackup;
    if (d != null && d < 1) return;
    await backupNow();
  }

  /// Share sheet with a backup file attached (WhatsApp, email, Drive…).
  Future<void> shareBackup() async {
    final now = DateTime.now();
    await Native.shareFile(
      content: await backupJson(),
      fileName: 'household-ledger-backup-${isoDate(now)}.json',
      subject: tr('Household Ledger backup {d}', {'d': isoDate(now)}),
      body: tr('Backup of {n} entries, created {d}. To restore: open the app, Settings → Backup & restore → Choose backup file.',
          {'n': txns.length, 'd': '${isoDate(now)} ${two(now.hour)}:${two(now.minute)}'}),
    );
    if (backupUri.isEmpty) await setSetting('lastBackup', '${now.millisecondsSinceEpoch}');
  }

  // ------------------------------------------------------------ start fresh

  /// Deletes every entry and the SMS review history; keeps categories, accounts, budgets, plan,
  /// yearly expenses and merchant rules. Bank SMS are read again only from [smsFrom].
  Future<void> deleteAllEntries(DateTime smsFrom) async {
    await db.transaction((tx) async {
      for (final t in ['txns', 'sms_inbox', 'alerts', 'plan_status', 'fund_status']) {
        await tx.delete(t);
      }
    });
    final start = DateTime(smsFrom.year, smsFrom.month, smsFrom.day).millisecondsSinceEpoch;
    await setSetting('smsStartFrom', '$start', notify: false);
    await setSetting('smsLastScan', '${start - 1}', notify: false);
    reviewWindow = null;
    lastAutoAdded = 0;
    await _loadTxns();
    await _loadPending();
    await _loadPlans();
    await _loadFunds();
    period = periodFor(DateTime.now(), cycleStartDay);
    notifyListeners();
  }

  /// Bumped when the app is reset, so the whole UI starts over with first-run setup.
  final resets = ValueNotifier<int>(0);
  bool firstRunDone = false;

  /// Deletes everything and returns to first-run setup.
  Future<void> resetApp() async {
    await Native.cancelReminder();
    for (final k in ['blockedSenders', 'taughtSenders', 'autoKeys']) {
      await Native.setPrefText(k, '');
    }
    final path = db.path;
    await db.close();
    await deleteDatabase(path);
    await init();
    firstRunDone = false;
    tab.value = 0;
    resets.value++;
    notifyListeners();
  }

  int? get daysSinceBackup {
    final ms = int.tryParse(settings['lastBackup'] ?? '');
    if (ms == null) return null;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms)).inDays;
  }

  bool get backupDue => txns.isNotEmpty && (backupFailed || daysSinceBackup == null || daysSinceBackup! >= 7);

  /// Summary of a backup file before restoring, or null if it isn't one.
  String? describeBackup(String text) {
    try {
      final d = jsonDecode(text);
      if (d is! Map || d['app'] != 'household_ledger') return null;
      final n = (d['txns'] as List?)?.length ?? 0;
      final created = (d['createdAt'] as String?)?.substring(0, 10) ?? tr('unknown date');
      return tr('Backup from {d} with {n} entries.', {'d': created, 'n': n});
    } catch (_) {
      return null;
    }
  }

  /// Replaces everything in the app with the backup's contents.
  Future<String> restoreBackup(String text) async {
    final d = jsonDecode(text) as Map<String, dynamic>;
    if (d['app'] != 'household_ledger') return tr('This file is not a Household Ledger backup.');
    final keepBackupInfo = {'backupEmail': settings['backupEmail'], 'lastBackup': settings['lastBackup']};
    final thisPhone = {
      for (final k in ['backupUri', 'backupWhere', 'autoBackup', 'backupFailed']) k: settings[k],
    };
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
    // the backup carries its own language choice
    final restoredLang = settings['lang']?.isNotEmpty == true ? settings['lang']! : 'system';
    setLanguage(restoredLang);
    language.value = restoredLang;
    for (final e in keepBackupInfo.entries) {
      if (e.value != null && (settings[e.key] ?? '').isEmpty) await setSetting(e.key, e.value!, notify: false);
    }
    // the backup location belongs to this phone, not to the phone the backup came from
    for (final e in thisPhone.entries) {
      await setSetting(e.key, e.value ?? '', notify: false);
    }
    await setSetting('onboarded', '1', notify: false);
    await _loadCategories();
    await _loadTxns();
    await _loadOverrides();
    await _loadRules();
    await _loadPending();
    await _loadPlans();
    await _loadAccounts();
    await _loadFunds();
    period = periodFor(DateTime.now(), cycleStartDay);
    await applyReminder();
    notifyListeners();
    return tr('Restored {n} entries.', {'n': txns.length});
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
