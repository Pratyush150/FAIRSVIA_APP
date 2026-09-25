import 'package:flutter/material.dart';

import 'app_clay3d.dart';
import 'app_colors.dart';
import 'app_glass.dart';
import 'phosphor_icons.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'app_variant.dart';

/// Light and dark themes shared by all three apps. Component themes are tuned so
/// even un-restyled Material widgets (cards, chips, inputs, dialogs) inherit the
/// warm, rounded, low-chrome look.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceMuted =
        isDark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight;
    final background =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    // The theme is built for a given brightness, not the app's current one, so
    // it takes the ink explicitly rather than from AppColors.accent.
    final ink = AppColors.inkFor(isDark);
    final onInk = AppColors.onInkFor(isDark);
    final soft = AppColors.softFor(isDark);
    // The v2 builds use the audit's brighter dark-mode danger (#FF4D4F); the
    // shipped turquoise default keeps the red its screens were tuned with.
    final danger =
        isDark && AppColors.v2 ? AppColors.dangerDark : AppColors.error;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: ink,
      onPrimary: onInk,
      primaryContainer: soft,
      onPrimaryContainer: ink,
      secondary: textPrimary,
      onSecondary: surface,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border,
      error: danger,
      onError: Colors.white,
      surfaceTint: Colors.transparent,
    );

    final text = AppTypography.textTheme(textPrimary, textSecondary);
    // Plan D: sheets are warm paper, not white; cards on them stay white.
    final sheet = AppVariant.local ? LocalColour.paperFor(isDark) : surface;
    // Modal surfaces (sheets, dialogs, menus): Plan F uses glass's opaque
    // surface.solid and the glass corner radius so they match the floating
    // AppSheet; every other build keeps its sheet colour and radii.
    final modalSurface = AppGlass.enabled ? AppGlass.solid(isDark) : sheet;
    final modalRadius =
        AppGlass.enabled ? AppGlass.sheetRadius : AppSpacing.radiusXl;

    OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      textTheme: text,
      // Quiet press feedback: a flat highlight, not a sparkle.
      splashFactory: InkRipple.splashFactory,
      dividerColor: border,
      // 24 = the utility size (audit 2.1 rule 2: 24 / 20 / 16 only). Was 22,
      // which made every unsized icon off-scale.
      iconTheme: IconThemeData(color: textPrimary, size: AppIconSize.utility),

      // THEME=clay3d: Material's back / close / drawer glyphs are the only
      // icons not drawn from Phosphor, so they would stay flat line art;
      // route them through the 3D font like every other icon.
      actionIconTheme: AppClay3D.on
          ? ActionIconThemeData(
              backButtonIconBuilder: (_) =>
                  const Icon(PhosphorIconsRegular.arrowLeft),
              closeButtonIconBuilder: (_) => const Icon(PhosphorIconsRegular.x),
              drawerButtonIconBuilder: (_) =>
                  const Icon(PhosphorIconsRegular.list),
              endDrawerButtonIconBuilder: (_) =>
                  const Icon(PhosphorIconsRegular.list),
            )
          : null,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        // Secondary, not tertiary, grey: tertiary is 4.6:1 on white but only
        // ~4.1:1 on the muted field fill — under WCAG AA (audit 4.3).
        hintStyle: text.bodyLarge?.copyWith(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
        ),
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(ink, 1.6),
        errorBorder: inputBorder(danger),
        focusedErrorBorder: inputBorder(danger, 1.6),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: onInk,
          disabledBackgroundColor: ink.withValues(alpha: 0.3),
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          // Button glyphs are 20 (Material's default 18 is off-scale).
          iconSize: 20,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          iconSize: 20,
          side: BorderSide(color: border, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // Plan F: text buttons sit on glass, so they take the deeper
          // brand-text teal (AppColors.accentTextFor); the ink elsewhere.
          foregroundColor: AppColors.accentTextFor(isDark),
          // Tertiary actions: at least the 44 pt touch target.
          minimumSize: const Size(AppSpacing.buttonHeightTertiary,
              AppSpacing.buttonHeightTertiary),
          iconSize: 20,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
        ),
      ),

      // Audit 2026-09-25 item 8: one sheet / dialog / menu family. Plan F
      // modal sheets open through core's showAppModalSheet (the inset glass
      // card); any sheet opened directly still gets the glass radius and the
      // solid glass surface, so nothing falls back to a white slab. Dialogs
      // and popup menus share the same surface and corner family.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: modalSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: modalSurface,
        elevation: 0,
        showDragHandle: false,
        dragHandleColor: textSecondary.withValues(alpha: 0.4),
        dragHandleSize: const Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(modalRadius),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: modalSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppGlass.enabled ? modalRadius : AppSpacing.radiusLg,
          ),
        ),
        titleTextStyle: text.titleLarge,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: modalSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        textStyle: text.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: border),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: soft,
        side: BorderSide(color: border),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium
            ?.copyWith(color: ink),
        shape: const StadiumBorder(),
        // Chip glyphs on the 20 step (Material's default is 18).
        iconTheme: const IconThemeData(size: AppIconSize.chip),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor:
            AppColors.v2 ? AppColors.iconNeutralFor(isDark) : textSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.screenMargin),
        titleTextStyle: text.titleMedium,
        subtitleTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? onInk : surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? ink
              : (isDark ? AppColors.surfaceMutedDark : AppColors.borderLight),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.surfaceMutedDark : AppColors.primary,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(
            color: ink),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: text.labelMedium
            ?.copyWith(color: ink),
        unselectedLabelTextStyle: text.labelMedium,
        indicatorColor: soft,
        useIndicator: true,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: onInk,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),
    );
  }
}
