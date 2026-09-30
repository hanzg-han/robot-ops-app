import 'dart:math' as math;

/// 数值与角度格式化（PRD §9.2 单位与精度约定）。
class NumFmt {
  const NumFmt._();

  /// 坐标：米，3 位小数（PRD §9.1）
  static String coord(double? v) =>
      v == null || v.isNaN || v.isInfinite ? '—' : v.toStringAsFixed(3);

  /// 通用保留 3 位（调试台的 num()）
  static String trim3(num? v) {
    if (v == null) return '—';
    final d = v.toDouble();
    if (d.isNaN || d.isInfinite) return '—';
    return (d * 1000).round() / 1000 == d
        ? _stripZeros(d.toStringAsFixed(3))
        : (d).toStringAsFixed(3);
  }

  static String _stripZeros(String s) =>
      s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;

  /// 弧度 → 角度（PRD §9.1：主显角度保留 1 位）
  static double rad2deg(double? rad) =>
      rad == null || rad.isNaN ? double.nan : rad * 180 / math.pi;

  /// 角度 → 弧度（界面用「度」，内部用弧度，D6 决策）
  static double deg2rad(double deg) => deg * math.pi / 180;

  /// 角度展示：保留 1 位小数 + °
  static String angleDeg(double? rad) {
    final deg = rad2deg(rad);
    if (deg.isNaN || deg.isInfinite) return '—';
    return '${deg.toStringAsFixed(1)}°';
  }

  /// 弧度展示：保留 3 位
  static String angleRad(double? rad) {
    if (rad == null || rad.isNaN || rad.isInfinite) return '—';
    return '${rad.toStringAsFixed(3)} rad';
  }

  /// 距离（PRD §9.2）：<1000 m 显示米（1 位）；≥1000 m 显示千米（2 位）
  static String distance(double? meters) {
    if (meters == null || meters.isNaN || meters.isInfinite) return '—';
    final m = meters.abs();
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.toStringAsFixed(1)} m';
  }

  /// 累计里程（PRD §9.1：>1000m 转 km，保留 3 位）
  static String odometry(double? meters) {
    if (meters == null || meters.isNaN || meters.isInfinite) return '—';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(3)} km';
    return '${meters.toStringAsFixed(3)} m';
  }

  /// 耗时（PRD §9.2）：<1s 显示 ms；≥1s 显示秒（1 位）
  static String duration(int? ms) {
    if (ms == null) return '—';
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  /// 秒数展示（停留倒计时等）：整数秒
  static String seconds(num seconds) {
    final s = seconds.round();
    if (s < 60) return '$s 秒';
    final m = s ~/ 60;
    final rest = s % 60;
    return '$m 分 $rest 秒';
  }

  /// 电量：整数 + %（PRD §9.1：保留 0 位小数；缺失显示 —，不显示 0）
  static String battery(num? v) {
    if (v == null) return '—';
    return '${v.round()}%';
  }

  /// 速度：保留 3 位（FR-MOT-07）
  static String speed(double? v) => coord(v);

  /// 两点直线距离
  static double lineDistance(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// 路径总长度（点数：相邻点累加）
  static double pathLength(List<List<double>> points) {
    if (points.length < 2) return 0;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += lineDistance(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1]);
    }
    return total;
  }
}

/// 角度规范化到 (-180, 180]
double normalizeDeg(double deg) {
  var d = deg % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// 弧度规范化到 (-pi, pi]
double normalizeRad(double rad) {
  var r = rad % (2 * math.pi);
  if (r > math.pi) r -= 2 * math.pi;
  if (r <= -math.pi) r += 2 * math.pi;
  return r;
}
