import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/periods.dart';
import 'package:household_ledger/sms_parser.dart';

void main() {
  group('SMS parser', () {
    test('Arabic mada purchase', () {
      final p = parseSms('شراء عبر نقاط البيع\nبطاقة: 1946;مدى\nمبلغ: SAR 45.00\nلدى: LULU HYPER DAMMAM\nفي: 26-10-23 18:30');
      expect(p, isNotNull);
      expect(p!.amount, 45.0);
      expect(p.kind, 'expense');
      expect(p.merchant, 'LULU HYPER DAMMAM');
    });

    test('English purchase ignores balance', () {
      final p = parseSms('Purchase\nCard: *1946\nAmount: SAR 293.81\nAt: LULU HYPER DAMMAM\nBalance: SAR 4,298.84');
      expect(p!.amount, 293.81);
      expect(p.merchant, 'LULU HYPER DAMMAM');
    });

    test('Inline purchase with available limit', () {
      final p = parseSms('POS Purchase SAR 36.00 at SAPAH ALFOL CAFE on 25/10/2026. Available limit SAR 12,500.00');
      expect(p!.amount, 36.0);
      expect(p.merchant, 'SAPAH ALFOL CAFE');
    });

    test('Amount after number, merchant after from', () {
      final p = parseSms('Online purchase of 437.44 SAR from SHEIN.COM using card *1946');
      expect(p!.amount, 437.44);
      expect(p.merchant, 'SHEIN.COM');
    });

    test('Balance first, amount later', () {
      final p = parseSms('رصيد حسابك 4,298 ريال. شراء بمبلغ 91.06 ريال لدى UNITED FUEL COMPANY');
      expect(p!.amount, 91.06);
      expect(p.merchant, 'UNITED FUEL COMPANY');
    });

    test('Salary is income', () {
      final p = parseSms('Your account was credited with SAR 18,000.00 Salary. Balance: SAR 22,000');
      expect(p!.amount, 18000);
      expect(p.kind, 'income');
    });

    test('Incoming transfer in Arabic is income', () {
      final p = parseSms('حوالة واردة\nمبلغ: 10,000 ر.س\nمن: احمد\nالرصيد: 25,000 ر.س');
      expect(p!.amount, 10000);
      expect(p.kind, 'income');
    });

    test('Arabic-Indic digits', () {
      final p = parseSms('شراء بمبلغ ١٢٥٫٥٠ ريال لدى PANDA');
      expect(p!.amount, 125.5);
    });

    test('OTP is ignored', () {
      expect(parseSms('Your OTP for purchase of SAR 50 is 123456'), isNull);
    });

    test('Credit card purchase is not income', () {
      final p = parseSms('Credit Card purchase SAR 80.00 at ALROMANSIA');
      expect(p!.kind, 'expense');
    });

    test('Al Rajhi POS purchase (screenshot)', () {
      final p = parseSms('شراء عبر نقاط البيع\nبطاقة:1946 ;فيزا-سامسونج باي\nلدى:SAPAH ALF\nمبلغ:SAR 36\nرصيد:SAR 20441.22\n25/10/26 17:31');
      expect(p!.amount, 36);
      expect(p.kind, 'expense');
      expect(p.merchant, 'SAPAH ALF');
    });

    test('Al Rajhi online purchase with tatweel and direction marks', () {
      for (final body in [
        'شراء إنترنت\nبـSR 5\nعبر:1946;فيزا\nلـEHSAN\nرصيد:SR 20436.22\n26/10/26 6:27',
        'شراء إنترنت بـSR 5\nعبر1946;فيزا\nلـEHSAN\nرصيد:SR 20431.22\n6:28 26/10/26',
        '\u200fشراء إنترنت\n\u200fبـ\u200eSR 5\n\u200fلـ\u200eEHSAN\n\u200fرصيد:SR 20436.22',
      ]) {
        final p = parseSms(body);
        expect(p, isNotNull, reason: body);
        expect(p!.amount, 5, reason: body);
        expect(p.kind, 'expense');
        expect(p.merchant, 'EHSAN', reason: body);
        expect(looksLikeTransaction(body), isTrue);
      }
    });

    test('merchantKey', () {
      expect(merchantKey('LULU HYPER DAMMAM 123'), 'lulu hyper');
      expect(merchantKey('***'), '');
    });
  });

  group('Periods', () {
    test('calendar month', () {
      final p = periodFor(DateTime(2026, 10, 27), 1);
      expect(p.startIso, '2026-10-01');
      expect(p.endIso, '2026-10-31');
      expect(p.key, '2026-10');
    });

    test('salary cycle from the 27th', () {
      final p = periodFor(DateTime(2026, 10, 27), 27);
      expect(p.startIso, '2026-10-27');
      expect(p.endIso, '2026-11-26');
      final q = periodFor(DateTime(2026, 10, 20), 27);
      expect(q.startIso, '2026-09-27');
      expect(q.endIso, '2026-10-26');
      expect(q.next.startIso, '2026-10-27');
    });

    test('year boundary', () {
      final p = periodFor(DateTime(2027, 1, 5), 27);
      expect(p.startIso, '2026-12-27');
      expect(p.prev.startIso, '2026-11-27');
    });
  });
}
