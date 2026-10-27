import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'i18n_ar.dart';

/// Very small translation layer: English text is the key, Arabic comes from [arabic].
/// Placeholders use {name}. Missing translations fall back to English.

String _lang = 'en';

/// The language in use: 'en' or 'ar'.
String get lang => _lang;
bool get isAr => _lang == 'ar';

/// [pref] is the user's setting: 'system', 'en' or 'ar'.
void setLanguage(String pref) {
  if (pref == 'en' || pref == 'ar') {
    _lang = pref;
  } else {
    _lang = PlatformDispatcher.instance.locale.languageCode == 'ar' ? 'ar' : 'en';
  }
}

String tr(String key, [Map<String, Object?> args = const {}]) {
  var s = isAr ? (arabic[key] ?? key) : key;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Count-dependent text. English picks [one] or [many]; Arabic uses the [many] key,
/// whose translation is written to read correctly for any number.
String trn(num n, String one, String many, [Map<String, Object?> args = const {}]) {
  final a = {'n': n, ...args};
  if (isAr) return tr(many, a);
  return tr(n == 1 ? one : many, a);
}

/// Keeps a signed amount like "−1,084" in left-to-right order inside Arabic text.
String ltr(String s) => isAr ? '\u202A$s\u202C' : s;

/// A translated Text that can stay `const`.
class T extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const T(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) =>
      Text(tr(text), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
}
