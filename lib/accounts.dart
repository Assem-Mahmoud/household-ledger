/// Accounts and cards the user names (Main account, Credit card, Savings…), matched to bank SMS
/// by the last digits of the card or account number that banks include in their messages.

import 'sms_parser.dart' show normalizeDigits;

class Account {
  int id;
  String name;
  String type; // 'bank' | 'credit' | 'savings' | 'cash' | 'wallet'
  String digits; // last digits used in SMS, comma-separated when one account has several cards
  int color;
  int sort;
  bool archived;

  Account({
    required this.id,
    required this.name,
    this.type = 'bank',
    this.digits = '',
    this.color = 0xFF0D6B5B,
    this.sort = 0,
    this.archived = false,
  });

  List<String> get digitList =>
      digits.split(RegExp(r'[,\s]+')).map((d) => d.replaceAll(RegExp(r'[^0-9]'), '')).where((d) => d.length >= 3).toList();

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int,
        name: (m['name'] as String?) ?? '',
        type: (m['type'] as String?) ?? 'bank',
        digits: (m['digits'] as String?) ?? '',
        color: (m['color'] as int?) ?? 0xFF0D6B5B,
        sort: (m['sort'] as int?) ?? 0,
        archived: ((m['archived'] as int?) ?? 0) == 1,
      );

  Map<String, Object?> toMap() =>
      {'name': name, 'type': type, 'digits': digits, 'color': color, 'sort': sort, 'archived': archived ? 1 : 0};
}

const accountTypes = [
  ('bank', 'Bank account / debit card'),
  ('credit', 'Credit card'),
  ('savings', 'Savings account'),
  ('wallet', 'Wallet (STC Pay, urpay…)'),
  ('cash', 'Cash'),
];

/// The account whose digits appear in the message as a stand-alone number
/// (not part of an amount, a date or a time). Null when none match.
int? matchAccount(String body, Iterable<Account> accounts) {
  final b = normalizeDigits(body);
  for (final a in accounts) {
    if (a.archived) continue;
    for (final d in a.digitList) {
      // not inside an amount (1,946.50), a date (19/46) or a time (19:46)
      if (RegExp('(?<![0-9])(?<![0-9][.,/:])$d(?![0-9])(?![.,/:][0-9])').hasMatch(b)) return a.id;
    }
  }
  return null;
}

final _cardDigits = RegExp(
  r'(?:card|بطاقة|بطاقتك|ending(?:\s+with)?|ends|acct|account|a/c|حساب|حسابك|عبر|مدى|mada|visa|فيزا|master|من|from|رقم|no\.?|xx+|\*+|#)'
  r'[^0-9\n]{0,12}?([0-9]{4})(?![0-9])(?![.,/:][0-9])',
  caseSensitive: false,
);

/// Card or account numbers (last 4 digits) mentioned in a bank message.
List<String> cardDigitsIn(String body) {
  final b = normalizeDigits(body);
  return {for (final m in _cardDigits.allMatches(b)) m.group(1)!}.toList();
}
