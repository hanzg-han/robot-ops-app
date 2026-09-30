/// 时间格式化与「机器运行毫秒 → 本地时间」换算（FR-EVT-02 / 开发文档 §15.1）。
class TimeFmt {
  const TimeFmt._();

  /// 本地时钟 HH:mm:ss
  static String hms(DateTime t) =>
      '${_2(t.hour)}:${_2(t.minute)}:${_2(t.second)}';

  /// 本地时钟 HH:mm:ss.SSS（日志用）
  static String hmsMs(DateTime t) =>
      '${_2(t.hour)}:${_2(t.minute)}:${_2(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

  /// 完整时间戳（日志导出用）
  static String full(DateTime t) =>
      '${t.year}-${_2(t.month)}-${_2(t.day)} ${hms(t)}';

  /// 「X 秒前」相对时间（FR-DASH-10：>10s 灰显）
  static String ago(DateTime? t, {DateTime? now}) {
    if (t == null) return '从未更新';
    final n = now ?? DateTime.now();
    final diff = n.difference(t);
    if (diff.inSeconds < 1) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${diff.inHours} 小时前';
  }

  /// 机器运行毫秒 → 时长文本，如「运行 01:23:45」
  static String uptime(double? machineMs) {
    if (machineMs == null || machineMs.isNaN || machineMs <= 0) return '—';
    final total = (machineMs / 1000).floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return '运行 ${_2(h)}:${_2(m)}:${_2(s)}';
  }

  /// 事件时间换算（FR-EVT-02）：
  /// 事件 timestamp 为「机器运行毫秒」，用当前机器运行毫秒作为基准反推墙钟时间。
  /// 基准缺失时返回 null，由调用方退化为「运行+HH:MM:SS」。
  static DateTime? eventWallClock({
    required double eventTimestampMs,
    required double? machineTimestampMs,
    required DateTime? sampledAt,
  }) {
    if (machineTimestampMs == null || sampledAt == null) return null;
    if (machineTimestampMs.isNaN || eventTimestampMs.isNaN) return null;
    final deltaMs = machineTimestampMs - eventTimestampMs;
    return sampledAt.subtract(Duration(milliseconds: deltaMs.round()));
  }

  /// 事件展示文本：优先本地时间，基准缺失时退化（FR-EVT-02）
  static String eventTime({
    required double eventTimestampMs,
    required double? machineTimestampMs,
    required DateTime? sampledAt,
  }) {
    final wall = eventWallClock(
      eventTimestampMs: eventTimestampMs,
      machineTimestampMs: machineTimestampMs,
      sampledAt: sampledAt,
    );
    if (wall != null) return hms(wall);
    return uptime(eventTimestampMs);
  }

  /// 停留倒计时文本
  static String countdown(num secondsRemaining) {
    final s = secondsRemaining.ceil();
    if (s <= 0) return '0 秒';
    return '$s 秒';
  }

  /// 预计时长（巡逻确认弹窗用）：秒 → 「约 N 分钟」
  static String estimate(Duration d) {
    final minutes = d.inMinutes;
    if (minutes < 1) return '约 ${d.inSeconds} 秒';
    if (minutes < 60) return '约 $minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '约 $h 小时' : '约 $h 小时 $m 分钟';
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';
}
