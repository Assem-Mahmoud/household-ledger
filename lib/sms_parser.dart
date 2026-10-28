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
  // card holds, promotions, limit changes, reward points and reminders are not money movements
  'temporary hold', 'hold of', 'pre-auth', 'preauth', 'حجز مبلغ', 'مبلغ محجوز',
  'up to ', 'يصل إلى', 'يصل الى', 'limited time', 'لفترة محدودة', 'special offer', 'عرض خاص',
  'limit has been', 'limit is now', 'limit updated', 'حد الشراء', 'تم تحديث الحد',
  'points on', 'you earned', 'is due', 'due on', 'reminder:', 'تذكير', 'مستحق السداد',
  // paying off the credit card is a transfer, not spending or income
  'received for your credit card', 'credit card payment received', 'سداد البطاقة الائتمانية', 'سداد بطاقة ائتمانية',
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

const _fx = r'(?<![A-Za-z])(USD|EUR|GBP|AED|BHD|KWD|QAR|OMR|EGP|TRY|JPY|CNY|INR)(?![A-Za-z])';
final _fxFirst = RegExp('$_fx\\s*[:：]?\\s*$_num', caseSensitive: false);
final _fxAfter = RegExp('$_num\\s*$_fx', caseSensitive: false);

// keyword must end at a word boundary, so "ATM" is not read as "at M"
const _wb = r'(?![A-Za-z\u0621-\u064A])';

final _merchantPatterns = [
  RegExp(r'(?:^|[\s\n])(?:at|merchant|biller|location|لدى|عند|التاجر|المتجر|اسم التاجر|المفوتر|الجهة|المكان|الموقع)' + _wb + r'\s*[:：]?\s*([^\n]+)', caseSensitive: false),
  // Al Rajhi online purchase: "لـEHSAN" (لـ = "to/for", merchant in Latin letters)
  RegExp(r'(?:^|[\s\n])ل\s*[:：]?\s*([A-Za-z0-9][^\n]*)'),
  RegExp(r'(?:^|[\s\n])(?:to|إلى|الى|المستفيد|beneficiary)\s*[:：]\s*([^\n]+)', caseSensitive: false),
  RegExp(r'(?:^|[\s\n])(?:from|من)\s*[:：]\s*([^\n]+)', caseSensitive: false),
  // "purchase of 437 SAR from SHEIN.COM using card" (merchant names are usually upper-case)
  RegExp(r'(?:^|[\s\n])(?:from|to|at)\s+([A-Z0-9][^\n]*)'),
  // inline Arabic: "حوالة واردة بمبلغ 2,500 ريال من فهد العتيبي إلى حسابك"
  RegExp(r'(?:^|[\s\n])(?:من|إلى|الى)\s+([^\n]+)'),
];

// words that end a merchant name ("SPOTIFY approved on card…", "ALDREES بواسطة بطاقة…")
final _merchantCut = RegExp(
  r'\s(?:on|using|via|with|by|from|for|card|approved|ending|was|is|account|completed|successfully|credited|debited|charged|ref|reference|total|بطاقة|بطاقتك|في|بتاريخ|date|تاريخ|بواسطة|باستخدام|عبر|إلى|الى|من)' + _wb,
  caseSensitive: false,
);
final _notMerchant = RegExp(r'^(?:your|account|card|حساب|حسابك|بطاق|رصيد)', caseSensitive: false);
// a line that is just an upper-case name, used when the bank gives no label
final _nameLine = RegExp(r"^[A-Z][A-Z0-9&'.\- ]{2,39}$");
final _nameLineStop = RegExp(r'\b(?:PURCHASE|POS|MADA|VISA|MASTERCARD|CARD|SAR|SR|ATM|APPLE PAY|ONLINE|TRANSFER|AMOUNT|BALANCE|DATE)\b');

String normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(ar[i], '$i').replaceAll(fa[i], '$i');
  }
  // drop bidi control marks and tatweel (Al Rajhi writes "بـSR 5", "لـEHSAN")
  out = out.replaceAll(RegExp('[\u200e\u200f\u202a-\u202e\u2066-\u2069\u0640]'), '');
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
  // no SAR amount: fall back to a foreign-currency amount (Review shows a hint to check it)
  final f = _fxFirst.firstMatch(b);
  if (f != null) return _toDouble(f.group(2));
  final g = _fxAfter.firstMatch(b);
  if (g != null) return _toDouble(g.group(1));
  return null;
}

/// Currency code when the only amount in the SMS is not in riyals, e.g. "USD"; otherwise null.
String? foreignCurrency(String raw) {
  final b = normalizeDigits(raw);
  if (_curFirst.hasMatch(b) || _numFirst.hasMatch(b)) return null;
  final f = _fxFirst.firstMatch(b);
  if (f != null) return f.group(1)!.toUpperCase();
  final g = _fxAfter.firstMatch(b);
  return g?.group(2)!.toUpperCase();
}

String findMerchant(String raw) {
  final b = normalizeDigits(raw);
  for (final p in _merchantPatterns) {
    for (final m in p.allMatches(b)) {
      var s = m.group(1)!.trim();
      // cut trailing clauses such as dates, amounts or "on 12/10"
      s = s.split(_merchantCut).first;
      s = s.split(RegExp(_cur, caseSensitive: false)).first;
      s = s.split(RegExp(r'\s\d{1,4}[-/]\d{1,2}[-/]\d{1,4}')).first;
      s = s.split(RegExp(r'\.(?:\s|$)')).first;
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      s = s.replaceAll(RegExp(r'^[:：\-\s]+|[.,;:\-\s]+$'), '');
      if (s.isEmpty || RegExp(r'^[\d\s:./\-*]+$').hasMatch(s) || _notMerchant.hasMatch(s)) continue;
      if (s.length > 40) s = s.substring(0, 40).trim();
      return s;
    }
  }
  for (final line in b.split('\n').skip(1)) {
    final t = line.trim();
    if (_nameLine.hasMatch(t) && !_nameLineStop.hasMatch(t)) return t;
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
