/// Plain data classes stored in SQLite.

class Category {
  int id;
  String name;
  String kind; // 'expense' | 'income'
  String grp; // 'need' | 'want' | 'save' | 'income'
  double budget; // template (default monthly) budget
  int color;
  int sort;
  bool archived;

  Category({
    required this.id,
    required this.name,
    required this.kind,
    required this.grp,
    this.budget = 0,
    required this.color,
    this.sort = 0,
    this.archived = false,
  });

  bool get isExpense => kind == 'expense';
  bool get isSaving => grp == 'save';

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int,
        name: m['name'] as String,
        kind: m['kind'] as String,
        grp: m['grp'] as String,
        budget: (m['budget'] as num?)?.toDouble() ?? 0,
        color: m['color'] as int,
        sort: (m['sort'] as int?) ?? 0,
        archived: ((m['archived'] as int?) ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'kind': kind,
        'grp': grp,
        'budget': budget,
        'color': color,
        'sort': sort,
        'archived': archived ? 1 : 0,
      };
}

class Txn {
  int? id;
  String kind; // 'expense' | 'income'
  double amount;
  int categoryId;
  String date; // yyyy-MM-dd
  String note;
  String merchant;
  String source; // 'manual' | 'sms' | 'import'
  String? smsKey;
  int createdAt;

  Txn({
    this.id,
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.merchant = '',
    this.source = 'manual',
    this.smsKey,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  String get label => merchant.isNotEmpty ? merchant : note;

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
        id: m['id'] as int,
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['category_id'] as int,
        date: m['date'] as String,
        note: (m['note'] as String?) ?? '',
        merchant: (m['merchant'] as String?) ?? '',
        source: (m['source'] as String?) ?? 'manual',
        smsKey: m['sms_key'] as String?,
        createdAt: (m['created_at'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'kind': kind,
        'amount': amount,
        'category_id': categoryId,
        'date': date,
        'note': note,
        'merchant': merchant,
        'source': source,
        'sms_key': smsKey,
        'created_at': createdAt,
      };
}

class SmsItem {
  final int id;
  final String smsKey;
  final String sender;
  final String body;
  final int receivedAt;
  final double amount;
  final String kind;
  final String merchant;
  final String status; // pending | confirmed | ignored
  final int? categoryId;

  SmsItem({
    required this.id,
    required this.smsKey,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.amount,
    required this.kind,
    required this.merchant,
    required this.status,
    this.categoryId,
  });

  factory SmsItem.fromMap(Map<String, Object?> m) => SmsItem(
        id: m['id'] as int,
        smsKey: m['sms_key'] as String,
        sender: (m['sender'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        receivedAt: (m['received_at'] as int?) ?? 0,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        kind: (m['kind'] as String?) ?? 'expense',
        merchant: (m['merchant'] as String?) ?? '',
        status: (m['status'] as String?) ?? 'pending',
        categoryId: m['category_id'] as int?,
      );
}

class Rule {
  final int id;
  final String keyword;
  final int categoryId;
  final bool learned;

  Rule({required this.id, required this.keyword, required this.categoryId, required this.learned});

  factory Rule.fromMap(Map<String, Object?> m) => Rule(
        id: m['id'] as int,
        keyword: m['keyword'] as String,
        categoryId: m['category_id'] as int,
        learned: ((m['learned'] as int?) ?? 0) == 1,
      );
}

class Insight {
  final String level; // good | warn | bad | info
  final String text;
  const Insight(this.level, this.text);
}

/// A monthly plan item: a bill to pay or an amount to set aside.
/// Recurring items have no [onlyPeriod]; one-off items belong to a single period.
class PlanItem {
  int id;
  String title;
  String kind; // 'pay' | 'save'
  double amount;
  int? dueDay; // 1–31, null = any time in the month
  int? categoryId; // when set, spending in this category ticks the item automatically
  String startPeriod; // first period key it applies to
  String? endPeriod; // last period key (inclusive) after it was stopped
  String? onlyPeriod; // one-off item for this period only
  int sort;

  PlanItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.amount,
    this.dueDay,
    this.categoryId,
    required this.startPeriod,
    this.endPeriod,
    this.onlyPeriod,
    this.sort = 0,
  });

  bool get recurring => onlyPeriod == null;

  bool appliesTo(String key) {
    if (onlyPeriod != null) return onlyPeriod == key;
    if (key.compareTo(startPeriod) < 0) return false;
    if (endPeriod != null && key.compareTo(endPeriod!) > 0) return false;
    return true;
  }

  factory PlanItem.fromMap(Map<String, Object?> m) => PlanItem(
        id: m['id'] as int,
        title: m['title'] as String,
        kind: (m['kind'] as String?) ?? 'pay',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        dueDay: m['due_day'] as int?,
        categoryId: m['category_id'] as int?,
        startPeriod: (m['start_period'] as String?) ?? '2000-01',
        endPeriod: m['end_period'] as String?,
        onlyPeriod: m['only_period'] as String?,
        sort: (m['sort'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        'title': title,
        'kind': kind,
        'amount': amount,
        'due_day': dueDay,
        'category_id': categoryId,
        'start_period': startPeriod,
        'end_period': endPeriod,
        'only_period': onlyPeriod,
        'sort': sort,
      };
}

/// One plan item in one period, with its progress.
class PlanLine {
  final PlanItem item;
  final double target; // this period's amount (override or item amount)
  final double progress; // auto progress from the linked category
  final bool manualDone;
  final bool overridden;
  final DateTime? due;

  PlanLine(this.item, this.target, this.progress, this.manualDone, this.overridden, this.due);

  bool get autoDone => item.categoryId != null && target > 0 && progress >= target - 0.01;
  bool get done => manualDone || autoDone;
  double get remaining => done ? 0 : (target - progress).clamp(0, double.infinity).toDouble();

  /// 'done' | 'overdue' | 'due' (within 3 days) | 'open'
  String get status {
    if (done) return 'done';
    if (due == null) return 'open';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isAfter(due!)) return 'overdue';
    if (due!.difference(today).inDays <= 3) return 'due';
    return 'open';
  }
}
