import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/accounts.dart';
import 'package:household_ledger/funds.dart';
import 'package:household_ledger/periods.dart';

void main() {
  group('Yearly expenses', () {
    final nov = periodFor(DateTime(2026, 11, 5), 1);

    test('spread over the months before the due month', () {
      expect(periodsBefore(nov, DateTime(2027, 10, 18), 1), 11);
      expect(monthlySetAside(amount: 1638, savedBefore: 0, from: nov, due: DateTime(2027, 10, 18), startDay: 1), 149);
    });

    test('money already saved lowers the monthly amount', () {
      expect(monthlySetAside(amount: 1638, savedBefore: 300, from: nov, due: DateTime(2027, 10, 18), startDay: 1), 122);
    });

    test('due this month needs the rest now; fully saved needs nothing', () {
      expect(monthlySetAside(amount: 900, savedBefore: 400, from: nov, due: DateTime(2026, 11, 20), startDay: 1), 500);
      expect(monthlySetAside(amount: 900, savedBefore: 900, from: nov, due: DateTime(2027, 3, 1), startDay: 1), 0);
    });

    test('salary-to-salary months', () {
      final p = periodFor(DateTime(2026, 11, 1), 27); // 27 Oct – 26 Nov
      expect(periodsBefore(p, DateTime(2027, 1, 5), 27), 2); // Oct 27 and Nov 27 periods
    });

    test('next due date keeps the day, clamped to month end', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 10, 18), 12), DateTime(2027, 10, 18));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });
  });

  group('Accounts', () {
    final accounts = [
      Account(id: 1, name: 'Credit card', type: 'credit', digits: '1946'),
      Account(id: 2, name: 'Main account', digits: '5678, 4321'),
    ];

    test('matched by card digits, not by amounts, dates or times', () {
      expect(matchAccount('شراء عبر نقاط البيع\nبطاقة:1946 ;فيزا\nمبلغ:SAR 36', accounts), 1);
      expect(matchAccount('شراء إنترنت\nبـSR 5\nعبر:1946;فيزا\nلـEHSAN', accounts), 1);
      expect(matchAccount('Local Transfer\nFrom: 5678\nAmount: SAR 1,500.00', accounts), 2);
      expect(matchAccount('Apple Pay purchase card *4321 SAR 42', accounts), 2);
      expect(matchAccount('Purchase SAR 1946.00 at X', accounts), isNull);
      expect(matchAccount('Payment SAR 1,946.50 at X', accounts), isNull);
      expect(matchAccount('Purchase SAR 20 at 19:46', accounts), isNull);
    });

    test('card numbers are found in messages', () {
      expect(cardDigitsIn('بطاقة:1946 ;فيزا-سامسونج باي\nلدى:SAPAH ALF\nمبلغ:SAR 36'), ['1946']);
      expect(cardDigitsIn('Your credit card ending with #4521 was charged for EGP 250.00'), ['4521']);
      expect(cardDigitsIn('Salary 19,750 credited to account **9876 on 27/10/2026'), ['9876']);
      expect(cardDigitsIn('Purchase SAR 1946.00 at X'), isEmpty);
    });
  });
}
