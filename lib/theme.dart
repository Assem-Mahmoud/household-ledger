/// Colours, type and component styles for light and dark mode (palette option A: Emerald + Amber).

import 'package:flutter/material.dart' hide Category;

import 'models.dart';

class LedgerColors {
  final bool dark;
  final Color bg, card, raised, text, muted, divider, outline;
  final Color primary, onPrimary, primarySoft, onPrimarySoft;
  final Color secondary, onSecondary, attnBg, attnText;
  final Color hero, heroText, heroSub, heroTrack, heroChip;
  final Color good, warn, bad;

  const LedgerColors({
    required this.dark,
    required this.bg,
    required this.card,
    required this.raised,
    required this.text,
    required this.muted,
    required this.divider,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.primarySoft,
    required this.onPrimarySoft,
    required this.secondary,
    required this.onSecondary,
    required this.attnBg,
    required this.attnText,
    required this.hero,
    required this.heroText,
    required this.heroSub,
    required this.heroTrack,
    required this.heroChip,
    required this.good,
    required this.warn,
    required this.bad,
  });
}

const lightColors = LedgerColors(
  dark: false,
  bg: Color(0xFFF4F6F3),
  card: Color(0xFFFFFFFF),
  raised: Color(0xFFEDF1EE),
  text: Color(0xFF15211D),
  muted: Color(0xFF5B6863),
  divider: Color(0xFFE4E9E6),
  outline: Color(0xFFDCE3DF),
  primary: Color(0xFF0B6B57),
  onPrimary: Color(0xFFFFFFFF),
  primarySoft: Color(0xFFDDF0EA),
  onPrimarySoft: Color(0xFF08493C),
  secondary: Color(0xFFE8912D),
  onSecondary: Color(0xFF1E1404),
  attnBg: Color(0xFFFFF3E0),
  attnText: Color(0xFF8A4E06),
  hero: Color(0xFF0B6B57),
  heroText: Color(0xFFFFFFFF),
  heroSub: Color(0xFFCFE9E1),
  heroTrack: Color(0x38FFFFFF),
  heroChip: Color(0x1FFFFFFF),
  good: Color(0xFF1F7A4D),
  warn: Color(0xFFB4690E),
  bad: Color(0xFFB3362F),
);

const darkColors = LedgerColors(
  dark: true,
  bg: Color(0xFF0F1513),
  card: Color(0xFF18201D),
  raised: Color(0xFF212B27),
  text: Color(0xFFE8EEEB),
  muted: Color(0xFF9AA8A2),
  divider: Color(0xFF2B3631),
  outline: Color(0xFF3A4742),
  primary: Color(0xFF3FBF9B),
  onPrimary: Color(0xFF06231C),
  primarySoft: Color(0xFF173A31),
  onPrimarySoft: Color(0xFFBDEBDD),
  secondary: Color(0xFFF0A848),
  onSecondary: Color(0xFF241603),
  attnBg: Color(0xFF33240D),
  attnText: Color(0xFFF6C989),
  hero: Color(0xFF124A3E),
  heroText: Color(0xFFF1F5F3),
  heroSub: Color(0xBFF1F5F3),
  heroTrack: Color(0x33F1F5F3),
  heroChip: Color(0x14FFFFFF),
  good: Color(0xFF5CC98E),
  warn: Color(0xFFF0A848),
  bad: Color(0xFFF07A70),
);

bool _dark = false;

/// Current colours. The app root sets the mode before building any screen.
LedgerColors get lc => _dark ? darkColors : lightColors;
bool get isDarkMode => _dark;
void setDarkMode(bool v) => _dark = v;

const appFont = 'IBMPlexSansArabic';

ThemeData buildTheme(LedgerColors c) {
  final scheme = ColorScheme(
    brightness: c.dark ? Brightness.dark : Brightness.light,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primarySoft,
    onPrimaryContainer: c.onPrimarySoft,
    secondary: c.secondary,
    onSecondary: c.onSecondary,
    secondaryContainer: c.attnBg,
    onSecondaryContainer: c.attnText,
    tertiary: c.primary,
    onTertiary: c.onPrimary,
    error: c.bad,
    onError: c.dark ? const Color(0xFF2A0A07) : Colors.white,
    surface: c.card,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.card,
    surfaceContainerLow: c.card,
    surfaceContainer: c.raised,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.raised,
    outline: c.outline,
    outlineVariant: c.divider,
    shadow: Colors.black,
    inverseSurface: c.dark ? const Color(0xFFE8EEEB) : const Color(0xFF15211D),
    onInverseSurface: c.dark ? const Color(0xFF15211D) : const Color(0xFFF4F6F3),
  );
  final rounded14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: appFont);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: c.text,
      titleTextStyle: TextStyle(fontFamily: appFont, fontSize: 22, fontWeight: FontWeight.w700, color: c.text),
    ),
    cardTheme: CardTheme(
      color: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: rounded14,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: rounded14,
        side: BorderSide(color: c.outline),
        foregroundColor: c.text,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: rounded14,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: c.outline),
      backgroundColor: c.card,
      selectedColor: c.primarySoft,
      labelStyle: TextStyle(fontFamily: appFont, fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
      secondaryLabelStyle: TextStyle(fontFamily: appFont, fontSize: 13, fontWeight: FontWeight.w700, color: c.onPrimarySoft),
      checkmarkColor: c.onPrimarySoft,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.primary, width: 2)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(rounded14),
        side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.muted),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : null),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

// ------------------------------------------------------------ categories

const _categoryIcons = <String, IconData>{
  'Housing': Icons.home_outlined,
  'Utilities': Icons.bolt_outlined,
  'Groceries': Icons.shopping_cart_outlined,
  'Transport': Icons.directions_car_outlined,
  'Health': Icons.favorite_border,
  'Education': Icons.school_outlined,
  'Family': Icons.family_restroom,
  'Dining': Icons.restaurant,
  'Shopping': Icons.shopping_bag_outlined,
  'Subscriptions': Icons.subscriptions_outlined,
  'Entertainment': Icons.movie_outlined,
  'Travel': Icons.flight_takeoff,
  'Personal care': Icons.spa_outlined,
  'Charity': Icons.volunteer_activism_outlined,
  'Other': Icons.more_horiz,
  'Savings & investments': Icons.savings_outlined,
  'Salary': Icons.payments_outlined,
  'Housing allowance': Icons.account_balance_outlined,
  'Bonus': Icons.card_giftcard,
  'Consulting / freelance': Icons.work_outline,
  'Investment income': Icons.trending_up,
  'Refunds': Icons.undo,
  'Other income': Icons.add_card,
};

IconData categoryIcon(Category? c) {
  if (c == null) return Icons.help_outline;
  return _categoryIcons[c.name] ?? (c.kind == 'income' ? Icons.south_west : Icons.label_outline);
}

/// Icon colour for a category, lightened in dark mode so it stays readable.
Color categoryColor(Category? c) {
  final base = Color(c?.color ?? 0xFF8A9691);
  if (!_dark) return base;
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness + 0.28).clamp(0.0, 0.78)).toColor();
}

Color categoryTint(Category? c) => categoryColor(c).withOpacity(_dark ? 0.18 : 0.13);
