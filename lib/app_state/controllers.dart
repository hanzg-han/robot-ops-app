import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_result.dart';
import '../core/network/request_log.dart';
import '../data/dto/models.dart';
import '../data/repositories/repositories.dart';
import '../domain/models/event_catalog.dart';
import '../domain/services/event_dedupe.dart';
import '../domain/services/patrol_engine.dart';
import 'robot_state.dart';
import 'services.dart';
/// 一次导航/巡逻目标的路线与终点（开发文档 §14.1「showRouteTo」）。
class RouteTarget {
  RouteTarget({
    required this.name,
    required this.x,
    required this.y,
    this.points = const <List<double>>[],
    this.reachable = true,
    this.message,
  });

  final String name;
  final double x;
  final double y;

  /// 规划路径点（空表示搜路失败或未规划）
  List<List<double>> points;

  /// 搜路是否成功（失败仍需保留终点标记，FR-NAV-04）
  bool reachable;

  /// 失败提示（如「该目标当前不可达或已被占据」）
  String? message;

  double get lengthMeters {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final dx = points[i][0] - points[i - 1][0];
      final dy = points[i][1] - points[i - 1][1];
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  String get coordinateLabel =>
      'x ${x.toStringAsFixed(3)}, y ${y.toStringAsFixed(3)}';
}

/// 移动类操作的统一门控（FR-SAFE-01 / FR-MOT-05 / FR-RC-07）。
///
/// 约定：
/// - 所有会移动机器人的操作**必须**先经 UI 二次确认，本控制器只负责
///   地址/门控校验与下发，绝不自行确认；
/// - 终止类操作**不加摩擦**（一次点击直达，无需二次确认）；
/// - 遥控激活期间，其余移动入口全部置灰（双向互斥）。
class ActionGate extends ChangeNotifier {
  ActionGate(this.services);

  final AppServices services;

  /// 连点保护（PRD §10.1 边界 6）：下发后禁用至行为结束或用户显式终止
  DateTime? _lastDispatchAt;
  bool _dispatching = false;

  bool get isDispatching => _dispatching;

  /// 遥控是否激活（互斥用）
  bool remoteControlActive = false;

  /// 巡逻是否运行中（互斥用）
  bool patrolRunning = false;

  /// 某移动入口是否被禁用，并给出原因（禁止「先报错后解释」，FR-SAFE-06）
  String? blockReason({required bool needsDock}) {
    final s = services.state;
    if (remoteControlActive) return '遥控进行中';
    if (!s.isConnected) return '未连接底盘';
    if (!s.localizationOk) return '定位未开启';
    if (needsDock && !s.hasDock) return '未设置充电桩位置';
    return null;
  }


  bool canDispatch({required bool needsDock}) => blockReason(needsDock: needsDock) == null;

  /// 下发导航（移动级）。调用方必须先完成二次确认。
  Future<DispatchResult> dispatchMoveTo({
    required String targetName,
    required double x,
    required double y,
    double? yawRad,
    int? mode,
    double? speedRatio,
  }) async {
    final reason = blockReason(needsDock: false);
    if (reason != null) {
      return DispatchResult.failure('$reason，已阻止下发。');
    }
    return _dispatch(
      label: '导航到「$targetName」',
      action: () => services.motion.moveTo(
        x: x,
        y: y,
        yawRad: yawRad,
        mode: mode,
        speedRatio: speedRatio,
      ),
    );
  }

  /// 下发原地旋转（移动级）
  Future<DispatchResult> dispatchRotate(double angleRad) async {
    final reason = blockReason(needsDock: false);
    if (reason != null) {
      return DispatchResult.failure('$reason，已阻止下发。');
    }
    final deg = angleRad * 180 / 3.141592653589793;
    return _dispatch(
      label: '原地旋转 ${deg.toStringAsFixed(1)}°',
      action: () => services.motion.rotateTo(angleRad),
    );
  }

  /// 下发回充（移动级）
  Future<DispatchResult> dispatchGoHome({
    required String flags,
    required bool backToLanding,
    required int retryCount,
    required int mode,
  }) async {
    final reason = blockReason(needsDock: true);
    if (reason != null) {
      return DispatchResult.failure('$reason，已阻止下发。');
    }
    return _dispatch(
      label: '回充',
      action: () => services.motion.goHome(
        flags: flags,
        backToLanding: backToLanding,
        retryCount: retryCount,
        mode: mode,
      ),
    );
  }

  /// 内部统一下发：写日志、标记「已下发」、触发行为条前台化（FR-SAFE-03）
  Future<DispatchResult> _dispatch({
    required String label,
    required Future<ApiResult<dynamic>> Function() action,
  }) async {
    _dispatching = true;
    notifyListeners();
    try {
      final res = await action();
      if (!res.ok) {
        final msg = res.error ?? '下发失败：底盘返回 HTTP ${res.status}';
        services.log.note('$label 下发失败：$msg');
        return DispatchResult.failure(msg);
      }

      final id = res.data is Map ? (res.data as Map)['action_id'] : null;
      services.log.note('已下发 $label${id == null ? '' : '，action_id=$id'}');
      _lastDispatchAt = DateTime.now();
      // 立即前台化：不等下一轮 2s 轮询（3s 内必须出现）
      services.state.markDispatched();
      await services.state.refreshNow();
      return DispatchResult.success(
        message: '$label 已下发',
        actionId: id,
      );
    } finally {
      _dispatching = false;
      notifyListeners();
    }
  }

  /// 终止当前行为（急停：一次点击，无二次确认）
  Future<AbortOutcome> abort() async {
    services.log.note('请求终止当前行为');
    final outcome = await services.state.abortCurrentAction();
    return outcome;
  }

  DateTime? get lastDispatchAt => _lastDispatchAt;
}

class DispatchResult {
  DispatchResult._({required this.ok, required this.message, this.actionId});

  factory DispatchResult.success({required String message, Object? actionId}) =>
      DispatchResult._(ok: true, message: message, actionId: actionId);

  factory DispatchResult.failure(String message) =>
      DispatchResult._(ok: false, message: message);

  final bool ok;
  final String message;
  final Object? actionId;
}

/// 导航与选点（FR-NAV-01~09 / 开发文档 §14.1）。
///
/// 核心约束：**凡涉及目标的入口，都必须走同一个 [showRouteTo]**，
/// 避免出现「点了导航但地图不画线」。
class NavigationController extends ChangeNotifier {
  NavigationController(this.services);

  final AppServices services;

  final RequestLogBuffer get log => services.log;

  List<Poi> get pois => services.state.pois;

  /// 当前导航目标（FR-NAV-08：地图页顶部常驻提示）
  RouteTarget? target;

  /// 最近一次规划结果提示（「路径 N 点 / 长度 m」）
  String? lastPlanSummary;

  /// 搜路失败但保留终点的提示
  String? lastPlanWarning;

  /// 统一目标入口（FR-NAV-06）：地图选点 / POI 列表 / 巡逻点 / 坐标输入
  /// 全部经此方法规划并在图上画路线。
  Future<RouteTarget> showRouteTo(String name, double x, double y) async {
    final t = RouteTarget(name: name, x: x, y: y);
    target = t;
    lastPlanWarning = null;
    notifyListeners();

    final res = await services.motion.searchPath(x: x, y: y);
    if (res.ok) {
      t.points = res.data ?? <List<double>>[];
      t.reachable = true;
      lastPlanSummary =
          '路径 ${t.points.length} 点 / ${t.lengthMeters.toStringAsFixed(1)} m';
      log.note('已在地图上标出到「$name」的路线：${t.points.length} 个路径点');
    } else {
      t.points = <List<double>>[];
      t.reachable = false;
      // 搜路失败仍保留终点标记（FR-NAV-04 / 开发文档 §14.1）
      lastPlanWarning = res.status == 500
          ? '该目标当前不可达或已被占用，仅显示终点。可稍后重试，或选择附近其他点位。'
          : (res.error ?? '路径规划失败，仅显示终点。');
      lastPlanSummary = null;
      log.note('「$name」路线规划失败（HTTP ${res.status}），仅标出终点');
    }
    notifyListeners();
    return t;
  }

  /// 规划路径（不移动，无需二次确认）
  Future<RouteTarget> planOnly(double x, double y, {String? name}) =>
      showRouteTo(name ?? '自定义坐标', x, y);

  /// 导航到当前目标（已经过 UI 二次确认）
  Future<DispatchResult> navigateToTarget(ActionGate gate) async {
    final t = target;
    if (t == null) {
      return DispatchResult.failure('未选择导航目标。');
    }
    final res = await gate.dispatchMoveTo(targetName: t.name, x: t.x, y: t.y);
    if (res.ok) {
      await services.state.refreshNow();
    }
    notifyListeners();
    return res;
  }

  /// 导航到指定 POI/坐标（先画路线，再下发）—— 所有入口的唯一实现
  Future<DispatchResult> navigateTo(
    ActionGate gate,
    String name,
    double x,
    double y,
  ) async {
    await showRouteTo(name, x, y);
    return navigateToTarget(gate);
  }

  /// 导航到达/终止后清理提示与路线（FR-NAV-08）
  void clearTarget() {
    target = null;
    lastPlanSummary = null;
    lastPlanWarning = null;
    notifyListeners();
  }

  /// POI 与机器人直线距离（FR-NAV-02）
  double? distanceTo(Poi poi) {
    final pose = services.state.pose;
    if (pose == null) return null;
    final dx = poi.pose.x - pose.x;
    final dy = poi.pose.y - pose.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// POI 搜索 + 排序（FR-NAV-01）
  List<Poi> search(String keyword, {bool byName = true, bool byDistance = false}) {
    var list = List<Poi>.from(pois);
    final k = keyword.trim().toLowerCase();
    if (k.isNotEmpty) {
      list = list
          .where((p) =>
              p.displayName.toLowerCase().contains(k) ||
              p.id.toLowerCase().contains(k) ||
              (p.type ?? '').toLowerCase().contains(k))
          .toList();
    }
    if (byDistance) {
      final withDist = list
          .map((p) => MapEntry(p, distanceTo(p) ?? double.infinity))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      list = withDist.map((e) => e.key).toList();
    } else if (byName) {
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
    }
    return list;
  }

  /// 按楼层分组（PRD §14.3：首段为楼层）
  Map<String, List<Poi>> groupedByFloor() {
    final map = <String, List<Poi>>{};
    for (final p in pois) {
      map.putIfAbsent(p.floorGroup, () => <Poi>[]).add(p);
    }
    return map;
  }
}

/// 事件与告警（FR-EVT-01~09）。
class EventsController extends ChangeNotifier {
  EventsController(this.services);

  final AppServices services;
  final EventDedupe dedupe = EventDedupe(capacity: AppConfig.defaultEventCapacity);

  double? machineTimestampMs;
  DateTime? machineTimestampAt;

  /// 级别筛选（空 = 全部）
  Set<EventLevel> levelFilter = <EventLevel>{};

  /// 新事件横幅（FR-EVT-05；同时多条时合并）
  String? bannerText;

  Timer? _timer;
  bool _polling = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: AppConfig.defaultPollIntervalMs),
      (_) => unawaited(pollOnce()),
    );
    unawaited(pollOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final tsRes = await services.eventsRepo.machineTimestamp();
      if (tsRes.ok && tsRes.data != null) {
        machineTimestampMs = tsRes.data;
        machineTimestampAt = DateTime.now();
      }
      final res = await services.eventsRepo.events();
      if (res.ok) {
        final fresh = dedupe.merge(res.data);
        if (fresh.isNotEmpty) {
          _onNewEvents(fresh);
        }
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  void _onNewEvents(List<RobotEvent> fresh) {
    // 只对错误/警告弹横幅（FR-EVT-05）；同类重复已由去重键保证不重复
    final notable = fresh
        .where((e) => e.level == EventLevel.error || e.level == EventLevel.warning)
        .toList();
    if (notable.isEmpty) return;
    services.log.note('新事件 ${fresh.length} 条（其中告警 ${notable.length} 条）');
    bannerText = notable.length == 1
        ? '${notable.first.level.label}：${notable.first.description}'
        : '${notable.length} 条新告警';
  }

  void dismissBanner() {
    bannerText = null;
    notifyListeners();
  }

  List<RobotEvent> get visibleEvents => dedupe.filterByLevels(levelFilter);

  void setFilter(Set<EventLevel> levels) {
    levelFilter = levels;
    notifyListeners();
  }

  void markAllRead() {
    dedupe.markAllRead();
    notifyListeners();
  }

  void clearRead() {
    dedupe.clearRead();
    notifyListeners();
  }

  /// 事件时间展示（FR-EVT-02：机器毫秒 → 本地时间；基准缺失退化为「运行 HH:MM:SS」）
  String timeLabel(RobotEvent e) {
    final wall = TimeFmtHelper.eventTime(
      eventTimestampMs: e.timestamp,
      machineTimestampMs: machineTimestampMs,
      sampledAt: machineTimestampAt,
    );
    return wall;
  }
}

/// 时间换算辅助（避免 UI 层直接依赖 core/utils）
class TimeFmtHelper {
  const TimeFmtHelper._();

  static String eventTime({
    required double eventTimestampMs,
    required double? machineTimestampMs,
    required DateTime? sampledAt,
  }) {
    if (machineTimestampMs == null || sampledAt == null) {
      return _uptime(eventTimestampMs);
    }
    final deltaMs = machineTimestampMs - eventTimestampMs;
    final wall = sampledAt.subtract(Duration(milliseconds: deltaMs.round()));
    return _hms(wall);
  }

  static String _hms(DateTime t) =>
      '${_2(t.hour)}:${_2(t.minute)}:${_2(t.second)}';

  static String _uptime(double ms) {
    if (ms.isNaN || ms <= 0) return '—';
    final total = (ms / 1000).floor();
    return '运行 ${_2(total ~/ 3600)}:${_2((total % 3600) ~/ 60)}:${_2(total % 60)}';
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';
}

/// 巡逻控制器：驱动 [PatrolEngine] 与网络下发（开发文档 §14.2）。
///
/// 关键点：
/// - 等待/停留期间**继续轮询**（由 RobotState 保证，不冻结 UI）；
/// - 串行下发：下一目标必须等上一行为结束（Q5，PRD §14.2）；
/// - 单点超时（默认 10 分钟）按「未到达」处理并终止；
/// - 停止 = 终止行为 + 停状态机 + 清标记（FR-PAT-07 / FR-SAFE-04）。
class PatrolController extends ChangeNotifier {
  PatrolController(this.services, this.gate);

  final AppServices services;
  final ActionGate gate;

  final List<PatrolPoint> points = <PatrolPoint>[];
  final PatrolParams params = PatrolParams();

  PatrolEngine engine = PatrolEngine();

  /// 当前巡逻段路径（地图显示）
  List<List<double>> currentSegmentPath = <List<double>>[];

  /// 整条巡逻路线（地图显示）
  List<List<double>> fullRoute = <List<double>>[];

  /// 下一目标（地图显示十字 + 标签）
  PatrolPoint? nextTarget;

  /// 停留倒计时剩余秒
  int dwellRemainingSec = 0;

  /// 单点已等待时长（用于超时判定）
  DateTime? _pointStartedAt;

  Timer? _dwellTimer;
  Timer? _pointTimeoutTimer;
  bool _advancing = false;
  bool _waitingAction = false;

  PatrolRunState get runState => engine.state;
  bool get isRunning => engine.isRunning || engine.isStopping;

  /// 巡逻点文本（编辑器）
  String pointsToText() => points.map((p) => p.toLine()).join('\n');

  void addPoint(PatrolPoint p) {
    points.add(p);
    _syncEngine();
  }

  void updatePoint(int index, PatrolPoint p) {
    if (index < 0 || index >= points.length) return;
    points[index] = p;
    _syncEngine();
  }

  void removePoint(int index) {
    if (index < 0 || index >= points.length) return;
    points.removeAt(index);
    _syncEngine();
  }

  void movePoint(int index, int delta) {
    final to = index + delta;
    if (index < 0 || index >= points.length) return;
    if (to < 0 || to >= points.length) return;
    final p = points.removeAt(index);
    points.insert(to, p);
    _syncEngine();
  }

  /// 追加全部 POI（FR-PAT-02：按楼层分组导入，避免跨楼层混入同一路线）
  int appendAllPois() {
    var added = 0;
    final grouped = <String, List<Poi>>{};
    for (final p in services.state.pois) {
      grouped.putIfAbsent(p.floorGroup, () => <Poi>[]).add(p);
    }
    final keys = grouped.keys.toList()..sort();
    for (final k in keys) {
      for (final poi in grouped[k]!) {
        points.add(PatrolPoint(
          name: poi.displayName,
          x: poi.pose.x,
          y: poi.pose.y,
          yaw: null,
        ));
        added++;
      }
    }
    _syncEngine();
    return added;
  }

  /// 文本批量粘贴导入（FR-PAT-02：失败提示具体行号）
  PatrolParseResult importText(String text) {
    final res = PatrolTextParser.parse(text);
    points.addAll(res.points);
    _syncEngine();
    return res;
  }

  void clearPoints() {
    points.clear();
    _syncEngine();
  }

  void _syncEngine() {
    engine = PatrolEngine(points: points, params: params);
    notifyListeners();
  }

  void updateParams({
    int? loops,
    int? dwellMs,
    double? speedRatio,
    bool? usePointYaw,
  }) {
    if (loops != null) params.loops = loops;
    if (dwellMs != null) params.dwellMs = dwellMs;
    if (speedRatio != null) params.speedRatio = speedRatio;
    if (usePointYaw != null) params.usePointYaw = usePointYaw;
    _syncEngine();
  }

  /// 校验（开始按钮的禁用原因，FR-SAFE-06）
  String? startBlockReason() {
    if (gate.remoteControlActive) return '遥控进行中';
    if (!services.state.isConnected) return '未连接底盘';
    if (!services.state.localizationOk) return '定位未开启';
    if (points.length < 2) return '至少需要 2 个巡逻点';
    return engine.validate();
  }

  bool get canStart => startBlockReason() == null;

  /// 路径摘要（FR-PAT-04 二次确认弹窗内容）
  String summary() {
    final loopsLabel = params.loops == 0 ? '无限圈' : '${params.loops} 圈';
    final dwellSec = (params.dwellMs / 1000).toStringAsFixed(0);
    final est = params.estimate(points.length);
    return '${points.length} 点 × $loopsLabel，每点停留 ${dwellSec}s，'
        '速度比例 ${params.speedRatio.toStringAsFixed(1)}'
        '${params.loops == 0 ? '' : '，预计${_estimateText(est)}'}';
  }

  static String _estimateText(Duration d) {
    final m = d.inMinutes;
    if (m < 60) return '约 $m 分钟';
    return '约 ${m ~/ 60} 小时 ${m % 60} 分钟';
  }

  /// 开始巡逻（调用方必须先完成二次确认）
  Future<void> start() async {
    if (!engine.start()) return;
    gate.patrolRunning = true;
    services.log.note('开始巡逻：${summary()}');
    await _buildFullRoute();
    _subscribeActionEnd();
    notifyListeners();
    await _nextStep();
  }

  void _subscribeActionEnd() {
    services.state.removeActionWatcher(_onActionEnd);
    services.state.addActionWatcher(_onActionEnd);
  }

  void _unsubscribeActionEnd() {
    services.state.removeActionWatcher(_onActionEnd);
  }

  /// 行为结束回调：推进状态机 / 处理失败与超时（FR-PAT-06/08/09）
  void _onActionEnd(ActionState? last, ActionState? current) {
    if (!engine.isRunning) return;
    if (!_waitingAction) return;
    _waitingAction = false;
    _pointTimeoutTimer?.cancel();
    _dwellTimer?.cancel();
    dwellRemainingSec = 0;

    final outcome = last?.outcome ?? ActionOutcome.success;
    if (outcome == ActionOutcome.failed) {
      final idx = engine.currentIndex == 0 ? 0 : engine.currentIndex - 1;
      final name = points.isNotEmpty && idx < points.length ? points[idx].name : '未知点';
      engine.failAt(idx, name, last?.reasonLabel ?? '导航失败');
      services.log.note('巡逻中断：第 ${idx + 1} 点（$name）不可达，巡逻已停止');
      unawaited(_finish(abnormal: true));
      return;
    }

    engine.markPointDone();

    // 停留倒计时（本圈最后一个点之后进入圈间停留）
    unawaited(_dwellThenNext());
  }

  Future<void> _dwellThenNext() async {
    if (!engine.isRunning) return;
    final dwell = params.dwellMs;
    if (dwell > 0) {
      dwellRemainingSec = (dwell / 1000).ceil();
      notifyListeners();
      _dwellTimer?.cancel();
      _dwellTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        dwellRemainingSec--;
        if (dwellRemainingSec <= 0) {
          t.cancel();
          unawaited(_nextStep());
        }
        notifyListeners();
      });
      return;
    }
    await _nextStep();
  }

  /// 下发下一个巡逻点（串行：等上一行为结束）
  Future<void> _nextStep() async {
    if (!engine.isRunning || _advancing) return;
    _advancing = true;
    try {
      final step = engine.advance();
      if (step == null) {
        // 全部圈跑完
        await _finish(abnormal: false);
        return;
      }

      nextTarget = step.point;
      notifyListeners();

      // 每个巡逻点都走同一 showRouteTo 逻辑（先画线，再下发）
      final nav = NavigationController(services);
      await nav.showRouteTo(step.point.name, step.point.x, step.point.y);
      currentSegmentPath = nav.target?.points ?? <List<double>>[];
      notifyListeners();

      final yawRad = params.usePointYaw ? step.point.yaw : null;
      final res = await services.motion.moveTo(
        x: step.point.x,
        y: step.point.y,
        yawRad: yawRad,
        speedRatio: params.speedRatio,
      );

      if (!res.ok) {
        engine.failAt(step.index, step.point.name, res.error ?? '下发失败');
        services.log.note('巡逻中断：第 ${step.index + 1} 点（${step.point.name}）下发失败');
        await _finish(abnormal: true);
        return;
      }

      final id = res.data is Map ? (res.data as Map)['action_id'] : null;
      services.log.note('巡逻下发 ${step.label}${id == null ? '' : '，action_id=$id'}');
      services.state.markDispatched();

      _waitingAction = true;
      _pointStartedAt = DateTime.now();

      // 单点超时（FR-PAT-08：默认 10 分钟，超时按「未到达」处理并终止）
      _pointTimeoutTimer?.cancel();
      _pointTimeoutTimer = Timer(Duration(milliseconds: params.pointTimeoutMs), () {
        if (!_waitingAction || !engine.isRunning) return;
        engine.failAt(step.index, step.point.name, '单点超时（未到达）');
        services.log.note('巡逻中断：第 ${step.index + 1} 点（${step.point.name}）超时未到达');
        unawaited(_finish(abnormal: true));
      });
    } finally {
      _advancing = false;
    }
  }

  /// 停止巡逻（FR-PAT-07 / FR-SAFE-04：终止行为 + 停状态机 + 清标记）
  Future<AbortOutcome> stop() async {
    final wasRunning = engine.isRunning;
    if (!wasRunning && engine.state != PatrolRunState.stopping) {
      return const AbortOutcome(
        kind: AbortKind.nothingToAbort,
        message: '当前没有正在执行的巡逻。',
      );
    }
    engine.requestStop(reason: '用户停止');
    notifyListeners();
    final outcome = await gate.abort();
    await _finish(abnormal: false, alreadyStopped: true);
    return outcome;
  }

  Future<void> _finish({required bool abnormal, bool alreadyStopped = false}) async {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    _pointTimeoutTimer?.cancel();
    _pointTimeoutTimer = null;
    _waitingAction = false;
    _unsubscribeActionEnd();

    if (!alreadyStopped) {
      engine.confirmStopped(abnormal: abnormal);
    }

    gate.patrolRunning = false;

    // 清理地图巡逻标记（停止后 ≤3s 内 UI 回到空闲态）
    nextTarget = null;
    currentSegmentPath = <List<double>>[];
    fullRoute = <List<double>>[];
    dwellRemainingSec = 0;

    final label = engine.state == PatrolRunState.aborted
        ? '巡逻已中断${engine.stopReason == null ? '' : '（${engine.stopReason}）'}'
        : '巡逻已结束';
    services.log.note(label);
    notifyListeners();
  }

  /// 构建整条巡逻路线（地图显示浅橙虚线 + 节点）
  Future<void> _buildFullRoute() async {
    final route = <List<double>>[];
    for (final p in points) {
      route.add(<double>[p.x, p.y]);
    }
    fullRoute = route;
    notifyListeners();
  }

  /// 巡逻进度文本（FR-PAT-05）
  String progressLabel() {
    if (!isRunning && engine.state == PatrolRunState.idle) return '待开始';
    final cur = engine.currentIndex;
    final total = points.length;
    final current = cur == 0 ? 1 : cur;
    final loopsLabel =
        params.loops == 0 ? '第 ${engine.currentLoop} 圈（无限）' : '${engine.currentLoop}/${params.loops} 圈';
    return '$loopsLabel · 第 $current/$total 点 · 剩余 ${engine.remainingPoints} 点';
  }
}

/// 手动遥控驾驶（FR-RC-01~15）—— 全 App 最危险的功能。
///
/// 安全约束（必须逐条实现，不得简化）：
/// - 进入时**一次性确认**（本次连接内有效），未确认时方向键完全禁用且不产生任何请求；
/// - 按住期间按 ≤300ms 间隔连续下发 MoveByAction，单次 duration ≤500ms；
/// - 六路立即停止：抬指 / 滑出 / 切后台 / 锁屏 / 断连 / 关面板；
/// - 任一 RPC 失败立即停止全部下发；
/// - 遥控期间与导航/巡逻/回充**双向互斥**；
/// - 退出时清理状态，下次进入必须重新确认（状态不持久化）。
class RemoteControlController extends ChangeNotifier {
  RemoteControlController(this.services, this.gate);

  final AppServices services;
  final ActionGate gate;

  /// 本次连接是否已确认（当次连接内有效）
  bool confirmed = false;

  /// 面板是否激活（进入后）
  bool active = false;

  /// 当前按下的方向（null = 未按下）。同一时刻只允许一个方向生效。
  RcDirection? pressedDirection;

  /// 速度档索引（默认最低档，FR-RC-05）
  int gearIndex = AppConfig.rcDefaultGearIndex;

  /// 建图模式状态（FR-RC-10）
  bool? mappingEnabled;

  /// 本次会话统计（FR-RC-14）
  DateTime? sessionStart;
  DateTime? pressStartedAt;
  int pressCountTotal = 0;
  int emergencyStopCount = 0;
  int directionCountForward = 0;
  int directionCountBackward = 0;
  int directionCountLeft = 0;
  int directionCountRight = 0;
  double travelledMeters = 0;
  Pose? _lastPose;
  double? _pressStartDistance;

  Timer? _dispatchTimer;
  bool _dispatching = false;
  bool _stopping = false;

  /// 失败后短暂禁用（3s 自动恢复，PRD §5.12③）
  DateTime? _errorLockUntil;
  String? lastError;

  bool get isErrorLocked {
    final until = _errorLockUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  RcGear get gear => AppConfig.rcGears[gearIndex];

  bool get isMoving => pressedDirection != null;

  /// 本次按住已持续秒数
  int get pressSeconds {
    final t = pressStartedAt;
    if (t == null) return 0;
    return DateTime.now().difference(t).inSeconds;
  }

  /// 会话已持续秒数
  String get sessionDurationLabel {
    final t = sessionStart;
    if (t == null) return '—';
    final d = DateTime.now().difference(t);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '${h}:${_2(m)}:${_2(s)}'
        : '${_2(m)}:${_2(s)}';
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';

  /// 进入前预检（FR-RC-15）
  String? enterBlockReason() {
    if (!services.state.isConnected) return '未连接底盘';
    if (services.state.blocksRemoteControl) {
      return '检测到系统急停或致命故障（hasFatal / 系统急停），禁止进入遥控';
    }
    return null;
  }

  bool get canEnter => enterBlockReason() == null;

  /// 电量低提示（Q15：允许进入但确认页追加红色警示）
  bool get lowBatteryWarning => services.state.isLowBattery;

  /// 一次性确认（FR-RC-02）
  Future<void> confirm() async {
    confirmed = true;
    active = true;
    gate.remoteControlActive = true;
    sessionStart = DateTime.now();
    travelledMeters = 0;
    pressCountTotal = 0;
    emergencyStopCount = 0;
    directionCountForward = 0;
    directionCountBackward = 0;
    directionCountLeft = 0;
    directionCountRight = 0;
    _lastPose = services.state.pose;
    lastError = null;
    services.log.note('进入遥控面板（本次连接内已确认）');
    await refreshMappingState();
    notifyListeners();
  }

  /// 取消/退出面板
  Future<void> exit() async {
    await stopAll(reason: '关闭面板');
    active = false;
    confirmed = false;
    gate.remoteControlActive = false;
    sessionStart = null;
    pressedDirection = null;
    services.log.note('退出遥控面板（会话统计：$summaryText）');
    notifyListeners();
  }

  /// 读取建图开关（FR-RC-10）
  Future<void> refreshMappingState() async {
    final res = await services.slam.mappingEnabled();
    if (res.ok) mappingEnabled = res.data;
    notifyListeners();
  }

  /// 切换建图模式（可写，需二次确认，由 UI 触发）
  Future<bool> setMapping(bool enabled) async {
    final res = await services.slam.setMappingEnabled(enabled);
    if (res.ok) {
      mappingEnabled = enabled;
      services.log.note('建图模式已${enabled ? '开启' : '关闭'}');
      notifyListeners();
      return true;
    }
    lastError = res.error ?? '切换建图模式失败';
    notifyListeners();
    return false;
  }

  /// 保存地图（FR-RC-12：多楼层环境禁止该操作）
  Future<ApiResult<dynamic>> saveMap() async {
    services.log.note('请求保存地图（多楼层环境禁止执行，否则会丢失其他楼层地图）');
    final res = await services.slam.saveMap();
    notifyListeners();
    return res;
  }

  void setGear(int index) {
    if (index < 0 || index >= AppConfig.rcGears.length) return;
    gearIndex = index;
    services.log.note('遥控速度档切换为「${gear.label}」（占空比 ${gear.duty}）');
    notifyListeners();
  }

  /// 按下方向键（FR-RC-03/04）
  void press(RcDirection dir) {
    if (!active || isErrorLocked) return;
    if (pressedDirection == dir) return;
    // 同一时刻只允许一个方向生效：后按者优先，先按者立即停止
    if (pressedDirection != null) {
      unawaited(stopAll(reason: '切换方向'));
    }
    pressedDirection = dir;
    pressStartedAt = DateTime.now();
    _pressStartDistance = travelledMeters;
    _countDirection(dir);
    pressCountTotal++;
    _startDispatching();
    notifyListeners();
  }

  void _countDirection(RcDirection dir) {
    switch (dir) {
      case RcDirection.forward:
        directionCountForward++;
      case RcDirection.backward:
        directionCountBackward++;
      case RcDirection.left:
        directionCountLeft++;
      case RcDirection.right:
        directionCountRight++;
    }
  }

  /// 抬起手指（不弹提示，视为正常操作）
  void release() {
    if (pressedDirection == null) return;
    unawaited(stopAll(reason: '松开'));
  }

  void _startDispatching() {
    _dispatchTimer?.cancel();
    _dispatchTimer = Timer.periodic(
      Duration(milliseconds: services.settings.rcIntervalMs),
      (_) => unawaited(_dispatchOnce()),
    );
    unawaited(_dispatchOnce());
  }

  /// 单次下发（间隔 ≤300ms、duration ≤500ms）
  Future<void> _dispatchOnce() async {
    final dir = pressedDirection;
    if (dir == null || _dispatching || !active) return;
    if (!services.state.isConnected) {
      await stopAll(reason: '连接中断');
      return;
    }
    _dispatching = true;
    try {
      final res = await services.motion.moveBy(
        direction: dir.code,
        durationMs: services.settings.rcDurationMs,
      );
      if (!res.ok) {
        // 任一 RPC 失败 → 立即停止全部下发（实现红线）
        lastError = res.error ?? '指令下发失败，已停止';
        _errorLockUntil = DateTime.now().add(const Duration(seconds: 3));
        await stopAll(reason: '下发失败');
        notifyListeners();
        return;
      }
      _accumulateDistance();
    } finally {
      _dispatching = false;
    }
  }

  /// 本次行进距离由位姿增量累计；松手后归零不累加（FR-RC-08）
  void _accumulateDistance() {
    final pose = services.state.pose;
    final last = _lastPose;
    if (pose != null && last != null) {
      final dx = pose.x - last.x;
      final dy = pose.y - last.y;
      final step = math.sqrt(dx * dx + dy * dy);
      // 仅在合理范围内累计，过滤位姿跳变
      if (step < 1.0) travelledMeters += step;
    }
    if (pose != null) _lastPose = pose;
  }


  /// 立即停止（六路统一入口）：停止下发 + 兜底发一次 DELETE
  Future<void> stopAll({required String reason}) async {
    if (_stopping) return;
    _stopping = true;
    _dispatchTimer?.cancel();
    _dispatchTimer = null;
    pressedDirection = null;
    pressStartedAt = null;

    final change = travelledMeters - (_pressStartDistance ?? 0);
    _pressStartDistance = null;
    if (change.abs() > 0.001) {
      // 本次按住的行进距离已计入会话总距离，按住结束不再单独累加
    }

    try {
      emergencyStopCount++;
      services.log.note('遥控停止（$reason）→ DELETE actions/:current');
      await services.motion.deleteCurrentAction();
    } catch (_) {
      // 兜底失败不影响本地状态复位
    } finally {
      _stopping = false;
      notifyListeners();
    }
  }

  /// App 切后台 / 锁屏（由 UI 的 WidgetsBindingObserver 调用）
  Future<void> onAppBackground() async {
    if (!active) return;
    await stopAll(reason: 'App 切后台/锁屏');
    // 返回前台时面板为未激活状态，需重新确认
    confirmed = false;
  }

  /// 连接中断处理
  Future<void> onDisconnected() async {
    if (!active) return;
    await stopAll(reason: '连接中断');
    confirmed = false;
    notifyListeners();
  }

  /// 会话统计文本（FR-RC-14：写入日志并可导出）
  String get summaryText {
    final dur = sessionStart == null ? '—' : sessionDurationLabel;
    return '时长 $dur · 距离 ${travelledMeters.toStringAsFixed(2)} m · '
        '按住 $pressCountTotal 次（前$directionCountForward/后$directionCountBackward/'
        '左$directionCountLeft/右$directionCountRight）· 急停 $emergencyStopCount 次';
  }

  @override
  void dispose() {
    _dispatchTimer?.cancel();
    super.dispose();
  }
}

/// 遥控四向（与接口枚举一致：0 前进 / 1 后退 / 2 右转 / 3 左转）
enum RcDirection {
  forward(0, '前进'),
  backward(1, '后退'),
  right(2, '右转'),
  left(3, '左转');

  const RcDirection(this.code, this.label);

  final int code;
  final String label;
}
