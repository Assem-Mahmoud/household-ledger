// Generated: SMS formats in the style of each Saudi bank. Keep in sync with the parser.
import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/sms_parser.dart';

const _cases = <(String, String, String, double?, String, String)>[
  ('Al Rajhi', 'POS (real)', 'شراء عبر نقاط البيع\nبطاقة:1946 ;فيزا-سامسونج باي\nلدى:SAPAH ALF\nمبلغ:SAR 36\nرصيد:SAR 20441.22\n25/10/26 17:31', 36.0, 'expense', 'SAPAH ALF'),
  ('Al Rajhi', 'Online (real)', 'شراء إنترنت\nبـSR 5\nعبر:1946;فيزا\nلـEHSAN\nرصيد:SR 20436.22\n26/10/26 6:27', 5.0, 'expense', 'EHSAN'),
  ('Al Rajhi', 'Outgoing transfer', 'حوالة محلية صادرة\nمن:5678\nمبلغ:SAR 2000\nإلى:AHMED ALI\nالرصيد:SAR 18000\n26/10/26 10:00', 2000.0, 'expense', 'AHMED ALI'),
  ('Al Rajhi', 'Salary', 'إيداع راتب\nمبلغ:SAR 19750\nإلى:**5678\nالرصيد:SAR 38000\n27/10/26', 19750.0, 'income', ''),
  ('Al Rajhi', 'ATM', 'سحب صراف آلي\nبطاقة:1946;مدى\nمبلغ:SAR 500\nالمكان:ALRAJHI ATM DAMMAM\n26/10/26', 500.0, 'expense', 'ALRAJHI ATM DAMMAM'),
  ('Al Rajhi', 'English POS', 'PoS Purchase\nCard: 1946;mada\nAt: LULU HYPER DAMMAM\nAmount: SAR 293.81\nBalance: SAR 4298.84\n23/10/26 20:01', 293.81, 'expense', 'LULU HYPER DAMMAM'),
  ('SNB', 'POS EN', 'Purchase\nAmount: SAR 120.00\nCard: mada *1234\nAt: JARIR BOOKSTORE\nDate: 2026-10-20 14:22', 120.0, 'expense', 'JARIR BOOKSTORE'),
  ('SNB', 'POS AR', 'شراء\nبطاقة: مدى *1234\nمبلغ: 120.00 SAR\nلدى: مكتبة جرير\nفي: 20/10/26 14:22', 120.0, 'expense', 'مكتبة جرير'),
  ('SNB', 'Local transfer', 'Local Transfer\nFrom: 5678\nAmount: SAR 1,500.00\nTo: SARA MOHAMMED\nBank: Al Rajhi', 1500.0, 'expense', 'SARA MOHAMMED'),
  ('SNB', 'SADAD bill', 'SADAD Payment\nBiller: Saudi Electricity\nAmount: SAR 340.00\nAccount: **5678', 340.0, 'expense', 'Saudi Electricity'),
  ('SNB', 'Incoming transfer', 'Incoming transfer\nAmount: SAR 3,000.00\nFrom: KHALID\nTo: **5678', 3000.0, 'income', 'KHALID'),
  ('Riyad', 'POS EN', 'PoS Purchase\nBy: mada card 1234\nAmount: 75.50 SAR\nAt: STARBUCKS\nOn: 2026-10-21 08:10', 75.5, 'expense', 'STARBUCKS'),
  ('Riyad', 'POS AR', 'شراء عبر نقاط البيع\nبطاقة مدى: 1234\nالمبلغ: 75.50 ريال\nمن: STARBUCKS\nفي: 21/10/2026', 75.5, 'expense', 'STARBUCKS'),
  ('Riyad', 'Merchant no label', 'Purchase 89.00 SAR\nmada *1234\nTAMIMI MARKETS\n21/10/26 19:44', 89.0, 'expense', 'TAMIMI MARKETS'),
  ('SAB', 'Inline card', 'Purchase transaction using Card no. ***1234 for SAR 230.00 at NAHDI PHARMACY on 22/10/2026 19:05. Available balance SAR 5,000.00', 230.0, 'expense', 'NAHDI PHARMACY'),
  ('SAB', 'Credit card online', 'Online purchase with credit card ending 1234 for SAR 610.00 at AMAZON.SA on 22/10/2026', 610.0, 'expense', 'AMAZON.SA'),
  ('ANB', 'Inline mada', 'Dear Customer, a POS purchase of SAR 59.00 was made with your mada card ending 1234 at PANDA RETAIL on 23-10-2026.', 59.0, 'expense', 'PANDA RETAIL'),
  ('ANB', 'Transfer out AR', 'تحويل إلى\nالمستفيد: سارة احمد\nالمبلغ: 800 ر.س\nمن حساب: **5678', 800.0, 'expense', 'سارة احمد'),
  ('Alinma', 'POS AR', 'عملية شراء\nبطاقة: ***1234 (مدى)\nالمبلغ: 44.25 ر.س\nالتاجر: HUNGERSTATION\nالتاريخ: 2026/10/23 21:10', 44.25, 'expense', 'HUNGERSTATION'),
  ('Alinma', 'Salary AR', 'إيداع راتب\nالمبلغ: 19,750.00 ر.س\nالحساب: **5678', 19750.0, 'income', ''),
  ('Albilad', 'POS EN', 'Debit Card Purchase SAR 18.00 Merchant: KUDU DAMMAM Card 1234 Date 24/10/26', 18.0, 'expense', 'KUDU DAMMAM'),
  ('Albilad', 'ATM AR', 'سحب نقدي\nالمبلغ: 1,000 ريال\nالبطاقة: 1234\n24/10/2026', 1000.0, 'expense', ''),
  ('BSF', 'Credit card', 'Your Credit Card ending 1234 was used for SAR 310.00 at AMAZON.SA on 24/10/2026 11:00. Available limit: SAR 9,690.00', 310.0, 'expense', 'AMAZON.SA'),
  ('BSF', 'Foreign currency', 'Credit card purchase USD 15.99 (SAR 60.12) at NETFLIX.COM on 24/10/2026', 60.12, 'expense', 'NETFLIX.COM'),
  ('AlJazira', 'Online AR', 'شراء انترنت\nالمبلغ:SAR 99\nالبطاقة:1234\nالتاجر:NOON\nالرصيد:SAR 3,201', 99.0, 'expense', 'NOON'),
  ('SAIB', 'Inline AR', 'تم خصم مبلغ 150.00 ريال من حسابك لدى JAHEZ بتاريخ 25/10/2026', 150.0, 'expense', 'JAHEZ'),
  ('STC Bank', 'Paid to', 'You paid SAR 25.00 to Careem using your card *1234.', 25.0, 'expense', 'Careem'),
  ('STC Bank', 'Received', 'Transfer received SAR 500.00 from MOHAMMED ALI', 500.0, 'income', 'MOHAMMED ALI'),
  ('D360', 'Approved', 'Purchase of SAR 15.00 at Al Baik approved. Card ending 1234.', 15.0, 'expense', 'Al Baik'),
  ('Any', 'Refund', 'Refund\nAmount: SAR 120.00\nFrom: NOON\nCard: *1234', 120.0, 'income', 'NOON'),
  ('Any', 'Card bill payment', 'Payment of SAR 6,207.00 received for your credit card ending 1234. Thank you.', null, 'skip', ''),
  ('Any', 'Apple Pay EN', 'Apple Pay purchase\nCard: *1234\nAmount: SAR 42.00\nAt: Dunkin\n25/10/26', 42.0, 'expense', 'Dunkin'),
  ('Any', 'Foreign only', 'Purchase\nAmount: USD 45.00\nAt: APPLE.COM/BILL', 45.0, 'expense', 'APPLE.COM/BILL'),
  ('Noise', 'OTP', 'Your OTP for purchase of SAR 50.00 at NOON is 123456. Do not share it.', null, 'skip', ''),
  ('Noise', 'Declined', 'Transaction declined: purchase SAR 300 at IKEA. Insufficient funds.', null, 'skip', ''),
  ('Noise', 'Promo cashback', 'Get 20% cashback up to SAR 100 on all purchases with your mada card this weekend!', null, 'skip', ''),
  ('Noise', 'Balance only', 'Your account balance is SAR 4,000.00 as of 25/10/2026', null, 'skip', ''),
  ('Noise', 'Installment notice', 'Your installment of SAR 1,200 will be deducted on 01/11/2026', null, 'skip', ''),
  ('Noise', 'Statement due', 'Your credit card statement is ready. Due amount SAR 6,207. Due date 05/11/2026', null, 'skip', ''),
  ('Noise', 'Pre-auth hold', 'A temporary hold of SAR 500.00 was placed on your card at HILTON for a reservation.', null, 'skip', ''),
  ('SNB', 'Apple Pay AR', 'شراء أبل باي\nبطاقة: فيزا *4321\nالمبلغ: 63.00 ر.س\nلدى: CAFE BATEEL\n2026-10-26 16:02', 63.0, 'expense', 'CAFE BATEEL'),
  ('Riyad', 'Transfer out EN', 'Outgoing transfer of SAR 4,000.00 to ABDULLAH SALEH from account **9876 on 26/10/2026', 4000.0, 'expense', 'ABDULLAH SALEH'),
  ('SAB', 'Salary EN', 'Salary deposit of SAR 21,300.00 has been credited to your account **9876. Available balance SAR 30,112.40', 21300.0, 'income', ''),
  ('ANB', 'ATM EN', 'Cash withdrawal SAR 300.00 from ATM DHAHRAN MALL using card 1234 on 26/10/26', 300.0, 'expense', 'ATM DHAHRAN MALL'),
  ('Alinma', 'Online EN', 'Online Purchase\nAmount: SAR 199.00\nCard: *1234\nMerchant: NAMSHI\nDate: 26/10/2026', 199.0, 'expense', 'NAMSHI'),
  ('Albilad', 'Incoming AR', 'حوالة واردة بمبلغ 2,500 ريال من فهد العتيبي إلى حسابك **9876', 2500.0, 'income', 'فهد العتيبي'),
  ('BSF', 'Mada AR', 'تمت عملية شراء بمبلغ 27.50 ريال لدى ALDREES بواسطة بطاقة مدى 1234', 27.5, 'expense', 'ALDREES'),
  ('AlJazira', 'SADAD AR', 'سداد فاتورة\nالمفوتر: STC\nالمبلغ: 230 ريال\n26/10/2026', 230.0, 'expense', 'STC'),
  ('STC Bank', 'Purchase AR', 'تم الدفع 18 ر.س لـ Hungerstation باستخدام بطاقتك', 18.0, 'expense', 'Hungerstation'),
  ('urpay', 'Wallet transfer', 'You sent SAR 150.00 to NOURA via urpay.', 150.0, 'expense', 'NOURA'),
  ('Any', 'Refund AR', 'استرداد مبلغ 89.00 ريال من NOON إلى بطاقتك 1234', 89.0, 'income', 'NOON'),
  ('Any', 'Fee', 'Annual card fee SAR 115.00 has been charged to your account.', 115.0, 'expense', ''),
  ('Noise', 'Login alert', 'You logged in to Al Rajhi Mobile on 26/10/2026 at 08:00', null, 'skip', ''),
  ('Noise', 'Promo AR', 'استمتع بخصم يصل إلى 30% بقيمة 200 ريال عند الشراء ببطاقتك', null, 'skip', ''),
  ('Noise', 'Limit change', 'Your daily purchase limit has been updated to SAR 20,000', null, 'skip', ''),
  ('SNB', 'POS inline AR', 'شراء نقاط بيع بقيمة 54.75 ر.س من OTHAIM MARKETS بطاقة مدى *1234 في 27/10/2026 13:40', 54.75, 'expense', 'OTHAIM MARKETS'),
  ('Riyad', 'Credit card EN', 'Credit Card *4321 Purchase\nSAR 1,249.00\nEXTRA STORES DAMMAM\n27/10/2026 18:02', 1249.0, 'expense', 'EXTRA STORES DAMMAM'),
  ('SAB', 'Transfer AR', 'تحويل صادر\nالمبلغ: 1,000.00 ريال\nإلى: محمد سالم\nمن الحساب: **9876\nالتاريخ: 27/10/2026', 1000.0, 'expense', 'محمد سالم'),
  ('ANB', 'Bill EN', 'Bill payment of SAR 275.00 to MOBILY completed successfully on 27/10/2026.', 275.0, 'expense', 'MOBILY'),
  ('Alinma', 'ATM AR', 'سحب من الصراف الآلي\nالمبلغ: 200 ر.س\nالموقع: ALINMA ATM KHOBAR\nالرصيد: 7,800 ر.س', 200.0, 'expense', 'ALINMA ATM KHOBAR'),
  ('Albilad', 'Salary AR', 'تم إيداع الراتب بمبلغ 19,750 ريال في حسابك **9876', 19750.0, 'income', ''),
  ('BSF', 'Online EN', 'Online transaction SAR 79.00 at SPOTIFY approved on card ending 4321', 79.0, 'expense', 'SPOTIFY'),
  ('AlJazira', 'Refund EN', 'Reversal of SAR 45.00 from HUNGERSTATION credited to your card 1234', 45.0, 'income', 'HUNGERSTATION'),
  ('STC Bank', 'Apple Pay', 'Apple Pay: SAR 12.00 at BARNS COFFEE. Card *1234', 12.0, 'expense', 'BARNS COFFEE'),
  ('D360', 'Transfer in', 'You received SAR 750.00 from OMAR KHALED', 750.0, 'income', 'OMAR KHALED'),
  ('Al Rajhi', 'Mada AR spaced', 'شراء عبر نقاط البيع\nبطاقة: 1946 ; مدى\nلدى: NAHDI MEDICAL CO\nمبلغ: SAR 64.50\nرصيد: SAR 12,004.11', 64.5, 'expense', 'NAHDI MEDICAL CO'),
  ('Any', 'Gov fee', 'SADAD: SAR 100.00 paid to ABSHER / Traffic fines. Ref 556677', 100.0, 'expense', 'ABSHER / Traffic fines'),
  ('Noise', 'Card activated', 'Your new mada card ending 1234 has been activated. Enjoy purchases up to SAR 10,000 daily.', null, 'skip', ''),
  ('Noise', 'Points', 'You earned 120 points on your purchase of SAR 600 at JARIR. Total points 4,500', null, 'skip', ''),
  ('Noise', 'Upcoming payment', 'Reminder: your credit card payment of SAR 3,200 is due on 05/11/2026', null, 'skip', ''),
];

void main() {
  for (final (bank, name, body, amount, kind, merchant) in _cases) {
    test('$bank · $name', () {
      final p = parseSms(body);
      if (kind == 'skip') {
        expect(p, isNull, reason: 'should be ignored: $p');
        return;
      }
      expect(p, isNotNull);
      expect(p!.amount, amount);
      expect(p.kind, kind);
      expect(p.merchant, merchant);
    });
  }

  test('foreign currency flagged only when no riyal amount', () {
    expect(foreignCurrency('Purchase\nAmount: USD 45.00\nAt: APPLE.COM/BILL'), 'USD');
    expect(foreignCurrency('Credit card purchase USD 15.99 (SAR 60.12) at NETFLIX.COM'), isNull);
    expect(foreignCurrency('Purchase SAR 20 at KUDU'), isNull);
  });
}
