import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'neo.dart';

/// Alma's Neo-Brutalist theme.
///
/// A light, high-contrast system: warm cream canvas, flat saturated pastels,
/// solid black strokes and hard block shadows, heavy black type. Every Material
/// surface is wired here so components we don't hand-build still land in style.
///
/// Reusable neo-brutalist widgets live in [neo.dart].
class AppTheme {
  AppTheme._();

  /// The app's normal system-bar dressing: transparent status bar with dark
  /// glyphs over the cream canvas.
  ///
  /// Lives here rather than inline in `main()` because anything that goes
  /// fullscreen has to put it back exactly as it was on the way out.
  static const SystemUiOverlayStyle systemOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Neo.paper,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// Restore the normal chrome after a fullscreen sequence.
  static void restoreSystemChrome() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(systemOverlayStyle);
  }

  static ThemeData neo() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Neo.pink,
      onPrimary: Neo.ink,
      primaryContainer: Neo.rose,
      onPrimaryContainer: Neo.ink,
      secondary: Neo.coral,
      onSecondary: Neo.ink,
      secondaryContainer: Neo.yellow,
      onSecondaryContainer: Neo.ink,
      tertiary: Neo.lilac,
      onTertiary: Neo.ink,
      tertiaryContainer: Neo.sky,
      onTertiaryContainer: Neo.ink,
      error: Neo.danger,
      onError: Neo.white,
      errorContainer: Color(0xFFFFD9D9),
      onErrorContainer: Neo.ink,
      surface: Neo.paper,
      onSurface: Neo.ink,
      surfaceContainerLowest: Neo.white,
      surfaceContainerLow: Neo.white,
      surfaceContainer: Neo.white,
      surfaceContainerHigh: Neo.white,
      surfaceContainerHighest: Color(0xFFF3E6CF),
      surfaceTint: Colors.transparent,
      onSurfaceVariant: Color(0xFF5C534A),
      outline: Neo.ink,
      outlineVariant: Neo.ink,
      shadow: Neo.ink,
      scrim: Neo.ink,
      inverseSurface: Neo.ink,
      onInverseSurface: Neo.paper,
      inversePrimary: Neo.pink,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );

    final text = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Neo.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: const IconThemeData(color: Neo.ink),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      iconTheme: const IconThemeData(color: Neo.ink),
      dividerTheme: const DividerThemeData(
        color: Neo.ink,
        space: 1,
        thickness: 2,
      ),
      cardTheme: CardThemeData(
        color: Neo.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Neo.corner,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Neo.white,
        hintStyle: text.bodyMedium?.copyWith(
          color: Neo.ink.withValues(alpha: .45),
          fontWeight: FontWeight.w600,
        ),
        labelStyle: text.bodyMedium?.copyWith(
          color: Neo.ink.withValues(alpha: .7),
          fontWeight: FontWeight.w700,
        ),
        floatingLabelStyle: text.labelLarge?.copyWith(
          color: Neo.accent,
          fontWeight: FontWeight.w800,
        ),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        counterStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: Neo.cornerSm,
          borderSide: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Neo.cornerSm,
          borderSide: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Neo.cornerSm,
          borderSide: const BorderSide(color: Neo.accent, width: Neo.stroke),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Neo.cornerSm,
          borderSide: const BorderSide(color: Neo.danger, width: Neo.stroke),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Neo.cornerSm,
          borderSide: const BorderSide(color: Neo.danger, width: Neo.stroke),
        ),
        prefixIconColor: Neo.ink,
        suffixIconColor: Neo.ink,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Neo.pink,
          foregroundColor: Neo.ink,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: Neo.corner,
            side: const BorderSide(color: Neo.ink, width: Neo.stroke),
          ),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Neo.white,
          foregroundColor: Neo.ink,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: Neo.corner),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Neo.ink,
          textStyle: text.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
            decorationColor: Neo.accent,
            decorationThickness: 2.5,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: Neo.ink,
        unselectedLabelColor: Neo.ink.withValues(alpha: .5),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: Neo.accent, width: 4),
          insets: EdgeInsets.symmetric(horizontal: 8),
        ),
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        dividerColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Neo.ink,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: Neo.white,
          fontWeight: FontWeight.w700,
        ),
        actionTextColor: Neo.yellow,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: Neo.cornerSm,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Neo.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Neo.corner,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Neo.paper,
        modalBackgroundColor: Neo.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
        showDragHandle: true,
        dragHandleColor: Neo.ink,
        dragHandleSize: Size(48, 5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Neo.ink,
        linearTrackColor: Neo.rose,
        circularTrackColor: Colors.transparent,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Neo.ink),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Neo.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        textStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: Neo.cornerSm,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Neo.white,
        labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w800),
        selectedColor: Neo.lilac,
        side: const BorderSide(color: Neo.ink, width: Neo.strokeThin),
        shape: RoundedRectangleBorder(borderRadius: Neo.cornerSm),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Neo.ink : Neo.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Neo.mint : Neo.white,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Neo.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(Neo.strokeThin),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Neo.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Neo.pink,
        headerForegroundColor: Neo.ink,
        shape: RoundedRectangleBorder(
          borderRadius: Neo.corner,
          side: const BorderSide(color: Neo.ink, width: Neo.stroke),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: Neo.ink, borderRadius: Neo.cornerSm),
        textStyle: const TextStyle(
          color: Neo.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle display(double size, {double spacing = -1.0}) => TextStyle(
      fontSize: size,
      height: 1.02,
      fontWeight: FontWeight.w900,
      color: Neo.ink,
      letterSpacing: spacing,
    );

    TextStyle body(
      double size, {
      FontWeight weight = FontWeight.w600,
      Color? color,
    }) => TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: weight,
      color: color ?? Neo.ink,
    );

    return base.copyWith(
      displayLarge: display(60),
      displayMedium: display(46),
      displaySmall: display(36),
      headlineLarge: display(30),
      headlineMedium: display(26, spacing: -0.5),
      headlineSmall: display(22, spacing: -0.5),
      titleLarge: body(20, weight: FontWeight.w800),
      titleMedium: body(16, weight: FontWeight.w800),
      titleSmall: body(14, weight: FontWeight.w700),
      bodyLarge: body(16),
      bodyMedium: body(14),
      bodySmall: body(12, color: scheme.onSurfaceVariant),
      labelLarge: body(14, weight: FontWeight.w800),
      labelMedium: body(12, weight: FontWeight.w700),
      labelSmall: body(11, weight: FontWeight.w700),
    );
  }
}
