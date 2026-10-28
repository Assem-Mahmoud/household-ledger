import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/sms_parser.dart';
import 'package:household_ledger/sms_template.dart';

(int, int) _mark(String text, String part) {
  final i = text.indexOf(part);
  expect(i, greaterThanOrEqualTo(0), reason: 'mark "$part" not found');
  return (i, i + part.length);
}

void main() {
  final cases = <(String, String, String, List<(String, double, String)>)>[
    (
      'CARREFOUR MAADI\nEGP 88.00\nCard 4521',
      '88.00',
      'CARREFOUR MAADI',
      [('SPINNEYS ZAYED\nEGP 1,020.00\nCard 4521', 1020.0, 'SPINNEYS ZAYED')],
    ),
    (
      'عملية شراء من بطاقتك 4521 بقيمة 340.00 جم لدى مطعم الشبراوي يوم 28/10 الساعة 14:30',
      '340.00 جم',
      'مطعم الشبراوي',
      [
        ('عملية شراء من بطاقتك 4521 بقيمة 1,275.50 جم لدى صيدلية العزبي يوم 3/11 الساعة 09:05', 1275.5, 'صيدلية العزبي'),
        ('عملية شراء من بطاقتك 9999 بقيمة 15 جم لدى KFC MAADI يوم 30/11 الساعة 22:10', 15.0, 'KFC MAADI'),
      ],
    ),
    (
      'Txn Alert\nAcct xx4521\nDr EGP 250.00\nCARREFOUR CITY STARS\n28-Oct-26 13:05\nAvl Bal EGP 9,120.33',
      '250.00',
      'CARREFOUR CITY STARS',
      [('Txn Alert\nAcct xx4521\nDr EGP 1,999.99\nB.TECH NASR CITY\n02-Nov-26 10:00\nAvl Bal EGP 7,000.00', 1999.99, 'B.TECH NASR CITY')],
    ),
    (
      'BANQUE: 4521 debit 120.00 EGP ref 778899 merchant UBER TRIP balance 3000.00',
      '120.00',
      'UBER TRIP',
      [('BANQUE: 4521 debit 64.25 EGP ref 112233 merchant TALABAT EGYPT balance 2935.75', 64.25, 'TALABAT EGYPT')],
    ),
  ];

  for (final (sample, amount, merchant, others) in cases) {
    test('taught format: ${sample.split('\n').first}', () {
      final text = normalizeDigits(sample);
      final t = SmsTemplate.build(
          text: text, amount: _mark(text, amount), merchant: _mark(text, merchant), kind: 'expense');
      final again = SmsTemplate.decodeList(SmsTemplate.encodeList([t])).single;
      for (final (body, a, m) in others) {
        final p = again.apply(body, currency: 'EGP');
        expect(p, isNotNull, reason: body);
        expect(p!.amount, a);
        expect(p.merchant, m);
        expect(p.kind, 'expense');
      }
    });
  }

  test('amount mark without a number is refused', () {
    const text = 'Purchase at KUDU amount SAR 20';
    expect(() => SmsTemplate.build(text: text, amount: _mark(text, 'KUDU'), kind: 'expense'),
        throwsA(isA<FormatException>()));
  });

  test('sender restriction', () {
    const text = 'Dr EGP 50.00 at CAFE';
    final t = SmsTemplate.build(text: text, amount: _mark(text, '50.00'), kind: 'expense', sender: 'CIB');
    expect(t.senderMatches('CIB-EG'), isTrue);
    expect(t.senderMatches('NBE'), isFalse);
  });
}
