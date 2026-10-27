String fmt(double v, {int decimals = 0}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  return '${neg ? '−' : ''}$buf$dec';
}

/// Shows decimals only when the value has them.
String fmtAuto(double v) => fmt(v, decimals: (v * 100).round() % 100 == 0 ? 0 : 2);

String compact(double v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  if (a >= 1000000) return '$sign${(a / 1000000).toStringAsFixed(1)}M';
  if (a >= 1000) return '$sign${(a / 1000).toStringAsFixed(a % 1000 == 0 ? 0 : 1)}k';
  return '$sign${a.toStringAsFixed(0)}';
}

double? parseAmount(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = s.trim();
  for (var i = 0; i < 10; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  t = t.replaceAll('٫', '.').replaceAll(',', '').replaceAll('٬', '');
  return double.tryParse(t);
}
