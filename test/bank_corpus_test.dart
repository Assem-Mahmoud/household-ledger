// Generated: SMS formats in the style of Saudi, Egyptian and Gulf banks. Keep in sync with the parser.
import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/sms_parser.dart';

const _cases = <(String, String, String, double?, String, String, String)>[
  ('Al Rajhi', 'POS (real)', 'شراء عبر نقاط البيع\nبطاقة:1946 ;فيزا-سامسونج باي\nلدى:SAPAH ALF\nمبلغ:SAR 36\nرصيد:SAR 20441.22\n25/10/26 17:31', 36.0, 'expense', 'SAPAH ALF', 'SAR'),
  ('Al Rajhi', 'Online (real)', 'شراء إنترنت\nبـSR 5\nعبر:1946;فيزا\nلـEHSAN\nرصيد:SR 20436.22\n26/10/26 6:27', 5.0, 'expense', 'EHSAN', 'SAR'),
  ('Al Rajhi', 'Outgoing transfer', 'حوالة محلية صادرة\nمن:5678\nمبلغ:SAR 2000\nإلى:AHMED ALI\nالرصيد:SAR 18000\n26/10/26 10:00', 2000.0, 'expense', 'AHMED ALI', 'SAR'),
  ('Al Rajhi', 'Salary', 'إيداع راتب\nمبلغ:SAR 19750\nإلى:**5678\nالرصيد:SAR 38000\n27/10/26', 19750.0, 'income', '', 'SAR'),
  ('Al Rajhi', 'ATM', 'سحب صراف آلي\nبطاقة:1946;مدى\nمبلغ:SAR 500\nالمكان:ALRAJHI ATM DAMMAM\n26/10/26', 500.0, 'expense', 'ALRAJHI ATM DAMMAM', 'SAR'),
  ('Al Rajhi', 'English POS', 'PoS Purchase\nCard: 1946;mada\nAt: LULU HYPER DAMMAM\nAmount: SAR 293.81\nBalance: SAR 4298.84\n23/10/26 20:01', 293.81, 'expense', 'LULU HYPER DAMMAM', 'SAR'),
  ('SNB', 'POS EN', 'Purchase\nAmount: SAR 120.00\nCard: mada *1234\nAt: JARIR BOOKSTORE\nDate: 2026-10-20 14:22', 120.0, 'expense', 'JARIR BOOKSTORE', 'SAR'),
  ('SNB', 'POS AR', 'شراء\nبطاقة: مدى *1234\nمبلغ: 120.00 SAR\nلدى: مكتبة جرير\nفي: 20/10/26 14:22', 120.0, 'expense', 'مكتبة جرير', 'SAR'),
  ('SNB', 'Local transfer', 'Local Transfer\nFrom: 5678\nAmount: SAR 1,500.00\nTo: SARA MOHAMMED\nBank: Al Rajhi', 1500.0, 'expense', 'SARA MOHAMMED', 'SAR'),
  ('SNB', 'SADAD bill', 'SADAD Payment\nBiller: Saudi Electricity\nAmount: SAR 340.00\nAccount: **5678', 340.0, 'expense', 'Saudi Electricity', 'SAR'),
  ('SNB', 'Incoming transfer', 'Incoming transfer\nAmount: SAR 3,000.00\nFrom: KHALID\nTo: **5678', 3000.0, 'income', 'KHALID', 'SAR'),
  ('Riyad', 'POS EN', 'PoS Purchase\nBy: mada card 1234\nAmount: 75.50 SAR\nAt: STARBUCKS\nOn: 2026-10-21 08:10', 75.5, 'expense', 'STARBUCKS', 'SAR'),
  ('Riyad', 'POS AR', 'شراء عبر نقاط البيع\nبطاقة مدى: 1234\nالمبلغ: 75.50 ريال\nمن: STARBUCKS\nفي: 21/10/2026', 75.5, 'expense', 'STARBUCKS', 'SAR'),
  ('Riyad', 'Merchant no label', 'Purchase 89.00 SAR\nmada *1234\nTAMIMI MARKETS\n21/10/26 19:44', 89.0, 'expense', 'TAMIMI MARKETS', 'SAR'),
  ('SAB', 'Inline card', 'Purchase transaction using Card no. ***1234 for SAR 230.00 at NAHDI PHARMACY on 22/10/2026 19:05. Available balance SAR 5,000.00', 230.0, 'expense', 'NAHDI PHARMACY', 'SAR'),
  ('SAB', 'Credit card online', 'Online purchase with credit card ending 1234 for SAR 610.00 at AMAZON.SA on 22/10/2026', 610.0, 'expense', 'AMAZON.SA', 'SAR'),
  ('ANB', 'Inline mada', 'Dear Customer, a POS purchase of SAR 59.00 was made with your mada card ending 1234 at PANDA RETAIL on 23-10-2026.', 59.0, 'expense', 'PANDA RETAIL', 'SAR'),
  ('ANB', 'Transfer out AR', 'تحويل إلى\nالمستفيد: سارة احمد\nالمبلغ: 800 ر.س\nمن حساب: **5678', 800.0, 'expense', 'سارة احمد', 'SAR'),
  ('Alinma', 'POS AR', 'عملية شراء\nبطاقة: ***1234 (مدى)\nالمبلغ: 44.25 ر.س\nالتاجر: HUNGERSTATION\nالتاريخ: 2026/10/23 21:10', 44.25, 'expense', 'HUNGERSTATION', 'SAR'),
  ('Alinma', 'Salary AR', 'إيداع راتب\nالمبلغ: 19,750.00 ر.س\nالحساب: **5678', 19750.0, 'income', '', 'SAR'),
  ('Albilad', 'POS EN', 'Debit Card Purchase SAR 18.00 Merchant: KUDU DAMMAM Card 1234 Date 24/10/26', 18.0, 'expense', 'KUDU DAMMAM', 'SAR'),
  ('Albilad', 'ATM AR', 'سحب نقدي\nالمبلغ: 1,000 ريال\nالبطاقة: 1234\n24/10/2026', 1000.0, 'expense', '', 'SAR'),
  ('BSF', 'Credit card', 'Your Credit Card ending 1234 was used for SAR 310.00 at AMAZON.SA on 24/10/2026 11:00. Available limit: SAR 9,690.00', 310.0, 'expense', 'AMAZON.SA', 'SAR'),
  ('BSF', 'Foreign currency', 'Credit card purchase USD 15.99 (SAR 60.12) at NETFLIX.COM on 24/10/2026', 60.12, 'expense', 'NETFLIX.COM', 'SAR'),
  ('AlJazira', 'Online AR', 'شراء انترنت\nالمبلغ:SAR 99\nالبطاقة:1234\nالتاجر:NOON\nالرصيد:SAR 3,201', 99.0, 'expense', 'NOON', 'SAR'),
  ('SAIB', 'Inline AR', 'تم خصم مبلغ 150.00 ريال من حسابك لدى JAHEZ بتاريخ 25/10/2026', 150.0, 'expense', 'JAHEZ', 'SAR'),
  ('STC Bank', 'Paid to', 'You paid SAR 25.00 to Careem using your card *1234.', 25.0, 'expense', 'Careem', 'SAR'),
  ('STC Bank', 'Received', 'Transfer received SAR 500.00 from MOHAMMED ALI', 500.0, 'income', 'MOHAMMED ALI', 'SAR'),
  ('D360', 'Approved', 'Purchase of SAR 15.00 at Al Baik approved. Card ending 1234.', 15.0, 'expense', 'Al Baik', 'SAR'),
  ('Any', 'Refund', 'Refund\nAmount: SAR 120.00\nFrom: NOON\nCard: *1234', 120.0, 'income', 'NOON', 'SAR'),
  ('Any', 'Card bill payment', 'Payment of SAR 6,207.00 received for your credit card ending 1234. Thank you.', null, 'skip', '', 'SAR'),
  ('Any', 'Apple Pay EN', 'Apple Pay purchase\nCard: *1234\nAmount: SAR 42.00\nAt: Dunkin\n25/10/26', 42.0, 'expense', 'Dunkin', 'SAR'),
  ('Any', 'Foreign only', 'Purchase\nAmount: USD 45.00\nAt: APPLE.COM/BILL', 45.0, 'expense', 'APPLE.COM/BILL', 'SAR'),
  ('Noise', 'OTP', 'Your OTP for purchase of SAR 50.00 at NOON is 123456. Do not share it.', null, 'skip', '', 'SAR'),
  ('Noise', 'Declined', 'Transaction declined: purchase SAR 300 at IKEA. Insufficient funds.', null, 'skip', '', 'SAR'),
  ('Noise', 'Promo cashback', 'Get 20% cashback up to SAR 100 on all purchases with your mada card this weekend!', null, 'skip', '', 'SAR'),
  ('Noise', 'Balance only', 'Your account balance is SAR 4,000.00 as of 25/10/2026', null, 'skip', '', 'SAR'),
  ('Noise', 'Installment notice', 'Your installment of SAR 1,200 will be deducted on 01/11/2026', null, 'skip', '', 'SAR'),
  ('Noise', 'Statement due', 'Your credit card statement is ready. Due amount SAR 6,207. Due date 05/11/2026', null, 'skip', '', 'SAR'),
  ('Noise', 'Pre-auth hold', 'A temporary hold of SAR 500.00 was placed on your card at HILTON for a reservation.', null, 'skip', '', 'SAR'),
  ('SNB', 'Apple Pay AR', 'شراء أبل باي\nبطاقة: فيزا *4321\nالمبلغ: 63.00 ر.س\nلدى: CAFE BATEEL\n2026-10-26 16:02', 63.0, 'expense', 'CAFE BATEEL', 'SAR'),
  ('Riyad', 'Transfer out EN', 'Outgoing transfer of SAR 4,000.00 to ABDULLAH SALEH from account **9876 on 26/10/2026', 4000.0, 'expense', 'ABDULLAH SALEH', 'SAR'),
  ('SAB', 'Salary EN', 'Salary deposit of SAR 21,300.00 has been credited to your account **9876. Available balance SAR 30,112.40', 21300.0, 'income', '', 'SAR'),
  ('ANB', 'ATM EN', 'Cash withdrawal SAR 300.00 from ATM DHAHRAN MALL using card 1234 on 26/10/26', 300.0, 'expense', 'ATM DHAHRAN MALL', 'SAR'),
  ('Alinma', 'Online EN', 'Online Purchase\nAmount: SAR 199.00\nCard: *1234\nMerchant: NAMSHI\nDate: 26/10/2026', 199.0, 'expense', 'NAMSHI', 'SAR'),
  ('Albilad', 'Incoming AR', 'حوالة واردة بمبلغ 2,500 ريال من فهد العتيبي إلى حسابك **9876', 2500.0, 'income', 'فهد العتيبي', 'SAR'),
  ('BSF', 'Mada AR', 'تمت عملية شراء بمبلغ 27.50 ريال لدى ALDREES بواسطة بطاقة مدى 1234', 27.5, 'expense', 'ALDREES', 'SAR'),
  ('AlJazira', 'SADAD AR', 'سداد فاتورة\nالمفوتر: STC\nالمبلغ: 230 ريال\n26/10/2026', 230.0, 'expense', 'STC', 'SAR'),
  ('STC Bank', 'Purchase AR', 'تم الدفع 18 ر.س لـ Hungerstation باستخدام بطاقتك', 18.0, 'expense', 'Hungerstation', 'SAR'),
  ('urpay', 'Wallet transfer', 'You sent SAR 150.00 to NOURA via urpay.', 150.0, 'expense', 'NOURA', 'SAR'),
  ('Any', 'Refund AR', 'استرداد مبلغ 89.00 ريال من NOON إلى بطاقتك 1234', 89.0, 'income', 'NOON', 'SAR'),
  ('Any', 'Fee', 'Annual card fee SAR 115.00 has been charged to your account.', 115.0, 'expense', '', 'SAR'),
  ('Noise', 'Login alert', 'You logged in to Al Rajhi Mobile on 26/10/2026 at 08:00', null, 'skip', '', 'SAR'),
  ('Noise', 'Promo AR', 'استمتع بخصم يصل إلى 30% بقيمة 200 ريال عند الشراء ببطاقتك', null, 'skip', '', 'SAR'),
  ('Noise', 'Limit change', 'Your daily purchase limit has been updated to SAR 20,000', null, 'skip', '', 'SAR'),
  ('SNB', 'POS inline AR', 'شراء نقاط بيع بقيمة 54.75 ر.س من OTHAIM MARKETS بطاقة مدى *1234 في 27/10/2026 13:40', 54.75, 'expense', 'OTHAIM MARKETS', 'SAR'),
  ('Riyad', 'Credit card EN', 'Credit Card *4321 Purchase\nSAR 1,249.00\nEXTRA STORES DAMMAM\n27/10/2026 18:02', 1249.0, 'expense', 'EXTRA STORES DAMMAM', 'SAR'),
  ('SAB', 'Transfer AR', 'تحويل صادر\nالمبلغ: 1,000.00 ريال\nإلى: محمد سالم\nمن الحساب: **9876\nالتاريخ: 27/10/2026', 1000.0, 'expense', 'محمد سالم', 'SAR'),
  ('ANB', 'Bill EN', 'Bill payment of SAR 275.00 to MOBILY completed successfully on 27/10/2026.', 275.0, 'expense', 'MOBILY', 'SAR'),
  ('Alinma', 'ATM AR', 'سحب من الصراف الآلي\nالمبلغ: 200 ر.س\nالموقع: ALINMA ATM KHOBAR\nالرصيد: 7,800 ر.س', 200.0, 'expense', 'ALINMA ATM KHOBAR', 'SAR'),
  ('Albilad', 'Salary AR', 'تم إيداع الراتب بمبلغ 19,750 ريال في حسابك **9876', 19750.0, 'income', '', 'SAR'),
  ('BSF', 'Online EN', 'Online transaction SAR 79.00 at SPOTIFY approved on card ending 4321', 79.0, 'expense', 'SPOTIFY', 'SAR'),
  ('AlJazira', 'Refund EN', 'Reversal of SAR 45.00 from HUNGERSTATION credited to your card 1234', 45.0, 'income', 'HUNGERSTATION', 'SAR'),
  ('STC Bank', 'Apple Pay', 'Apple Pay: SAR 12.00 at BARNS COFFEE. Card *1234', 12.0, 'expense', 'BARNS COFFEE', 'SAR'),
  ('D360', 'Transfer in', 'You received SAR 750.00 from OMAR KHALED', 750.0, 'income', 'OMAR KHALED', 'SAR'),
  ('Al Rajhi', 'Mada AR spaced', 'شراء عبر نقاط البيع\nبطاقة: 1946 ; مدى\nلدى: NAHDI MEDICAL CO\nمبلغ: SAR 64.50\nرصيد: SAR 12,004.11', 64.5, 'expense', 'NAHDI MEDICAL CO', 'SAR'),
  ('Any', 'Gov fee', 'SADAD: SAR 100.00 paid to ABSHER / Traffic fines. Ref 556677', 100.0, 'expense', 'ABSHER / Traffic fines', 'SAR'),
  ('Noise', 'Card activated', 'Your new mada card ending 1234 has been activated. Enjoy purchases up to SAR 10,000 daily.', null, 'skip', '', 'SAR'),
  ('Noise', 'Points', 'You earned 120 points on your purchase of SAR 600 at JARIR. Total points 4,500', null, 'skip', '', 'SAR'),
  ('Noise', 'Upcoming payment', 'Reminder: your credit card payment of SAR 3,200 is due on 05/11/2026', null, 'skip', '', 'SAR'),
  ('CIB (EG)', 'Credit card EN', 'Your credit card ending with #1234 was charged for EGP 250.00 at CARREFOUR MAADI on 28/10/26 13:05. Available limit EGP 30,000.00', 250.0, 'expense', 'CARREFOUR MAADI', 'EGP'),
  ('NBE (EG)', 'Debit AR', 'تم خصم مبلغ 500.00 جنيه من حسابك رقم ***1234 لدى VODAFONE بتاريخ 28/10/2026. الرصيد المتاح 12,500.00 جنيه', 500.0, 'expense', 'VODAFONE', 'EGP'),
  ('Banque Misr (EG)', 'Purchase AR', 'عزيزي العميل تم إجراء عملية شراء بمبلغ 1,250.50 ج.م باستخدام بطاقتك 1234 لدى B.TECH يوم 28/10', 1250.5, 'expense', 'B.TECH', 'EGP'),
  ('InstaPay (EG)', 'Transfer out', 'تم تحويل 1000 جنيه إلى احمد محمد عبر InstaPay. رقم العملية 123456', 1000.0, 'expense', 'احمد محمد', 'EGP'),
  ('QNB (EG)', 'Salary AR', 'تم إضافة 18,500.00 جم إلى حسابك رقم ***1234 - مرتب شهر أكتوبر', 18500.0, 'income', '', 'EGP'),
  ('Fawry (EG)', 'Bill EN', 'Fawry: Payment of EGP 340.00 to WE Internet completed. Ref 99887766', 340.0, 'expense', 'WE Internet', 'EGP'),
  ('CIB (EG)', 'ATM AR', 'تم سحب 2,000.00 جنيه من ماكينة ATM CIB NASR CITY باستخدام بطاقتك 1234', 2000.0, 'expense', 'ماكينة ATM CIB NASR CITY', 'EGP'),
  ('Any (EG)', 'Refund EN', 'A refund of EGP 199.00 from NOON has been credited to your card ending 1234', 199.0, 'income', 'NOON', 'EGP'),
  ('Any (EG)', 'Foreign USD', 'Your card ending 1234 was charged USD 9.99 at NETFLIX.COM', 9.99, 'expense', 'NETFLIX.COM', 'EGP'),
  ('Noise (EG)', 'OTP code', 'كود التحقق الخاص بك 123456 لعملية شراء بمبلغ 500 جنيه', null, 'skip', '', 'EGP'),
  ('ENBD (AE)', 'Credit card', 'Purchase of AED 120.50 with Credit Card ending 1234 at NOON.COM, DUBAI. Avl Cr. Limit is AED 9,000.00', 120.5, 'expense', 'NOON.COM', 'AED'),
  ('ADCB (AE)', 'No space', 'Your Cr.Card XXX1234 was used for AED45.00 on 28/10/2026 at CARREFOUR CITY CENTRE. Available limit AED 12,000', 45.0, 'expense', 'CARREFOUR CITY CENTRE', 'AED'),
  ('FAB (AE)', 'Debit AR', 'تم خصم 75.00 درهم من بطاقتك 1234 لدى TALABAT في 28/10/2026', 75.0, 'expense', 'TALABAT', 'AED'),
  ('Any (AE)', 'Salary', 'Salary of AED 25,000.00 has been credited to your account XXX5678', 25000.0, 'income', '', 'AED'),
  ('NBK (KW)', 'Spent 3 decimals', 'KD 12.500 spent on your card ending 1234 at THE SULTAN CENTER', 12.5, 'expense', 'THE SULTAN CENTER', 'KWD'),
  ('KFH (KW)', 'Purchase AR', 'تم شراء بمبلغ 3.750 د.ك لدى TALABAT KUWAIT', 3.75, 'expense', 'TALABAT KUWAIT', 'KWD'),
  ('BBK (BH)', 'Debited', 'BHD 5.250 debited from your account for purchase at LULU HYPERMARKET', 5.25, 'expense', 'LULU HYPERMARKET', 'BHD'),
  ('QNB (QA)', 'Purchase', 'QNB: Purchase of QAR 150.00 at CARREFOUR VILLAGGIO approved.', 150.0, 'expense', 'CARREFOUR VILLAGGIO', 'QAR'),
  ('Bank Muscat (OM)', 'Card used', 'Your card 1234 used for OMR 8.400 at LULU MUSCAT', 8.4, 'expense', 'LULU MUSCAT', 'OMR'),
  ('Arab Bank (JO)', 'Purchase AR', 'تم شراء بقيمة 20.000 دينار من CARREFOUR AMMAN بواسطة بطاقة 1234', 20.0, 'expense', 'CARREFOUR AMMAN', 'JOD'),
  ('HSBC (EG)', 'Debit card EN', 'Debit card 1234 purchase EGP 85.50 at TALABAT EGYPT 28OCT26', 85.5, 'expense', 'TALABAT EGYPT', 'EGP'),
  ('Alex Bank (EG)', 'Transfer in AR', 'تم استلام حوالة بمبلغ 3,000 جنيه مصري من محمود علي', 3000.0, 'income', 'محمود علي', 'EGP'),
  ('Vodafone Cash (EG)', 'Wallet', 'تم دفع 120 جنيه لـ Uber من محفظة فودافون كاش. رصيدك الحالي 880 جنيه', 120.0, 'expense', 'Uber', 'EGP'),
  ('Mashreq (AE)', 'Debit card', 'AED 32.75 spent at STARBUCKS MALL OF THE EMIRATES using Debit Card ending 1234', 32.75, 'expense', 'STARBUCKS MALL OF THE EMIRATES', 'AED'),
  ('DIB (AE)', 'Transfer out', 'AED 1,500.00 transferred to SARA AHMED from your account 5678', 1500.0, 'expense', 'SARA AHMED', 'AED'),
  ('Gulf Bank (KW)', 'Withdrawal', 'Cash withdrawal of KWD 50.000 from ATM AVENUES MALL', 50.0, 'expense', 'ATM AVENUES MALL', 'KWD'),
  ('Housing Bank (JO)', 'Salary AR', 'تم إيداع راتب بقيمة 650.000 دينار في حسابك', 650.0, 'income', '', 'JOD'),
  ('Noise (AE)', 'Promo', 'Enjoy 10% cashback up to AED 200 on dining this weekend!', null, 'skip', '', 'AED'),
];

void main() {
  for (final (bank, name, body, amount, kind, merchant, currency) in _cases) {
    test('$bank · $name', () {
      final p = parseSms(body, currency: currency);
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

  test('foreign currency flagged only when no home-currency amount', () {
    expect(foreignCurrency('Purchase\nAmount: USD 45.00\nAt: APPLE.COM/BILL'), 'USD');
    expect(foreignCurrency('Credit card purchase USD 15.99 (SAR 60.12) at NETFLIX.COM'), isNull);
    expect(foreignCurrency('Purchase SAR 20 at KUDU'), isNull);
    expect(foreignCurrency('Your card ending 1234 was charged USD 9.99 at NETFLIX.COM', currency: 'EGP'), 'USD');
    expect(foreignCurrency('تم خصم 75.00 درهم من بطاقتك', currency: 'SAR'), 'AED');
    expect(foreignCurrency('تم خصم 75.00 درهم من بطاقتك', currency: 'AED'), isNull);
  });
}
