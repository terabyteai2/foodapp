import 'package:flutter/material.dart';

// ignore_for_file: unused_element
enum PosThemeTone { dark, light }

class _PosPalette {
  const _PosPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.primaryGlow,
    required this.accent,
    required this.accentSoft,
    required this.background,
    required this.surface,
    required this.surfaceWarm,
    required this.surfaceTinted,
    required this.slate,
    required this.slateSoft,
    required this.muted,
    required this.mutedSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.purple,
    required this.line,
    required this.lineStrong,
  });

  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color primaryGlow;
  final Color accent;
  final Color accentSoft;
  final Color background;
  final Color surface;
  final Color surfaceWarm;
  final Color surfaceTinted;
  final Color slate;
  final Color slateSoft;
  final Color muted;
  final Color mutedSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color purple;
  final Color line;
  final Color lineStrong;
}

class PosColors {
  // Dark-first palette — exact tokens from wireframe SystemNotes
  static const _dark = _PosPalette(
    primary: Color(0xFFE8C547), // brand
    primaryDark: Color(
      0xFF14110E,
    ), // surface-0 / app bg (used as dark fg on brand buttons)
    primarySoft: Color(0x33E8C547), // brand/20 tint
    primaryGlow: Color(0xFFE8C547),
    accent: Color(0xFFE8A14A), // cooking / warm accent
    accentSoft: Color(0x1AE8C547),
    background: Color(0xFF14110E), // surface-0
    surface: Color(0xFF1F1C18), // surface-1 / cards
    surfaceWarm: Color(0xFF2A2622), // surface-2 / raised elements
    surfaceTinted: Color(0xFF2A2622),
    slate: Color(0xFFF6F1E4), // ink-hi / titles
    slateSoft: Color(0xFFD8D2C2),
    muted: Color(0xFF9A9388), // ink-lo / supporting text
    mutedSoft: Color(0xFF5A5450),
    success: Color(0xFF7BB47C), // ready / green state
    warning: Color(0xFFE8A14A), // cooking state
    danger: Color(0xFFD86A55), // danger state
    info: Color(0xFF4BA3F5),
    purple: Color(0xFFB97AF7),
    line: Color(0xFF2A2622), // hairline divider
    lineStrong: Color(0xFF3A3630),
  );

  // Light palette (kept for compatibility)
  static const _light = _PosPalette(
    primary: Color(0xFFFFD928),
    primaryDark: Color(0xFF111111),
    primarySoft: Color(0xFFFFF0A8),
    primaryGlow: Color(0xFFFFE45C),
    accent: Color(0xFFFFC400),
    accentSoft: Color(0xFFFFF7D6),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF8F7F5),
    surfaceWarm: Color(0xFFF4F3F0),
    surfaceTinted: Color(0xFFFFFBF0),
    slate: Color(0xFF0B0B0B),
    slateSoft: Color(0xFF1F1F1F),
    muted: Color(0xFF4B4B4B),
    mutedSoft: Color(0xFF9B9B9B),
    success: Color(0xFF16A34A),
    warning: Color(0xFFFFB300),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    purple: Color(0xFF7C3AED),
    line: Color(0xFFEDEDED),
    lineStrong: Color(0xFFD8D8D8),
  );

  static _PosPalette _active = _dark;
  static PosThemeTone _tone = PosThemeTone.dark;

  static PosThemeTone get tone => _tone;

  static void setTone(PosThemeTone tone) {
    _tone = tone;
    _active = tone == PosThemeTone.dark ? _dark : _light;
  }

  static Color get primary => _active.primary;
  static Color get primaryDark => _active.primaryDark;
  static Color get primarySoft => _active.primarySoft;
  static Color get primaryGlow => _active.primaryGlow;
  static Color get accent => _active.accent;
  static Color get accentSoft => _active.accentSoft;
  static Color get background => _active.background;
  static Color get surface => _active.surface;
  static Color get surfaceWarm => _active.surfaceWarm;
  static Color get surfaceTinted => _active.surfaceTinted;
  static Color get slate => _active.slate;
  static Color get slateSoft => _active.slateSoft;
  static Color get muted => _active.muted;
  static Color get mutedSoft => _active.mutedSoft;
  static Color get success => _active.success;
  static Color get warning => _active.warning;
  static Color get danger => _active.danger;
  static Color get info => _active.info;
  static Color get purple => _active.purple;
  static Color get line => _active.line;
  static Color get lineStrong => _active.lineStrong;
}

class PosRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}

class PosShadows {
  static List<BoxShadow> get card => [
    BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x22000000), blurRadius: 30, offset: Offset(0, 16)),
  ];

  static List<BoxShadow> get raised => [
    BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(color: Color(0x44F2C744), blurRadius: 26, offset: Offset(0, 14)),
  ];
}

class PosGradients {
  static LinearGradient get brand => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PosColors.primary, Color(0xFFE0B030)],
  );

  static LinearGradient get brandDeep => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PosColors.primary, Color(0xFFC89A20)],
  );

  static LinearGradient softWash({double opacity = 0.72}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [PosColors.background, PosColors.background],
  );

  static LinearGradient cardTint(Color color) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [PosColors.surface, PosColors.surface],
  );
}

class AppTheme {
  static ThemeData dark({double uiScale = 1.0}) {
    PosColors.setTone(PosThemeTone.dark);
    return _build(uiScale: uiScale, brightness: Brightness.dark);
  }

  static ThemeData light({double uiScale = 1.0}) {
    PosColors.setTone(PosThemeTone.light);
    return _build(uiScale: uiScale, brightness: Brightness.light);
  }

  static ThemeData _build({
    required double uiScale,
    required Brightness brightness,
  }) {
    final scale = uiScale.clamp(1.0, 1.28).toDouble();
    double s(double value) => (value * scale).toDouble();

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: PosColors.primary,
          primary: PosColors.primary,
          secondary: PosColors.accent,
          surface: PosColors.surface,
          error: PosColors.danger,
          brightness: brightness,
        ).copyWith(
          surface: PosColors.surface,
          onSurface: PosColors.slate,
          surfaceContainerHighest: PosColors.surfaceWarm,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: PosColors.background,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displaySmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          color: PosColors.slate,
          height: 1.06,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: PosColors.slate,
          height: 1.1,
        ),
        titleLarge: TextStyle(
          fontSize: 18.5,
          fontWeight: FontWeight.w800,
          color: PosColors.slate,
          height: 1.18,
        ),
        titleMedium: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: PosColors.slate,
          height: 1.22,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: PosColors.slate,
          height: 1.22,
        ),
        bodyLarge: TextStyle(
          fontSize: 14.4,
          color: PosColors.slate,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 12.8,
          color: PosColors.muted,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          fontSize: 11.5,
          color: PosColors.muted,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: TextStyle(
          fontSize: 13.2,
          color: PosColors.slate,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: PosColors.background,
        foregroundColor: PosColors.slate,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: const Color(0x66000000),
        color: PosColors.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.lg)),
          side: BorderSide(color: PosColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PosColors.surfaceWarm,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
          borderSide: BorderSide(color: PosColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
          borderSide: BorderSide(color: PosColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
          borderSide: BorderSide(color: PosColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
          borderSide: BorderSide(color: PosColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
          borderSide: BorderSide(color: PosColors.danger, width: 1.6),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: s(14),
          vertical: s(13),
        ),
        labelStyle: TextStyle(
          color: PosColors.muted,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: PosColors.muted),
        prefixIconColor: PosColors.muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(s(44), s(40)),
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: PosColors.primary,
          foregroundColor: PosColors.primaryDark,
          padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(10)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s(PosRadii.sm + 2)),
          ),
          textStyle: TextStyle(
            fontSize: s(13.0),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(s(44), s(40)),
          backgroundColor: PosColors.primary,
          foregroundColor: PosColors.primaryDark,
          padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(10)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s(PosRadii.sm + 2)),
          ),
          textStyle: TextStyle(fontSize: s(13.0), fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(s(44), s(40)),
          foregroundColor: PosColors.slate,
          backgroundColor: Colors.transparent,
          side: BorderSide(color: PosColors.lineStrong),
          padding: EdgeInsets.symmetric(horizontal: s(14), vertical: s(10)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s(PosRadii.sm + 2)),
          ),
          textStyle: TextStyle(
            fontSize: s(13.0),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PosColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: PosColors.slate,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s(PosRadii.sm)),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: s(66),
        backgroundColor: PosColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x50000000),
        indicatorColor: PosColors.primarySoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(s(PosRadii.md)),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: s(11),
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            color: selected ? PosColors.primary : PosColors.muted,
            letterSpacing: 0.1,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: selected ? s(22) : s(20),
            color: selected ? PosColors.primary : PosColors.muted,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: PosColors.surface,
        selectedIconTheme: IconThemeData(color: PosColors.primary, size: s(21)),
        unselectedIconTheme: IconThemeData(color: PosColors.muted, size: s(20)),
        selectedLabelTextStyle: TextStyle(
          color: PosColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: s(12),
          letterSpacing: 0.1,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: PosColors.muted,
          fontWeight: FontWeight.w700,
          fontSize: s(12),
        ),
        indicatorColor: PosColors.primarySoft,
        useIndicator: true,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? PosColors.primarySoft
                : PosColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? PosColors.primary
                : PosColors.muted,
          ),
          side: WidgetStateProperty.all(BorderSide(color: PosColors.line)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PosRadii.sm + 2),
            ),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: PosColors.surface,
        selectedColor: PosColors.primarySoft,
        side: BorderSide(color: PosColors.line),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: PosColors.slate,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: PosColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PosRadii.pill),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PosColors.primaryDark
              : PosColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? PosColors.primary
              : PosColors.lineStrong,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      dividerTheme: DividerThemeData(
        color: PosColors.line,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: PosColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PosRadii.xl),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: PosColors.slate,
        ),
        contentTextStyle: TextStyle(
          fontSize: 13.6,
          color: PosColors.muted,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: PosColors.surface,
        modalBackgroundColor: PosColors.surface,
        showDragHandle: true,
        dragHandleColor: PosColors.lineStrong,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: PosColors.surfaceWarm,
        contentTextStyle: TextStyle(
          color: PosColors.slate,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PosRadii.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: PosColors.surfaceWarm,
          borderRadius: BorderRadius.circular(PosRadii.xs + 2),
          border: Border.all(color: PosColors.line),
        ),
        textStyle: TextStyle(
          color: PosColors.slate,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: PosColors.primary,
        linearTrackColor: PosColors.surfaceWarm,
        circularTrackColor: PosColors.surfaceWarm,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: PosColors.primary,
        inactiveTrackColor: PosColors.lineStrong,
        thumbColor: PosColors.primary,
        overlayColor: PosColors.primary.withValues(alpha: 0.12),
        valueIndicatorColor: PosColors.primary,
        valueIndicatorTextStyle: TextStyle(
          color: PosColors.primaryDark,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
