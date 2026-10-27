/// Rule-based parser for Saudi bank SMS (Arabic and English). No AI involved.
/// Every list here is a default; users can edit keywords in Settings.

class ParsedSms {
  final double amount;
  final String kind; // 'expense' | 'income'
  final String merchant;
  const ParsedSms(this.amount, this.kind, this.merchant);

  @override
  String toString() => 'ParsedSms($amount, $kind, "$merchant")';
}

const defaultIgnoreKeywords = [
  'otp', 'one time', 'one-time', 'verification', 'رمز التحقق', 'رمز التفعيل', 'كلمة المرور', 'password',
  'declined', 'مرفوض', 'رفض', 'لم تتم', 'failed', 'unsuccessful', 'غير ناجحة',
  'will be deducted', 'سيتم خصم', 'due date', 'تاريخ الاستحقاق', 'statement is ready', 'كشف الحساب',
];

const defaultIncomeKeywords = [
  'salary', 'راتب', 'deposit', 'إيداع', 'ايداع', 'credited', 'received', 'incoming', 'واردة', 'وارد',
  'refund', 'استرداد', 'reversal', 'cashback', 'استرجاع',
];

const transactionKeywords = [
  'purchase', 'شراء', 'pos', 'mada', 'مدى', 'payment', 'سداد', 'paid', 'دفع', 'withdraw', 'سحب',
  'transfer', 'حوالة', 'تحويل', 'debit', 'credit', 'خصم', 'إيداع', 'ايداع', 'deposit', 'salary', 'راتب',
  'refund', 'استرداد', 'card', 'بطاقة', 'apple pay', 'online', 'atm', 'صراف', 'amount', 'مبلغ',
];

const _balanceWords = [
  'balance', 'bal ', 'bal:', 'رصيد', 'available', 'متاح', 'limit', 'الحد', 'remaining', 'المتبقي', 'outstanding',
];

const _cur = r'(?:(?<![A-Za-z])(?:SAR|SR)(?![A-Za-z])|ر\.?\s?س\.?|ريال)';
const _num = r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)';

final _labelled = RegExp(
  '(?:amount|amt|مبلغ|بمبلغ|المبلغ|القيمة|قيمة)\\s*[:：]?\\s*(?:$_cur)?\\s*$_num',
  caseSensitive: false,
);
final _curFirst = RegExp('$_cur\\s*[:：]?\\s*$_num', caseSensitive: false);
final _numFirst = RegExp('$_num\\s*$_cur', caseSensitive: false);

final _merchantPatterns = [
  RegExp(r'(?:^|[\s\n])(?:at|merchant|لدى|عند|التاجر|المتجر|اسم التاجر)\s*[:：]?\s*([^\n]+)', caseSensitive: false),
  RegExp(r'(?:^|[\s\n])(?:to|إلى|الى|المستفيد|beneficiary)\s*[:：]\s*([^\n]+)', caseSensitive: false),
  RegExp(r'(?:^|[\s\n])(?:from|من)\s*[:：]\s*([^\n]+)', caseSensitive: false),
  // "purchase of 437 SAR from SHEIN.COM using card" (merchant names are usually upper-case)
  RegExp(r'(?:^|[\s\n])(?:from|to|at)\s+([A-Z0-9][^\n]*)'),
];

String normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  return out.replaceAll('٫', '.').replaceAll('٬', ',');
}

double? _toDouble(String? s) => s == null ? null : double.tryParse(s.replaceAll(',', ''));

bool _containsAny(String lower, Iterable<String> words) =>
    words.any((w) => w.trim().isNotEmpty && lower.contains(w.trim().toLowerCase()));

/// True when the SMS looks like a money movement (used when no bank senders are configured).
bool looksLikeTransaction(String raw) {
  final body = normalizeDigits(raw);
  final lower = body.toLowerCase();
  return _containsAny(lower, transactionKeywords) && findAmount(body) != null;
}

double? findAmount(String raw) {
  final b = normalizeDigits(raw);
  final m = _labelled.firstMatch(b);
  if (m != null) {
    final v = _toDouble(m.group(1));
    if (v != null && v > 0) return v;
  }
  for (final p in [_curFirst, _numFirst]) {
    for (final match in p.allMatches(b)) {
      final from = match.start - 25 < 0 ? 0 : match.start - 25;
      final before = b.substring(from, match.start).toLowerCase();
      if (_balanceWords.any(before.contains)) continue;
      final v = _toDouble(match.group(1));
      if (v != null && v > 0) return v;
    }
  }
  return null;
}

String findMerchant(String raw) {
  final b = normalizeDigits(raw);
  for (final p in _merchantPatterns) {
    for (final m in p.allMatches(b)) {
      var s = m.group(1)!.trim();
      // cut trailing clauses such as dates, amounts or "on 12/10"
      s = s.split(RegExp(r'\s(?:on|using|via|with|by|في|بتاريخ|date|تاريخ)\s', caseSensitive: false)).first;
      s = s.split(RegExp(_cur, caseSensitive: false)).first;
      s = s.split(RegExp(r'\s\d{1,4}[-/]\d{1,2}[-/]\d{1,4}')).first;
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      s = s.replaceAll(RegExp(r'^[:：\-\s]+|[.,;:\-\s]+$'), '');
      if (s.isEmpty || RegExp(r'^[\d\s:./\-*]+$').hasMatch(s)) continue;
      if (s.length > 40) s = s.substring(0, 40).trim();
      return s;
    }
  }
  return '';
}

ParsedSms? parseSms(
  String raw, {
  List<String> ignore = defaultIgnoreKeywords,
  List<String> income = defaultIncomeKeywords,
}) {
  final body = normalizeDigits(raw);
  final lower = body.toLowerCase();
  if (_containsAny(lower, ignore)) return null;
  final amount = findAmount(body);
  if (amount == null) return null;
  final kind = _containsAny(lower, income) ? 'income' : 'expense';
  return ParsedSms(amount, kind, findMerchant(body));
}

/// Short, stable key for remembering which category a merchant belongs to.
String merchantKey(String merchant) {
  var s = merchant.toLowerCase().replaceAll(RegExp(r'[^a-z؀-ۿ\s]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return '';
  final words = s.split(' ').where((w) => w.length > 1).take(2).toList();
  return words.join(' ');
}
