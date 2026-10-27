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
