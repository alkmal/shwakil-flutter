import 'package:flutter/material.dart';

/// Centralized Design System for Shwakel App
class AppTheme {
  // --- Primary Palettes ---
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryLight = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF0D635C);

  static const Color secondary = Color(0xFF0F172A);
  static const Color secondaryLight = Color(0xFF1E293B);

  static const Color accent = Color(0xFF0284C7);
  static const Color accentLight = Color(0xFF38BDF8);

  // --- Neutral Palettes ---
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color surfaceMuted = Color(0xFFECFDF5);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color tabSurface = Color(0xFFE6FFFB);
  static const Color sidebarSurface = Color(0xFFF4F7FB);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textOnDark = Color(0xFFF8FAFC);
  static const Color textMutedOnDark = Color(0xFFD7E8E4);

  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);

  // --- Feedback Colors ---
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF0284C7);
  static const Color infoLight = Color(0xFFE0F2FE);

  // --- Spacing ---
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // --- Shadows ---
  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: const Color(0x080F172A),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get mediumShadow => [
    BoxShadow(
      color: const Color(0x0C0F172A),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get premiumShadow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.10),
      blurRadius: 34,
      offset: const Offset(0, 14),
    ),
  ];

  // --- Gradients ---
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [secondary, Color(0xFF1E293B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient successGradient = LinearGradient(
    colors: [success, success.withValues(alpha: 0.8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient pageBackgroundGradient = LinearGradient(
    colors: [Color(0xFFF8FAFC), Color(0xFFF0FDFA), Color(0xFFF8FAFC)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  // --- Radius ---
  static BorderRadius get radiusSm => BorderRadius.circular(8);
  static BorderRadius get radiusMd => BorderRadius.circular(18);
  static BorderRadius get radiusLg => BorderRadius.circular(28);
  static BorderRadius get radiusXl => BorderRadius.circular(34);

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 700 && width < 1100;
  }

  static double fluid(
    BuildContext context, {
    required double mobile,
    double? tablet,
    required double desktop,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) {
      return mobile;
    }
    if (width < 1100) {
      return tablet ?? ((mobile + desktop) / 2);
    }
    return desktop;
  }

  // --- Typography (Custom Styles) ---
  static TextStyle get h1 => const TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: textPrimary,
    height: 1.2,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get h2 => const TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    height: 1.3,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get h3 => const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get bodyText => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    height: 1.5,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get bodyBold => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get bodyAction => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textSecondary,
    fontFamily: 'NotoSansArabic',
  );

  static TextStyle get caption => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    fontFamily: 'NotoSansArabic',
  );

  // --- Main Theme Data ---
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansArabic',
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: textPrimary,
        brightness: Brightness.light,
        error: error,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      iconTheme: const IconThemeData(color: textPrimary, size: 22),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 70,
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          fontFamily: 'NotoSansArabic',
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 24,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'NotoSansArabic',
          ),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'NotoSansArabic',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: error, width: 1.6),
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        labelStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: textTertiary,
          fontWeight: FontWeight.w400,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: tabSurface,
        disabledColor: borderLight,
        side: const BorderSide(color: border, width: 1),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        labelStyle: bodyAction,
        secondaryLabelStyle: bodyAction.copyWith(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: softShadow,
        ),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: bodyBold.copyWith(fontSize: 14),
        unselectedLabelStyle: bodyAction.copyWith(fontSize: 14),
        splashBorderRadius: radiusMd,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: secondary,
        contentTextStyle: bodyText.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusLg),
        titleTextStyle: h2,
        contentTextStyle: bodyText,
      ),
    );
  }
}
