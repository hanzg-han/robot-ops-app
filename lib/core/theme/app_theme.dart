import 'package:flutter/material.dart';

/// 视觉规范（PRD §7.2）。
///
/// 主色 #1F4E79（项目统一色）；语义色与卡片样式按 PRD 固定，避免各页面自行发挥。
class AppColors {
  const AppColors._();

  static const Color primary = Color(0xFF1F4E79);
  static const Color primary2 = Color(0xFF2E75B6);

  // 语义色
  static const Color success = Color(0xFF0F766E);
  static const Color warning = Color(0xFFB45309);
  static const Color error = Color(0xFFB91C1C);
  static const Color info = Color(0xFF0369A1);
  static const Color neutral = Color(0xFF64748B);

  // 背景与线
  static const Color bg = Color(0xFFF6F8FB);
  static const Color line = Color(0xFFD6DEE7);

  // 地图栅格（PRD §7.2 / 开发文档 §13.2）
  static const Color gridPassable = Color(0xFFFFFFFF);
  static const Color gridUnexplored = Color(0xFFEEF1F5);
  static const Color gridObstacle = Color(0xFF3A4652);
  static const Color gridUnknown = Color(0xFF8D98A4);

  // 地图要素（PRD §5.3 绘制顺序配色）
  static const Color laser = Color(0xFF0891B2);
  static const Color trail = Color(0xFFF97316);
  static const Color route = Color(0xFF2563EB);
  static const Color navTarget = Color(0xFF1E3A8A);
  static const Color patrolRoute = Color(0xFFD97706);
  static const Color patrolSegment = Color(0xFFEA580C);
  static const Color poi = Color(0xFF7C3AED);
  static const Color dock = Color(0xFFE11D48);
  static const Color wall = Color(0xFFDC2626);
  static const Color track = Color(0xFF0D9488);
  static const Color robot = Color(0xFF16A34A);

  /// 定位质量三档颜色（FR-DASH-05：≥70 绿 / 40–69 橙 / <40 红）
  static Color qualityColor(num? quality) {
    if (quality == null) return neutral;
    if (quality >= 70) return success;
    if (quality >= 40) return warning;
    return error;
  }

  /// 电量颜色（<25% 红、<60% 橙、其余绿）
  static Color batteryColor(num? battery, {int threshold = 25}) {
    if (battery == null) return neutral;
    if (battery < threshold) return error;
    if (battery < 60) return warning;
    return success;
  }
}

/// 语义色分级（用于徽标/横幅）
enum Severity { info, warning, error, success, neutral }

extension SeverityColor on Severity {
  Color get color {
    switch (this) {
      case Severity.error:
        return AppColors.error;
      case Severity.warning:
        return AppColors.warning;
      case Severity.info:
        return AppColors.info;
      case Severity.success:
        return AppColors.success;
      case Severity.neutral:
        return AppColors.neutral;
    }
  }

  IconData get icon {
    switch (this) {
      case Severity.error:
        return Icons.error_outline;
      case Severity.warning:
        return Icons.warning_amber_outlined;
      case Severity.info:
        return Icons.info_outline;
      case Severity.success:
        return Icons.check_circle_outline;
      case Severity.neutral:
        return Icons.remove_circle_outline;
    }
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary)
        .copyWith(surface: Colors.white, error: AppColors.error);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      fontFamily: null, // 使用系统中文字体（PingFang SC / Microsoft YaHei）
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // 主要按钮高度 ≥48dp（PRD §7.2）
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.primary),
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary2, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF334155),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      // 危险操作按钮：红底白字（PRD §7.2）
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
    );
  }

  /// 危险按钮样式（回充以外的移动类、终止等）
  static ButtonStyle dangerButton() => FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  /// 禁用态：灰底 + 原因文案（原因不可省，PRD §7.2）
  static ButtonStyle disabledButton() => FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: const Color(0xFFE2E8F0),
        foregroundColor: AppColors.neutral,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
}
