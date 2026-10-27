import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:household_ledger/format.dart';
import 'package:household_ledger/i18n.dart';
import 'package:household_ledger/i18n_ar.dart';
import 'package:household_ledger/periods.dart';

void main() {
  test('every literal passed to tr() or T() has an Arabic translation', () {
    final call = RegExp(r"""(?<![A-Za-z0-9_.])(?:tr|T)\(\s*'((?:[^'\\]|\\.)*)'\s*[,)]""");
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('i18n_ar.dart')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!.replaceAll(r"\'", "'").replaceAll(r'\n', '\n');
        if (key.contains(r'$')) continue;
        if (!arabic.containsKey(key)) missing.add('${f.path}: $key');
      }
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('placeholders match between English and Arabic', () {
    final ph = RegExp(r'\{(\w+)\}');
    for (final e in arabic.entries) {
      final a = ph.allMatches(e.key).map((m) => m.group(1)).toSet();
      final b = ph.allMatches(e.value).map((m) => m.group(1)).toSet();
      expect(b, a, reason: e.key);
    }
  });

  test('Arabic texts, months and signed amounts', () {
    setLanguage('ar');
    expect(tr('Income'), 'الدخل');
    expect(tr('{a} {cur} left', {'a': '100', 'cur': 'ر.س'}), 'المتبقي 100 ر.س');
    expect(trn(3, '{n} entry', '{n} entries'), 'القيود: 3');
    expect(periodFor(DateTime(2026, 10, 5), 1).label, 'أكتوبر 2026');
    expect(fmt(-1084), '\u202A−1,084\u202C');
    setLanguage('en');
    expect(tr('Income'), 'Income');
    expect(trn(1, '{n} entry', '{n} entries'), '1 entry');
    expect(periodFor(DateTime(2026, 10, 5), 1).label, 'October 2026');
    expect(fmt(-1084), '−1,084');
  });
}
