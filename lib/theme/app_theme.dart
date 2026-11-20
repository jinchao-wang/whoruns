import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// App 自己的语义色。
///
/// 风险等级有固定的含义（高危=红、可疑=橙、留意=黄、正常=绿），
/// 明暗两套色值都要单独配：在深色模式下直接把亮色搬过来会刺眼。
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.danger,
    required this.warning,
    required this.watch,
    required this.safe,
    required this.dangerContainer,
    required this.warningContainer,
    required this.watchContainer,
    required this.safeContainer,
    required this.neutralContainer,
  });

  final Brightness brightness;

  /// 高危。
  final Color danger;

  /// 可疑。
  final Color warning;

  /// 留意。
  final Color watch;

  /// 正常。
  final Color safe;

  final Color dangerContainer;
  final Color warningContainer;
  final Color watchContainer;
  final Color safeContainer;
  final Color neutralContainer;

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? danger,
    Color? warning,
    Color? watch,
    Color? safe,
    Color? dangerContainer,
    Color? warningContainer,
    Color? watchContainer,
    Color? safeContainer,
    Color? neutralContainer,
  }) {
    return AppColors(
      brightness: brightness ?? this.brightness,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      watch: watch ?? this.watch,
      safe: safe ?? this.safe,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      watchContainer: watchContainer ?? this.watchContainer,
      safeContainer: safeContainer ?? this.safeContainer,
      neutralContainer: neutralContainer ?? this.neutralContainer,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      watch: Color.lerp(watch, other.watch, t)!,
      safe: Color.lerp(safe, other.safe, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      watchContainer: Color.lerp(watchContainer, other.watchContainer, t)!,
      safeContainer: Color.lerp(safeContainer, other.safeContainer, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
    );
  }
}

/// 取主题的快捷方式。
extension AppThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);

  ColorScheme get scheme => Theme.of(this).colorScheme;

  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      const AppColors(
        brightness: Brightness.light,
        danger: Color(0xFFD64541),
        warning: Color(0xFFE08A1E),
        watch: Color(0xFFB58900),
        safe: Color(0xFF1E8E4E),
        dangerContainer: Color(0xFFFFEDEA),
        warningContainer: Color(0xFFFFF3E0),
        watchContainer: Color(0xFFFFF9E0),
        safeContainer: Color(0xFFE6F5EB),
        neutralContainer: Color(0xFFEFEFE4),
      );
}

/// 统一圆角。
class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 26;
}

/// 构建 App 主题。
ThemeData buildAppTheme({required Brightness brightness}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2F6BFF),
    brightness: brightness,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  final appColors = AppColors(
    brightness: brightness,
    danger: isDark ? const Color(0xFFFF8A80) : const Color(0xFFD64541),
    warning: isDark ? const Color(0xFFFFC46B) : const Color(0xFFD98114),
    watch: isDark ? const Color(0xFFFFE08A) : const Color(0xFFB58900),
    safe: isDark ? const Color(0xFF7BD8A2) : const Color(0xFF1E8E4E),
    dangerContainer: isDark ? const Color(0xFF3B2220) : const Color(0xFFFFEDEA),
    warningContainer: isDark ? const Color(0xFF3A2C18) : const Color(0xFFFFF3E0),
    watchContainer: isDark ? const Color(0xFF383113) : const Color(0xFFFFF9E0),
    safeContainer: isDark ? const Color(0xFF17301F) : const Color(0xFFE6F5EB),
    neutralContainer: scheme.surfaceContainerHighest,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    extensions: [appColors],
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    splashColor: scheme.primary.withValues(alpha: 0.08),
    highlightColor: scheme.primary.withValues(alpha: 0.04),

    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: const TextStyle(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 3,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 68,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
