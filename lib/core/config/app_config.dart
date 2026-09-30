/// 全局静态配置：默认地址、超时、轮询间隔、容量上限与动作节奏。
///
/// 对应 PRD §9.3「本地持久化项」与开发文档 §7.1「轮询策略」的默认值。
class AppConfig {
  const AppConfig._();

  /// App 版本（About 页展示；与 pubspec.yaml version 保持一致）
  static const String appVersion = '1.0.0';

  /// 底盘默认地址（开发文档 §3.2）
  static const String defaultBaseUrl = 'http://192.168.0.16:1448';

  // ---------------------------------------------------------------- 超时
  /// 常规请求超时（FR-CON-04 默认 8s）
  static const int defaultTimeoutMs = 8000;

  /// 地图二进制与搜路的独立超时（FR-CON-04 默认 15s）
  static const int defaultLongTimeoutMs = 15000;

  /// 超时可选档位（FR-CON-04：5s / 8s / 15s / 30s）
  static const List<int> timeoutOptions = <int>[5000, 8000, 15000, 30000];

  // ---------------------------------------------------------------- 轮询
  /// 总览类数据轮询间隔（2s）
  static const int defaultPollIntervalMs = 2000;

  /// 激光刷新间隔（限流 4s，FR-MAP-06）
  static const int defaultLaserIntervalMs = 4000;

  /// 遥控/建图期间地图自动刷新间隔（FR-RC-11，不得高于 2s）
  static const int defaultMappingMapIntervalMs = 3000;

  /// 机型/固件等低频数据的刷新间隔（30s，PRD §5.2）
  static const int slowRefreshIntervalMs = 30000;

  /// 判定「已连接」的窗口倍数：距上次成功 < 3×轮询间隔（PRD §3.4）
  static const int connectedWindowFactor = 3;

  // ------------------------------------------------------------ 阈值/容量
  /// 低电提醒阈值（FR-DASH-07 默认 25%）
  static const int defaultLowBatteryThreshold = 25;

  /// 请求日志容量（FR-LOG-04 默认 300）
  static const int defaultLogCapacity = 300;

  /// 事件本地留存上限（FR-EVT-09 默认 500）
  static const int defaultEventCapacity = 500;

  /// 行走轨迹点上限（FR-MAP-05，约 4000 点）
  static const int maxTrailPoints = 4000;

  /// 轨迹采样间隔（m，FR-MAP-05）
  static const double trailSampleMeters = 0.05;

  // ------------------------------------------------------------ 巡逻默认值
  /// 巡逻点间停留默认 5000 ms（FR-PAT-03）
  static const int defaultPatrolDwellMs = 5000;

  /// 巡逻速度比例默认 0.5
  static const double defaultPatrolSpeedRatio = 0.5;

  /// 巡逻单点超时默认 10 分钟（FR-PAT-08）
  static const int defaultPatrolPointTimeoutMs = 600000;

  /// 无限巡逻的圈数护栏（FR-PAT-03）
  static const int patrolLoopGuard = 100000;

  // ------------------------------------------------------------ 回充默认值
  static const String defaultGoHomeFlags = 'dock';
  static const int defaultGoHomeRetryCount = 2;
  static const bool defaultGoHomeBackToLanding = true;
  static const int defaultMoveMode = 0;

  // -------------------------------------------------------- 遥控（FR-RC）
  /// 连续下发间隔上限（FR-RC-04：≤300 ms）
  static const int rcDispatchIntervalMs = 300;

  /// 单次 duration 上限（FR-RC-04：≤500 ms）
  static const int rcDurationMs = 500;

  /// 三档速度的脉冲占空比（FR-RC-05：Q14 决策用占空比实现，不改写全局参数）
  static const List<RcGear> rcGears = <RcGear>[
    RcGear(label: '慢', duty: 0.35),
    RcGear(label: '中', duty: 0.60),
    RcGear(label: '快', duty: 1.00),
  ];

  /// 默认档位索引（FR-RC-05：默认最低档）
  static const int rcDefaultGearIndex = 0;

  /// 单次遥控下发的位移量 / 角速度（低速起步，由占空比进一步降低）
  static const double rcLinearStepM = 0.08;
  static const double rcAngularStepRad = 0.12;
}

/// 遥控速度档（FR-RC-05）
class RcGear {
  const RcGear({required this.label, required this.duty});

  final String label;

  /// 脉冲占空比：1.0 = 全时下发；<1.0 表示按住期间按比例插入空档，从而降低平均速度
  final double duty;
}
