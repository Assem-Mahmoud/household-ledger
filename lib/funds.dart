/// Yearly and other irregular expenses (car insurance, school fees, Iqama renewal…).
/// Each one is spread over the months before it is due and shows up in the monthly plan
/// as an amount to set aside, then as a bill to pay in the month it falls due.

import 'periods.dart';

class Fund {
  int id;
  String title;
  double amount;
  String dueDate; // yyyy-MM-dd
  double saved; // set aside so far for the coming due date
  int? categoryId;
  int repeatMonths; // 12 = every year, 6, 3; 0 = only once
  bool archived;

  Fund({
    required this.id,
    required this.title,
    required this.amount,
    required this.dueDate,
    this.saved = 0,
    this.categoryId,
    this.repeatMonths = 12,
    this.archived = false,
  });

  DateTime get due => parseIso(dueDate);

  factory Fund.fromMap(Map<String, Object?> m) => Fund(
        id: m['id'] as int,
        title: (m['title'] as String?) ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        dueDate: (m['due_date'] as String?) ?? isoDate(DateTime.now()),
        saved: (m['saved'] as num?)?.toDouble() ?? 0,
        categoryId: m['category_id'] as int?,
        repeatMonths: (m['repeat_months'] as int?) ?? 12,
        archived: ((m['archived'] as int?) ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'title': title,
        'amount': amount,
        'due_date': dueDate,
        'saved': saved,
        'category_id': categoryId,
        'repeat_months': repeatMonths,
        'archived': archived ? 1 : 0,
      };
}

/// Number of periods from [from] up to, but not including, the period that contains [due].
/// That is how many months are left to set money aside before the bill arrives.
int periodsBefore(Period from, DateTime due, int startDay) {
  final duePer = periodFor(due, startDay);
  var n = 0;
  var p = from;
  while (p.key.compareTo(duePer.key) < 0 && n < 600) {
    n++;
    p = p.next;
  }
  return n;
}

/// Monthly amount to set aside so that [amount] is ready when the due month starts.
/// [savedBefore] is what was put aside before [from]. Rounded up to a whole unit.
double monthlySetAside({
  required double amount,
  required double savedBefore,
  required Period from,
  required DateTime due,
  required int startDay,
}) {
  final left = amount - savedBefore;
  if (left <= 0.005) return 0;
  final n = periodsBefore(from, due, startDay);
  if (n <= 0) return left; // due this month (or overdue): the rest is needed now
  return (left / n).ceilToDouble();
}

DateTime addMonths(DateTime d, int months) {
  final m = d.month - 1 + months;
  final y = d.year + (m ~/ 12);
  final mm = m % 12 + 1;
  final last = DateTime(y, mm + 1, 0).day;
  return DateTime(y, mm, d.day > last ? last : d.day);
}
