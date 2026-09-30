import 'dart:math' as math;

import '../../core/config/app_config.dart';

/// 巡逻点（FR-PAT-01：名称,x,y[,yaw]）
class PatrolPoint {
  PatrolPoint({
    required this.name,
    required this.x,
    required this.y,
    this.yaw,
  });

  String name;
  double x;
  double y;

  /// 到点定向（弧度，可选）。PRD §5.6：到点定向 = 使用点 yaw
  double? yaw;

  PatrolPoint copy() => PatrolPoint(name: name, x: x, y: y, yaw: yaw);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'x': x,
        'y': y,
        if (yaw != null) 'yaw': yaw,
      };

  static PatrolPoint fromJson(Map<String, dynamic> json) => PatrolPoint(
        name: (json['name'] ?? '') as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        yaw: json['yaw'] == null ? null : (json['yaw'] as num).toDouble(),
      );

  /// 一行文本（导出/粘贴格式）
  String toLine() {
    final base = '$name,${x.toStringAsFixed(3)},${y.toStringAsFixed(3)}';
    return yaw == null ? base : '$base,${yaw!.toStringAsFixed(4)}';
  }
}

/// 批量粘贴解析结果（FR-PAT-02）
class PatrolParseResult {
  PatrolParseResult({required this.points, required this.errors});

  final List<PatrolPoint> points;

  /// 具体行号 + 原文的错误提示
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// 巡逻参数（FR-PAT-03）
class PatrolParams {
  PatrolParams({
    this.loops = 1,
    this.dwellMs = AppConfig.defaultPatrolDwellMs,
    this.speedRatio = AppConfig.defaultPatrolSpeedRatio,
    this.usePointYaw = true,
    this.pointTimeoutMs = AppConfig.defaultPatrolPointTimeoutMs,
  });

  /// 圈数，0 = 无限（护栏 [AppConfig.patrolLoopGuard]）
  int loops;

  /// 点间停留（ms）
  int dwellMs;

  /// 速度比例 0.1–1.0
  double speedRatio;

  /// 到点定向模式：true = 使用点 yaw，false = 不旋转
  bool usePointYaw;

  /// 单点超时（ms，FR-PAT-08）
  int pointTimeoutMs;

  /// 预计总时长估算（FR-PAT-04 确认弹窗：路径摘要 + 预计时长）
  ///
  /// 用「点数 ×（假设每段移动 30s + 停留）」粗略估算，仅用于弹窗提示。
  Duration estimate(int pointCount) {
    final loopsEffective =
        loops == 0 ? AppConfig.patrolLoopGuard : math.min(loops, AppConfig.patrolLoopGuard);
    if (pointCount < 2) return Duration.zero;
    final perPointMs = (30000 + dwellMs) * pointCount;
    final totalMs = perPointMs * loopsEffective;
    return Duration(milliseconds: totalMs);
  }
}

/// 巡逻状态机（开发文档 §14.2）。
///
/// 状态：idle → running → (stopping) → done / aborted
///
/// 本类为**纯逻辑**（不接触网络），网络下发由 PatrolController 驱动；
/// 便于单元测试覆盖顺序、圈数、无限护栏与异常中断分支。
class PatrolEngine {
  PatrolEngine({List<PatrolPoint>? points, PatrolParams? params})
      : points = points ?? <PatrolPoint>[],
        params = params ?? PatrolParams();

  final List<PatrolPoint> points;
  final PatrolParams params;

  PatrolRunState state = PatrolRunState.idle;

  /// 当前圈（从 1 开始）
  int currentLoop = 0;

  /// 当前点索引（0 基）
  int currentIndex = 0;

  /// 本次巡逻已完成的目标下发次数（用于进度显示）
  int completedPoints = 0;

  /// 停止原因（异常中断时写入，供 UI 与日志展示）
  String? stopReason;

  /// 失败点信息（FR-PAT-09）
  int? failedIndex;
  String? failedName;

  bool get isRunning => state == PatrolRunState.running;
  bool get isStopping => state == PatrolRunState.stopping;

  /// 有效总圈数（0 = 无限 → 护栏值）
  int get effectiveLoops =>
      params.loops == 0 ? AppConfig.patrolLoopGuard : params.loops;

  /// 是否可开始巡逻（FR-PAT-01：至少 2 个点才能开始）
  bool get canStart => points.length >= 2 && state == PatrolRunState.idle;

  /// 校验巡逻点（返回第一条错误；无错误返回 null）
  String? validate() {
    if (points.length < 2) {
      return '至少需要 2 个巡逻点才能开始巡逻（当前 ${points.length} 个）';
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (!p.x.isFinite || !p.y.isFinite) {
        return '第 ${i + 1} 点（${p.name.isEmpty ? '未命名' : p.name}）坐标非法';
      }
      final span = 500.0;
      if (p.x.abs() > span || p.y.abs() > span) {
        return '第 ${i + 1} 点（${p.name.isEmpty ? '未命名' : p.name}）坐标超出合理范围（±${span.toStringAsFixed(0)} m）';
      }
    }
    return null;
  }

  /// 开始巡逻。已运行时返回 false（防重复开始）。
  bool start() {
    if (!canStart) return false;
    state = PatrolRunState.running;
    currentLoop = 0;
    currentIndex = 0;
    completedPoints = 0;
    stopReason = null;
    failedIndex = null;
    failedName = null;
    return true;
  }

  /// 进入下一圈。返回 false 表示已跑完所有圈。
  bool nextLoop() {
    if (currentLoop >= effectiveLoops) return false;
    currentLoop++;
    currentIndex = 0;
    return true;
  }

  /// 前进一步（下一点）。返回 null 表示本圈结束。
  ///
  /// 调用方（控制器）在收到行为结束回调后调用本方法推进状态机。
  PatrolStep? advance() {
    if (state != PatrolRunState.running) return null;
    if (points.isEmpty) return null;

    // 首次进入：currentLoop 为 0，先补一圈
    if (currentLoop == 0) {
      if (!nextLoop()) return null;
    }

    if (currentIndex >= points.length) {
      // 本圈结束，进入下一圈
      if (!nextLoop()) {
        state = PatrolRunState.done;
        return null;
      }
    }

    final point = points[currentIndex];
    final step = PatrolStep(
      loop: currentLoop,
      index: currentIndex,
      totalLoops: params.loops,
      point: point,
      isLastPointOfLoop: currentIndex == points.length - 1,
      isLastLoop: currentLoop == effectiveLoops,
    );
    currentIndex++;
    return step;
  }

  /// 标记当前点已完成（行为成功结束）
  void markPointDone() => completedPoints++;

  /// 请求停止（用户点停止 / 异常中断）
  void requestStop({String? reason}) {
    if (state == PatrolRunState.idle) return;
    state = PatrolRunState.stopping;
    stopReason = reason;
  }

  /// 确认已停止（DELETE 下发完成后调用）
  void confirmStopped({bool abnormal = false}) {
    state = abnormal ? PatrolRunState.aborted : PatrolRunState.done;
  }

  /// 异常中断（FR-PAT-09：任一巡逻点下发失败 → 停止巡逻并保留已完成进度）
  void failAt(int index, String name, String reason) {
    failedIndex = index;
    failedName = name;
    stopReason = reason;
    state = PatrolRunState.aborted;
  }

  void reset() {
    state = PatrolRunState.idle;
    currentLoop = 0;
    currentIndex = 0;
    completedPoints = 0;
    stopReason = null;
    failedIndex = null;
    failedName = null;
  }

  /// 进度百分比（0–1）。无限模式按当前圈内进度展示。
  double get progress {
    final total = points.length * effectiveLoops;
    if (total <= 0) return 0;
    if (params.loops == 0) {
      // 无限模式：无总进度，显示当前圈进度
      return points.isEmpty ? 0 : (completedPoints % points.length) / points.length;
    }
    return (completedPoints / total).clamp(0.0, 1.0);
  }

  /// 剩余点数（FR-PAT-05）
  int get remainingPoints {
    final total = points.length * effectiveLoops;
    return math.max(0, total - completedPoints);
  }

  /// 状态文本（如「巡逻中 2/3 圈」）
  String get statusLabel {
    switch (state) {
      case PatrolRunState.idle:
        return '待开始';
      case PatrolRunState.running:
        return params.loops == 0
            ? '巡逻中 第 $currentLoop 圈（无限）'
            : '巡逻中 $currentLoop/${params.loops} 圈';
      case PatrolRunState.stopping:
        return '正在停止…';
      case PatrolRunState.done:
        return '已结束';
      case PatrolRunState.aborted:
        return '已中断${stopReason == null ? '' : '：$stopReason'}';
    }
  }
}

enum PatrolRunState { idle, running, stopping, done, aborted }

/// 单步巡逻指令
class PatrolStep {
  PatrolStep({
    required this.loop,
    required this.index,
    required this.totalLoops,
    required this.point,
    required this.isLastPointOfLoop,
    required this.isLastLoop,
  });

  final int loop;
  final int index;

  /// 0 表示无限
  final int totalLoops;

  final PatrolPoint point;
  final bool isLastPointOfLoop;
  final bool isLastLoop;

  String get loopLabel => totalLoops == 0 ? '第 $loop 圈' : '第 $loop/$totalLoops 圈';

  String get label => '$loopLabel 第 ${index + 1} 点（${point.name}）';
}

/// 巡逻点文本批量解析（FR-PAT-02）
///
/// 格式：每行 `名称,x,y[,yaw]`；`#` 开头与空行忽略；
/// 解析失败提示**具体行号与原文**。
class PatrolTextParser {
  const PatrolTextParser._();

  static PatrolParseResult parse(String text) {
    final points = <PatrolPoint>[];
    final errors = <String>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();
      final lineNo = i + 1;

      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;

      final parts = line.split(',').map((s) => s.trim()).toList();
      if (parts.length < 3) {
        errors.add('第 $lineNo 行：字段不足（需要「名称,x,y[,yaw]」）→ $raw');
        continue;
      }

      final name = parts[0];
      final x = double.tryParse(parts[1]);
      final y = double.tryParse(parts[2]);
      if (x == null) {
        errors.add('第 $lineNo 行：x 不是数字「${parts[1]}」→ $raw');
        continue;
      }
      if (y == null) {
        errors.add('第 $lineNo 行：y 不是数字「${parts[2]}」→ $raw');
        continue;
      }

      double? yaw;
      if (parts.length >= 4 && parts[3].isNotEmpty) {
        yaw = double.tryParse(parts[3]);
        if (yaw == null) {
          errors.add('第 $lineNo 行：yaw 不是数字「${parts[3]}」→ $raw');
          continue;
        }
      }

      points.add(PatrolPoint(
        name: name.isEmpty ? '点 ${points.length + 1}' : name,
        x: x,
        y: y,
        yaw: yaw,
      ));
    }

    return PatrolParseResult(points: points, errors: errors);
  }
}
