import 'package:flutter/material.dart';

/// Brand palette, ported from the React app's CSS custom properties
/// (src/index.css). Primary is a vivid violet (oklch 0.65 0.25 270),
/// accent a bright cyan, on a deep-navy (or OLED black) surface.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF3B82F6); // blue-500
  static const Color primaryDim = Color(0xFF2563EB); // blue-600
  static const Color accent = Color(0xFF22D3EE); // cyan-400
  static const Color destructive = Color(0xFFE5484D);
  static const Color favorite = Color(0xFFF43F5E);

  // Deep-navy ("Deep Navy" theme)
  static const Color navyBackground = Color(0xFF101018);
  static const Color navyCard = Color(0xFF1A1B26);
  static const Color navyElevated = Color(0xFF222433);

  // OLED ("OLED Pure Black" theme)
  static const Color oledBackground = Color(0xFF000000);
  static const Color oledCard = Color(0xFF0C0C10);
  static const Color oledElevated = Color(0xFF16161C);

  static const Color foreground = Color(0xFFF4F4F6);
  static const Color mutedForeground = Color(0xFF9A9AA7);
  static const Color border = Color(0x1FFFFFFF); // white @ ~12%

  // Status accents (ported from --stream-* tokens).
  static const Color success = Color(0xFF34D399); // emerald-400
  static const Color warning = Color(0xFFFBBF24); // amber-400
  static const Color cyan = Color(0xFF22D3EE); // cyan-400

  // Glass tokens (ported from --stream-glass-*).
  static const Color glassFill = Color(0x0AFFFFFF); // white @ 4%
  static const Color glassBorder = Color(0x14FFFFFF); // white @ 8%

  // Brand gradient (blue → cyan), the app's signature accent. Used instead
  // of flat fills so surfaces read vibrant rather than bland.
  static const Color gradientStart = Color(0xFF3B82F6); // blue-500
  static const Color gradientEnd = Color(0xFF22D3EE); // cyan-400

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  /// A soft violet glow (ports the `.glow-*` box-shadow utilities).
  static List<BoxShadow> glow({double blur = 30, double spread = -5, double alpha = 0.4}) => [
        BoxShadow(
          color: primary.withValues(alpha: alpha),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];

  /// Quality badge color, falling back to muted grey.
  static Color quality(String q) => const {
        '4K': Color(0xFFE8B4B8),
        '2160p': Color(0xFFE8B4B8),
        '1080p': Color(0xFF7DD3FC),
        '720p': Color(0xFF86EFAC),
        '480p': Color(0xFFFCD34D),
        'CAM': Color(0xFFF87171),
        'TS': Color(0xFFF87171),
        'SCR': Color(0xFFFBBF24),
      }[q] ??
      mutedForeground;

  /// Quality badge (fill, text, border) tuple — ports StreamCard.tsx's
  /// getQualityBadgeColor (purple / sky / emerald / neutral families).
  static ({Color bg, Color fg, Color border}) qualityBadge(String q) {
    final u = q.toUpperCase();
    if (u.contains('4K') || u.contains('2160P')) {
      return (
        bg: const Color(0xFFA855F7).withValues(alpha: 0.15),
        fg: const Color(0xFFC084FC),
        border: const Color(0xFFA855F7).withValues(alpha: 0.25),
      );
    }
    if (u.contains('1080P')) {
      return (
        bg: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
        fg: const Color(0xFF38BDF8),
        border: const Color(0xFF0EA5E9).withValues(alpha: 0.25),
      );
    }
    if (u.contains('720P')) {
      return (
        bg: const Color(0xFF10B981).withValues(alpha: 0.15),
        fg: const Color(0xFF34D399),
        border: const Color(0xFF10B981).withValues(alpha: 0.25),
      );
    }
    return (
      bg: const Color(0xFF737373).withValues(alpha: 0.15),
      fg: const Color(0xFFA3A3A3),
      border: const Color(0xFF737373).withValues(alpha: 0.25),
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(
        background: AppColors.navyBackground,
        card: AppColors.navyCard,
        elevated: AppColors.navyElevated,
      );

  static ThemeData oled() => _build(
        background: AppColors.oledBackground,
        card: AppColors.oledCard,
        elevated: AppColors.oledElevated,
      );

  static ThemeData _build({
    required Color background,
    required Color card,
    required Color elevated,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: background,
      surfaceContainer: card,
      surfaceContainerHigh: elevated,
      error: AppColors.destructive,
      onSurface: AppColors.foreground,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // Transparent so the ambient AuroraBackground (painted behind every
      // route) shows through and the Glass surfaces have colour to refract.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      // System default sans (Roboto / Segoe) tuned for a tight, modern look.
      fontFamily: null,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.foreground,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        hintStyle: const TextStyle(color: AppColors.mutedForeground),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.foreground,
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    TextStyle h(TextStyle? s) => (s ?? const TextStyle()).copyWith(
          color: AppColors.foreground,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        );
    return base
        .copyWith(
          displayLarge: h(base.displayLarge),
          displayMedium: h(base.displayMedium),
          headlineLarge: h(base.headlineLarge),
          headlineMedium: h(base.headlineMedium),
          headlineSmall: h(base.headlineSmall),
          titleLarge: h(base.titleLarge),
        )
        .apply(
          bodyColor: AppColors.foreground,
          displayColor: AppColors.foreground,
        );
  }
}
