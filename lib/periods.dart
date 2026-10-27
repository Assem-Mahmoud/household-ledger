/// Budget periods. With startDay = 1 a period is a calendar month;
/// with e.g. startDay = 27 it runs from the 27th to the 26th (salary to salary).

import 'i18n.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
// Gregorian month names as used in Saudi Arabia
const _monthsAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysAr = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

String two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseIso(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String monthShort(int m) => isAr ? _monthsAr[m - 1] : _months[m - 1];
String monthLong(int m) => isAr ? _monthsAr[m - 1] : _monthsLong[m - 1];
String weekdayShort(DateTime d) => isAr ? _weekdaysAr[d.weekday - 1] : _weekdays[d.weekday - 1];

String shortDate(DateTime d) => '${d.day} ${monthShort(d.month)}';

class Period {
  final DateTime start;
  final DateTime end; // inclusive
  final int startDay;

  Period(this.start, this.end, this.startDay);

  /// Stable key used for budget overrides: the start month.
  String get key => '${start.year}-${two(start.month)}';
  String get startIso => isoDate(start);
  String get endIso => isoDate(end);

  bool contains(String iso) => iso.compareTo(startIso) >= 0 && iso.compareTo(endIso) <= 0;

  int get days => end.difference(start).inDays + 1;

  bool get isCurrent => contains(isoDate(DateTime.now()));
  bool get isFuture => start.isAfter(DateTime.now());

  /// Days elapsed including today (only meaningful for the current period).
  int get elapsed {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today.isBefore(start)) return 0;
    if (today.isAfter(end)) return days;
    return today.difference(start).inDays + 1;
  }

  Period get prev => periodStarting(DateTime(start.year, start.month - 1, startDay), startDay);
  Period get next => periodStarting(DateTime(start.year, start.month + 1, startDay), startDay);

  String get label {
    if (startDay == 1) return '${monthLong(start.month)} ${start.year}';
    return '${shortDate(start)} – ${shortDate(end)}';
  }

  String get shortLabel => startDay == 1 ? monthShort(start.month) : '${start.day} ${monthShort(start.month)}';
}

Period periodStarting(DateTime start, int startDay) {
  final s = DateTime(start.year, start.month, startDay);
  final e = DateTime(s.year, s.month + 1, startDay - 1);
  return Period(s, e, startDay);
}

Period periodFor(DateTime d, int startDay) {
  final day = DateTime(d.year, d.month, d.day);
  final start = day.day >= startDay
      ? DateTime(day.year, day.month, startDay)
      : DateTime(day.year, day.month - 1, startDay);
  return periodStarting(start, startDay);
}
