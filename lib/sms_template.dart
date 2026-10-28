/// Message formats the user teaches by marking the amount (and merchant) in a sample SMS.
/// Each format becomes two small patterns built from the words around the marks, so later
/// messages with a different amount, merchant, date or card number still match.

import 'dart:convert';

import 'sms_parser.dart';

const _amountGroup = r'([0-9][0-9,]*(?:\.[0-9]{1,3})?)';
const _context = 14; // characters of surrounding text kept as the anchor

class SmsTemplate {
  final String id;
  final String sender; // empty = any sender
  final String kind; // 'expense' | 'income'
  final String amountRe;
  final String merchantRe; // empty = use the built-in merchant reader
  final String sample;

  const SmsTemplate({
    required this.id,
    required this.sender,
    required this.kind,
    required this.amountRe,
    required this.merchantRe,
    required this.sample,
  });

  Map<String, Object> toJson() =>
      {'id': id, 'sender': sender, 'kind': kind, 'amountRe': amountRe, 'merchantRe': merchantRe, 'sample': sample};

  factory SmsTemplate.fromJson(Map<String, dynamic> m) => SmsTemplate(
        id: '${m['id'] ?? ''}',
        sender: '${m['sender'] ?? ''}',
        kind: m['kind'] == 'income' ? 'income' : 'expense',
        amountRe: '${m['amountRe'] ?? ''}',
        merchantRe: '${m['merchantRe'] ?? ''}',
        sample: '${m['sample'] ?? ''}',
      );

  static List<SmsTemplate> decodeList(String? json) {
    if (json == null || json.trim().isEmpty) return [];
    try {
      return (jsonDecode(json) as List)
          .map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((t) => t.amountRe.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeList(List<SmsTemplate> list) => jsonEncode(list.map((t) => t.toJson()).toList());

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]'), '');

  bool senderMatches(String from) {
    if (sender.isEmpty) return true;
    final a = _norm(from), b = _norm(sender);
    return a.isNotEmpty && b.isNotEmpty && (a.contains(b) || b.contains(a));
  }

  /// Reads [raw] with this format. Returns null when the message isn't in this format.
  ParsedSms? apply(String raw, {String currency = 'SAR'}) {
    final b = normalizeDigits(raw);
    RegExpMatch? a;
    try {
      a = RegExp(amountRe).firstMatch(b);
    } catch (_) {
      return null;
    }
    if (a == null) return null;
    final v = double.tryParse(a.group(1)!.replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    var merchant = '';
    if (merchantRe.isNotEmpty) {
      try {
        final m = RegExp(merchantRe).firstMatch(b);
        if (m != null) merchant = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      } catch (_) {}
    }
    if (merchant.isEmpty) merchant = findMerchant(b, currency: currency);
    if (merchant.length > 40) merchant = merchant.substring(0, 40).trim();
    return ParsedSms(v, kind, merchant);
  }

  /// Builds a format from [text] (already passed through normalizeDigits) and the marked ranges.
  /// Throws [FormatException] with a user-facing key when the marks can't be used.
  static SmsTemplate build({
    required String text,
    required (int, int) amount,
    (int, int)? merchant,
    required String kind,
    String sender = '',
  }) {
    // keep only the number inside the amount mark ("SAR 36.00" -> "36.00")
    final picked = text.substring(amount.$1, amount.$2);
    final n = RegExp(r'[0-9][0-9,]*(?:\.[0-9]+)?').firstMatch(picked);
    if (n == null) throw const FormatException('The amount mark has no number in it.');
    final aStart = amount.$1 + n.start, aEnd = amount.$1 + n.end;

    (int, int)? mer;
    if (merchant != null) {
      var s = merchant.$1, e = merchant.$2;
      while (s < e && text[s].trim().isEmpty) {
        s++;
      }
      while (e > s && text[e - 1].trim().isEmpty) {
        e--;
      }
      if (e > s) mer = (s, e);
      if (mer != null && mer.$1 < aEnd && aStart < mer.$2) {
        throw const FormatException('The amount and merchant marks overlap.');
      }
    }

    // amount: anchored on the text just before it, never reaching back into the merchant
    var from = aStart - _context < 0 ? 0 : aStart - _context;
    if (mer != null && mer.$2 <= aStart && mer.$2 > from) from = mer.$2;
    if (_letters(text.substring(from, aStart)) < 2) {
      from = aStart - 30 < 0 ? 0 : aStart - 30;
      if (mer != null && mer.$2 <= aStart && mer.$2 > from) from = mer.$2;
    }
    final before = text.substring(from, aStart);
    var amountRe = (before.trim().isEmpty && from == 0 ? r'^\s*' : _generalise(before)) + _amountGroup;
    if (mer != null && mer.$2 <= aStart && _letters(before) < 2) {
      // e.g. "CARREFOUR\nEGP 88": anchor the amount on the merchant line instead
      final mb = text.substring(mer.$1 - _context < 0 ? 0 : mer.$1 - _context, mer.$1);
      amountRe = '${_generalise(mb)}[^\\n]+?${_generalise(text.substring(mer.$2, aStart))}$_amountGroup';
    }

    var merchantRe = '';
    if (mer != null) {
      var mFrom = mer.$1 - _context < 0 ? 0 : mer.$1 - _context;
      if (aEnd <= mer.$1 && aEnd > mFrom) mFrom = aEnd;
      final mBefore = text.substring(mFrom, mer.$1);
      var mTo = mer.$2 + 8 > text.length ? text.length : mer.$2 + 8;
      final nl = text.indexOf('\n', mer.$2);
      if (nl >= 0 && nl < mTo) mTo = nl;
      if (aStart >= mer.$2 && aStart < mTo) mTo = aStart;
      final after = text.substring(mer.$2, mTo);
      var head = mBefore.isEmpty ? (mer.$1 == 0 ? r'^' : '') : _generalise(mBefore);
      if (aEnd <= mer.$1 && _letters(mBefore) < 2) {
        // merchant alone on the line under the amount: anchor it on the amount line
        head = '${_generalise(text.substring(aStart - _context < 0 ? 0 : aStart - _context, aStart))}'
            '[0-9][0-9,]*(?:\\.[0-9]{1,3})?${_generalise(text.substring(aEnd, mer.$1))}';
      }
      final tail = after.trim().isEmpty ? r'\s*(?:\n|$)' : _generalise(after);
      merchantRe = '$head([^\\n]+?)$tail';
    }

    final t = SmsTemplate(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: sender.trim(),
      kind: kind,
      amountRe: amountRe,
      merchantRe: merchantRe,
      sample: text,
    );
    // the format must read its own sample back
    final check = t.apply(text);
    if (check == null || (check.amount - double.parse(text.substring(aStart, aEnd).replaceAll(',', ''))).abs() > 0.0001) {
      throw const FormatException('Could not build a reliable format from this message.');
    }
    return t;
  }

  static int _letters(String s) => RegExp(r'[A-Za-zء-ي]').allMatches(s).length;

  /// Literal text with digits and spacing made flexible.
  static String _generalise(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (RegExp(r'[0-9]').hasMatch(ch)) {
        while (i < s.length && RegExp(r'[0-9]').hasMatch(s[i])) {
          i++;
        }
        out.write(r'[0-9]+');
      } else if (ch.trim().isEmpty) {
        while (i < s.length && s[i].trim().isEmpty) {
          i++;
        }
        out.write(r'\s+');
      } else {
        out.write(RegExp.escape(ch));
        i++;
      }
    }
    return out.toString();
  }
}
