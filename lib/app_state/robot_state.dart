import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_result.dart';
import '../core/network/request_log.dart';
import '../data/dto/models.dart';
import '../data/repositories/repositories.dart';
import '../domain/services/action_name_resolver.dart';
import 'settings_store.dart';

/// 全局机器人状态与轮询（PRD §3.3、§3.4；开发文档 §7.1）。
///
/// 关键约定：
/// - 总览类数据固定 2s 轮询，**页面不可见时暂停**（由 UI 层调用 [setVisible]）；
/// - 轮询**互斥**：上一轮未结束时跳过本次（防请求堆积）；
/// - 地图二进制不进轮询，按需加载（由地图控制器单独发起）；
/// - 巡逻/遥控运行期间轮询**继续**（否则行为与位姿整段不刷新）。
class RobotState extends ChangeNotifier {
  RobotState({
    required this.client,
    required this.settings,
    required this.log,
    required this.resolver,
    required this.system,
    required this.motion,
    required this.slam,
    required this.artifact,
    required this.eventsRepo,
  }) {
    client.addConnListener(_onConnChanged);
  }

  final ApiClient client;
  final SettingsStore settings;
  final RequestLogBuffer log;
  final ActionNameResolver resolver;
  final SystemRepository system;
  final MotionRepository motion;
  final SlamRepository slam;
  final ArtifactRepository artifact;
  final EventRepository eventsRepo;

  // ------------------------------------------------------------ 只读数据
  PowerStatus? power;
  RobotInfo? robotInfo;
  RobotHealth? health;
  Pose? pose;
  double? quality;
  double? odometry;
  bool? localizationEnabled;
  ActionState? currentAction;

  /// 地图要素（POI / 充电桩 / 墙线 / 轨道）
  List<Poi> pois = <Poi>[];
  List<Dock> docks = <Dock>[];
  List<WallLine> walls = <WallLine>[];
  List<WallLine> tracks = <WallLine>[];
  Pose? homepose;
  bool homeposeMissing = false;

  /// 能力清单（连接页展示，F10）
  List<Capability> capabilities = <Capability>[];

  /// 运动策略（F6：只读展示）
  String? strategy;

  // ---------------------------------------------------------- 新鲜度时间戳
  DateTime? powerAt;
  DateTime? poseAt;
  DateTime? qualityAt;
  DateTime? actionAt;
  DateTime? healthAt;
  DateTime? infoAt;

  // ------------------------------------------------------------ 轮询状态
  Timer? _pollTimer;
  Timer? _slowTimer;
  bool _polling = false;
  bool _visible = true;
  bool _disposed = false;

  /// 上一轮动作是否为「运行中」（用于捕获结束边沿，触发到达反馈）
  bool _lastActionRunning = false;

  /// 行为结束回调（FR-NAV-09 到达反馈、巡逻状态机推进）
  final List<void Function(ActionState? last, ActionState? current)> _actionWatchers =
      <void Function(ActionState?, ActionState?)>[];

  void addActionWatcher(void Function(ActionState?, ActionState?) w) =>
      _actionWatchers.add(w);

  void removeActionWatcher(void Function(ActionState?, ActionState?) w) =>
      _actionWatchers.remove(w);

  /// 「已下发但状态获取中」标记（FR-SAFE-03）
  DateTime? _dispatchedAt;
  bool get awaitingActionStatus {
    final d = _dispatchedAt;
    if (d == null) return false;
    return DateTime.now().difference(d).inSeconds < 10 && currentAction == null;
  }

  void markDispatched() {
    _dispatchedAt = DateTime.now();
    notifyListeners();
  }

  // ------------------------------------------------------------------ 连接
  ConnState get connState => client.connState;

  bool get isConnected => connState == ConnState.connected;

  String get connLabel {
    switch (connState) {
      case ConnState.connected:
        return '已连接';
      case ConnState.connecting:
        return '连接中';
      case ConnState.slow:
        return '响应慢';
      case ConnState.disconnected:
      case ConnState.unknown:
        return '未连接';
    }
  }

  void _onConnChanged(ConnState state) {
    if (_disposed) return;
    notifyListeners();
  }

  // ------------------------------------------------------ 前置条件（门控）
  /// 定位是否可用（F2：false = 已暂停定位，导航与回充都必须置灰）
  bool get localizationOk => localizationEnabled == true;

  /// 是否已设置充电桩（homepose 非 404 或存在已注册 homedock）
  bool get hasDock => homepose != null || docks.isNotEmpty;

  /// 回充是否可用，并给出不可用原因（FR-MOT-01/FR-SAFE-06）
  String? get goHomeBlockReason {
    if (!isConnected) return '未连接底盘';
    if (!localizationOk) return '定位未开启';
    if (!hasDock) return '未设置充电桩位置';
    return null;
  }

  bool get canGoHome => goHomeBlockReason == null;

  /// 导航类操作不可用原因
  String? get navigationBlockReason {
    if (!isConnected) return '未连接底盘';
    if (!localizationOk) return '定位未开启';
    return null;
  }

  bool get canNavigate => navigationBlockReason == null;

  /// POI 为空时的提示（FR-NAV-01）
  String get emptyPoiHint => '底盘中还没有点位。点位需在底盘建图流程中标注，App 不支持新建 POI。';

  /// 是否已有行为在运行（连点保护 + 遥控互斥用）
  bool get hasRunningAction => currentAction != null && !currentAction!.isFinished;

  /// 低电提醒（FR-DASH-07）
  bool get isLowBattery {
    final b = power?.batteryPercentage;
    if (b == null) return false;
    return b < settings.lowBatteryThreshold;
  }

  /// 健康告警列表（FR-DASH-09）
  List<HealthAlert> get healthAlerts => health?.alerts ?? const <HealthAlert>[];

  bool get hasRedHealth => healthAlerts.any((a) => a.isRed);

  bool get hasHealthAlert => healthAlerts.isNotEmpty;

  /// 是否禁止进入遥控（FR-RC-15）
  bool get blocksRemoteControl => health?.blocksRemoteControl ?? false;

  // ------------------------------------------------------------- 页面可见
  /// 页面不可见 → 暂停轮询（FR-DASH-10 / 工程验收「切后台后无周期请求」）
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    if (visible) {
      // 返回前台立即刷新一次并同步当前行为
      unawaited(refreshNow());
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  // ---------------------------------------------------------------- 轮询
  void start() {
    _startPolling();
    unawaited(refreshNow());
    unawaited(refreshSlow());
    unawaited(refreshActionFactories());
  }

  void _startPolling() {
    _stopPolling();
    if (!settings.autoPoll) return;
    _pollTimer = Timer.periodic(
      Duration(milliseconds: settings.pollIntervalMs),
      (_) => unawaited(refreshNow()),
    );
    _slowTimer = Timer.periodic(
      const Duration(milliseconds: AppConfig.slowRefreshIntervalMs),
      (_) => unawaited(refreshSlow()),
    );
  }


  /// 连接状态监听（透传 ApiClient，便于 UI 响应断连）
  void addConnListener(void Function(ConnState) l) => client.addConnListener(l);

  void removeConnListener(void Function(ConnState) l) => client.removeConnListener(l);
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
  }

  /// 设置变更后的轮询重启
  void restartPolling() {
    if (_visible) _startPolling();
  }

  /// 一轮总览刷新（2s）。
  ///
  /// 互斥：上一轮未结束则跳过（PRD §8.1「请求不堆积」）。
  Future<void> refreshNow() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      const polling = true;
      final results = await Future.wait<Object?>(<Future<Object?>>[
        system.powerStatus(polling: polling),
        motion.currentAction(polling: polling),
        slam.pose(polling: polling),
        slam.quality(polling: polling),
        system.robotHealth(polling: polling),
      ]);
      final powerRes = results[0] as ApiResult<PowerStatus>;
      final actionRes = results[1] as ApiResult<ActionState?>;
      final poseRes = results[2] as ApiResult<Pose>;
      final qualityRes = results[3] as ApiResult<double>;
      final healthRes = results[4] as ApiResult<RobotHealth>;

      final prev = currentAction;

      if (powerRes.ok && powerRes.data != null) {
        power = powerRes.data;
        powerAt = DateTime.now();
      }
      if (poseRes.ok && poseRes.data != null) {
        pose = poseRes.data;
        poseAt = DateTime.now();
      }
      if (qualityRes.ok) {
        quality = qualityRes.data;
        qualityAt = DateTime.now();
      }
      if (healthRes.ok && healthRes.data != null) {
        health = healthRes.data;
        healthAt = DateTime.now();
      }
      if (actionRes.ok) {
        currentAction = actionRes.data;
        actionAt = DateTime.now();
      }

      // 行为结束边沿：通知订阅者（巡逻推进、到达反馈、标记清理）
      final wasRunning = prev != null && !prev.isFinished;
      final nowRunning = currentAction != null && !currentAction!.isFinished;
      if (wasRunning && !nowRunning) {
        _dispatchedAt = null;
        for (final w in List<void Function(ActionState?, ActionState?)>.from(_actionWatchers)) {
          w(prev, currentAction);
        }
      }
      if (nowRunning) {
        _dispatchedAt = null;
      }
      _lastActionRunning = nowRunning;

      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  /// 低频数据（机型/固件、定位开关、充电桩、里程、策略）：30s 或首次
  Future<void> refreshSlow() async {
    if (_disposed) return;
    final infoRes = await system.robotInfo();
    if (infoRes.ok && infoRes.data != null) {
      robotInfo = infoRes.data;
      infoAt = DateTime.now();
    }

    final locRes = await slam.localizationEnabled();
    if (locRes.ok) localizationEnabled = locRes.data;

    final homeRes = await slam.homepose();
    if (homeRes.status == 404) {
      homepose = null;
      homeposeMissing = true;
    } else if (homeRes.ok) {
      homepose = homeRes.data;
      homeposeMissing = false;
    }

    final dockRes = await artifact.docks();
    if (dockRes.ok && dockRes.data != null) docks = dockRes.data!;

    final odoRes = await system.odometry();
    if (odoRes.ok) odometry = odoRes.data;

    final strategyRes = await motion.strategy();
    if (strategyRes.ok) strategy = strategyRes.data;

    notifyListeners();
  }

  /// 连接预检（FR-CON-08）：capabilities / robot-info / localization / homepose / homedocks / 动作清单
  Future<void> runPreflight() async {
    final capRes = await system.capabilities();
    if (capRes.ok && capRes.data != null) capabilities = capRes.data!;

    await refreshActionFactories();
    await refreshSlow();

    final poiRes = await artifact.pois();
    if (poiRes.ok && poiRes.data != null) pois = poiRes.data!;

    notifyListeners();
  }

  /// 地图要素刷新（POI / 桩 / 墙线 / 轨道）
  Future<void> refreshMapArtifacts() async {
    final results = await Future.wait<Object?>(<Future<Object?>>[
      artifact.pois(),
      artifact.docks(),
      artifact.walls(),
      artifact.tracks(),
    ]);
    final poiRes = results[0] as ApiResult<List<Poi>>;
    final dockRes = results[1] as ApiResult<List<Dock>>;
    final wallRes = results[2] as ApiResult<List<WallLine>>;
    final trackRes = results[3] as ApiResult<List<WallLine>>;

    if (poiRes.ok && poiRes.data != null) pois = poiRes.data!;
    if (dockRes.ok && dockRes.data != null) docks = dockRes.data!;
    if (wallRes.ok && wallRes.data != null) walls = wallRes.data!;
    if (trackRes.ok && trackRes.data != null) tracks = trackRes.data!;
    notifyListeners();
  }

  /// 动作工厂清单（开发文档 §9：启动时解析，末段精确匹配）
  Future<void> refreshActionFactories() async {
    final res = await motion.loadActionFactories();
    if (res.ok && res.data != null && res.data!.isNotEmpty) {
      log.note('已解析动作工厂 ${res.data!.length} 种');
    }
    notifyListeners();
  }

  /// 下拉刷新（FR-DASH-11）：一轮全部总览数据 + 低频数据
  Future<void> pullToRefresh() async {
    await refreshNow();
    await refreshSlow();
  }

  /// 终止当前行为（FR-MOT-05/06）。
  ///
  /// 结果判定**必须依据终止前后 :current 是否 404**，不能仅凭 DELETE 的 200（Q4/F7）。
  Future<AbortOutcome> abortCurrentAction() async {
    final before = await motion.currentAction();
    final hadAction = before.ok && before.data != null && !before.data!.isFinished;

    final del = await motion.deleteCurrentAction();
    if (!del.ok && del.status != 404) {
      return AbortOutcome(
        kind: AbortKind.failed,
        message: del.error ?? '终止失败：底盘返回 HTTP ${del.status}',
      );
    }

    // 轮询一次确认是否真的空闲
    inTransaction:
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final after = await motion.currentAction();
      if (!after.ok || after.data == null || after.data!.isFinished) {
        currentAction = null;
        _dispatchedAt = null;
        notifyListeners();
        break inTransaction;
      }
    }

    await refreshNow();

    if (!hadAction && currentAction == null) {
      return const AbortOutcome(
        kind: AbortKind.nothingToAbort,
        message: '当前没有正在执行的行为。',
      );
    }
    return const AbortOutcome(kind: AbortKind.done, message: '已终止当前行为。');
  }

  @override
  void dispose() {
    _disposed = true;
    client.removeConnListener(_onConnChanged);
    _stopPolling();
    super.dispose();
  }
}

/// 终止结果（FR-MOT-06：区分「已终止成功」「本无行为可终止」「终止失败」）
class AbortOutcome {
  const AbortOutcome({required this.kind, required this.message});

  final AbortKind kind;
  final String message;
}

enum AbortKind { done, nothingToAbort, failed }
