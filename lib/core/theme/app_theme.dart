import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Light and dark themes.
///
/// Everything visual is configured here rather than per-widget, so a screen can
/// be written with plain `ElevatedButton`s and `TextField`s and still look
/// right. Only genuinely reusable compositions live in `shared/widgets`.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
        surfaceAlt: AppColors.lightSurfaceAlt,
        border: AppColors.lightBorder,
        textPrimary: AppColors.lightTextPrimary,
        textSecondary: AppColors.lightTextSecondary,
        textTertiary: AppColors.lightTextTertiary,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        surfaceAlt: AppColors.darkSurfaceAlt,
        border: AppColors.darkBorder,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
        textTertiary: AppColors.darkTextTertiary,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
  }) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? AppColors.amber : AppColors.ink,
      onPrimary: isDark ? AppColors.ink : Colors.white,
      primaryContainer: isDark ? AppColors.inkSoft : AppColors.ink,
      onPrimaryContainer: Colors.white,
      secondary: AppColors.amber,
      onSecondary: AppColors.ink,
      secondaryContainer: isDark ? AppColors.inkMuted : AppColors.amberSoft,
      onSecondaryContainer: isDark ? AppColors.amber : AppColors.ink,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceAlt,
      onSurfaceVariant: textSecondary,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: isDark ? const Color(0xFF3A1D1D) : AppColors.dangerSoft,
      onErrorContainer: isDark ? const Color(0xFFFFB4AB) : AppColors.danger,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: textPrimary,
      onInverseSurface: surface,
    );

    final textTheme = _textTheme(textPrimary, textSecondary, textTertiary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      // Material's default is a visible ripple on every tap; a subtler splash
      // suits a utility app where people tap the same button repeatedly.
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: isDark ? AppColors.inkMuted : AppColors.lightBorder,
          disabledForegroundColor: textTertiary,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: border),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? AppColors.amber : AppColors.ink,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          minimumSize: const Size(0, AppSpacing.minTapTarget),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surfaceAlt : surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: textTertiary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(
          color: isDark ? AppColors.amber : AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        // Errors wrap to two lines rather than being clipped, because a
        // server-side field error can be a full sentence.
        errorMaxLines: 2,
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: isDark ? AppColors.amber : AppColors.ink, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
        showDragHandle: true,
        dragHandleColor: textTertiary,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: border),
        labelStyle: textTheme.labelMedium?.copyWith(color: textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.amber,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? AppColors.amber : AppColors.ink,
        unselectedLabelColor: textSecondary,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorColor: isDark ? AppColors.amber : AppColors.ink,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: isDark ? AppColors.amber : AppColors.ink,
        unselectedItemColor: textTertiary,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.ink : surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.amber : surfaceAlt,
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        minVerticalPadding: AppSpacing.md,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? AppColors.amber : AppColors.ink,
        linearTrackColor: surfaceAlt,
        circularTrackColor: Colors.transparent,
      ),
    );
  }

  static TextTheme _textTheme(Color primary, Color secondary, Color tertiary) {
    // Tighter letter spacing on headings and a generous line height on body
    // text: addresses and fare breakdowns are read, not skimmed.
    return TextTheme(
      displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.8),
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.6),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.4),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: primary, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: primary),
      titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: TextStyle(fontSize: 16, color: primary, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, color: primary, height: 1.45),
      bodySmall: TextStyle(fontSize: 12.5, color: secondary, height: 1.4),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primary),
      labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondary),
      labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: tertiary, letterSpacing: 0.2),
    );
  }
}
