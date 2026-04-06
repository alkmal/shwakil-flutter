import 'package:flutter/material.dart';

/// Centralized Design System for Shwakel App
class AppTheme {
  // --- Primary Palettes ---
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryLight = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF0D635C);
  static const Color primarySoft = Color(0xFFCCFBF1);

  static const Color secondary = Color(0xFF0F172A);
  static const Color secondaryLight = Color(0xFF1E293B);
  static const Color secondarySoft = Color(0xFFE2E8F0);

  static const Color accent = Color(0xFF0284C7);
  static const Color accentLight = Color(0xFF38BDF8);
  static const Color accentSoft = Color(0xFFE0F2FE);
  static const Color highlight = Color(0xFFF59E0B);

  // --- Neutral Palettes ---
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color surfaceMuted = Color(0xFFECFDF5);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color tabSurface = Color(0xFFE6FFFB);
  static const Color tabSurfaceMuted = Color(0xFFF1F5F9);
  static const Color sidebarSurface = Color(0xFFF4F7FB);
  static const Color inputFill = Color(0xFFF8FBFF);
  static const Color inputFocusFill = Color(0xFFF2FFFC);
  static const Color glassStroke = Color(0xFFF8FAFC);

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
      color: const Color(0x0A0F172A),
      blurRadius: 22,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get mediumShadow => [
    BoxShadow(
      color: const Color(0x120F172A),
      blurRadius: 32,
      offset: const Offset(0, 16),
    ),
  ];

  static List<BoxShadow> get premiumShadow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.10),
      blurRadius: 48,
      offset: const Offset(0, 22),
    ),
    BoxShadow(
      color: secondary.withValues(alpha: 0.07),
      blurRadius: 30,
      offset: const Offset(0, 12),
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
    colors: [Color(0xFFF8FAFC), Color(0xFFF2FBF9), Color(0xFFF4F8FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient shellGradient = LinearGradient(
    colors: [Color(0xFFF8FAFC), Color(0xFFEFFAF7), Color(0xFFF5FAFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF0F766E), Color(0xFF2DD4BF)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient cardHighlightGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF3FFFC)],
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

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1440) return 48;
    if (width >= 1100) return 32;
    if (width >= 720) return 24;
    return 16;
  }

  static EdgeInsets pagePadding(BuildContext context, {double top = 20}) {
    return EdgeInsets.fromLTRB(
      horizontalPadding(context),
      top,
      horizontalPadding(context),
      28,
    );
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
        backgroundColor: Colors.transparent,
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
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 17,
        ),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: border, width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: border, width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: const BorderSide(color: error, width: 1.6),
        ),
        prefixIconColor: primary,
        suffixIconColor: textSecondary,
        helperMaxLines: 3,
        labelStyle: const TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: textTertiary,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: const TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
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
        tabAlignment: TabAlignment.fill,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF2FFFC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: softShadow,
          border: Border.all(color: primary.withValues(alpha: 0.10)),
        ),
        dividerColor: borderLight,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: bodyBold.copyWith(fontSize: 14),
        unselectedLabelStyle: bodyAction.copyWith(fontSize: 14),
        splashBorderRadius: radiusMd,
        overlayColor: WidgetStatePropertyAll(primary.withValues(alpha: 0.05)),
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
