/// 全部接口路径常量（开发文档 §10 API 对照表）。
///
/// 集中在此处，便于固件升级后批量调整（开发文档 §8.4）。
/// 注意：`:current`、`:search_path`、`:register`、`:enable`、`:save`
/// 均为**字面量路径段**，不是占位符（开发文档 §10.2 明确说明）。
class ApiEndpoints {
  const ApiEndpoints._();

  // ------------------------------------------------ §10.1 系统 / 电源 / 健康
  static const String capabilities = '/api/core/system/v1/capabilities';
  static const String powerStatus = '/api/core/system/v1/power/status';
  static const String robotInfo = '/api/core/system/v1/robot/info';
  static const String robotHealth = '/api/core/system/v1/robot/health';
  static const String parameter = '/api/core/system/v1/parameter';
  static const String odometry = '/api/core/statistics/v1/odometry';
  static const String laserscan = '/api/core/system/v1/laserscan';

  // ------------------------------------------------------ §10.2 行为与运动
  static const String actions = '/api/core/motion/v1/actions';
  static const String currentAction = '/api/core/motion/v1/actions/:current';
  static const String actionFactories = '/api/core/motion/v1/action-factories';
  static const String strategies = '/api/core/motion/v1/strategies/:current';
  static const String speed = '/api/core/motion/v1/speed';
  static const String searchPath = '/api/core/motion/v1/:search_path';

  /// F3：按 action_id 查询状态（比轮询 :current 更可靠）
  static String actionById(Object actionId) =>
      '/api/core/motion/v1/actions/$actionId';

  /// F4：剩余时间 / 路径点 / 目标点
  static const String actionTime = '/api/core/motion/v1/time';
  static const String actionPath = '/api/core/motion/v1/path';
  static const String actionMilestones = '/api/core/motion/v1/milestones';

  // ------------------------------------------------------ §10.3 定位与地图
  static const String pose = '/api/core/slam/v1/localization/pose';
  static const String quality = '/api/core/slam/v1/localization/quality';
  static const String localizationEnable = '/api/core/slam/v1/localization/:enable';
  static const String mapGrid = '/api/core/slam/v1/maps/explore';
  static const String homepose = '/api/core/slam/v1/homepose';
  static const String homedocks = '/api/core/slam/v1/homedocks';
  static const String dockRegister = '/api/core/slam/v1/homedocks/:register';

  // ------------------------------------------- §10.4 POI / 充电桩 / 虚拟墙
  static const String pois = '/api/core/artifact/v1/pois';
  static const String walls = '/api/core/artifact/v1/lines/walls';
  static const String tracks = '/api/core/artifact/v1/lines/tracks';

  // ------------------------------------------------------ §10.5 事件与时间
  static const String events = '/api/platform/v1/events';
  static const String machineTimestamp = '/api/platform/v1/timestamp';

  // ------------------------------------------------- §4.11 遥控：建图与保存
  static const String mappingEnable = '/api/core/slam/v1/mapping/:enable';
  static const String saveStcm = '/api/core/multi-floor/map/v1/stcm/:save';

  /// 动作名末段（下发前经 ActionNameResolver 解析为实机全名）
  static const String suffixMoveTo = 'MoveToAction';
  static const String suffixRotateTo = 'RotateToAction';
  static const String suffixGoHome = 'GoHomeAction';
  static const String suffixMoveBy = 'MoveByAction';
}
