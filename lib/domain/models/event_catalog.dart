/// 事件级别（PRD §7.2 语义色 / 开发文档 §15.3）
enum EventLevel { error, warning, info }

extension EventLevelLabel on EventLevel {
  String get label {
    switch (this) {
      case EventLevel.error:
        return '错误';
      case EventLevel.warning:
        return '警告';
      case EventLevel.info:
        return '信息';
    }
  }

  /// 排序权重：错误 > 警告 > 信息
  int get weight {
    switch (this) {
      case EventLevel.error:
        return 3;
      case EventLevel.warning:
        return 2;
      case EventLevel.info:
        return 1;
    }
  }
}

/// 事件类型 → 中文说明与级别（开发文档 §15.3，必须完整内置）。
class EventCatalog {
  const EventCatalog._();

  /// 事件类型 → 中文说明（PRD §15.3 表）
  static const Map<String, String> zh = <String, String>{
    // ------------------------------------------------------- 错误（红）
    'DEVICE_ERROR': '设备健康报警（Error/Fatal）',
    'WAIT_PLANNING_FAILED': '规划失败/等待超时',
    'MOVE_TO_LANDING_POINT_FAILED': '前往充电桩失败',
    'SEARCH_DOCK_FAILED': '找桩失败',
    'CHARGING_BASE_FAILED': '充电失败',
    'DOCK_ID_NOT_FOUND': '地图中找不到绑定的桩',
    'CLIFF_DETECTED': '检测到悬崖（防跌落触发）',
    'CURRENT_POSE_OCCUPIED': '当前位姿被占据',
    'LOCALIZATION_ANOMALY': '定位异常，需重定位或推回桩',
    'ENTER_ELEVATOR_FAILED': '进电梯失败',
    'LEAVE_ELEVATOR_FAILED': '出电梯失败',
    'SEARCH_ELEVATOR_PATH_FAILED': '搜索电梯路径失败',
    'DISINFECT_TASK_FAILED': '消毒任务失败',
    'UNDOCK_FAILED': '下桩失败',

    // ------------------------------------------------------- 警告（橙）
    'PATH_OCCUPIED': '行进路径被阻挡',
    'ROBOT_BLOCKED': '被长时间连续阻挡',
    'BUMPER_TRIGGERED': '碰撞传感器触发',
    'BRAKE_RELEASED': '刹车被释放',
    'ENTER_ELEVATOR_OCCUPIED': '进电梯被挡',
    'LEAVE_ELEVATOR_OCCUPIED': '出电梯被挡',
    'TAKE_ELEVATOR_OCCUPIED': '进出电梯被挡',
    'LOW_BATTERY': '电量过低，即将回桩',
    'DELIVERY_NO_PICKUP': '用户未取物（配送）',
    'COLLECT_NO_PICKUP': '用户未取物（取物）',
    'ROBOT_REBOOT': '机器人即将重启',
    'BACK_TO_RECEPTION_FOR_FAILED_ORDER': '配送失败回到前台',

    // ------------------------------------------------------- 信息（蓝）
    'RESET_MAP_TO_DOCK': '被推回桩并重置地图成功',
    'START_CHARGING': '开始充电',
    'STOP_CHARGING': '停止充电',
    'ON_DOCK': '已上桩',
    'OFF_DOCK': '已下桩',
    'UPGRADE': '正在升级固件',
    'POWER_OFF': '正在关机',
    'PASS_THE_NARROW_CORRIDOR': '通过窄走廊',
    'MAP_LOOP_CLOSURE': '建图闭环',
    'SET_MAP_DONE': '完成设置地图',
    'SYNC_MAP_FROM_CLOUD': '从云端同步地图',
    'WAIT_ELEVATOR': '到达电梯等待点',
    'ENTER_ELEVATOR': '即将进电梯',
    'LEAVE_ELEVATOR': '即将出电梯',
    'IN_ELEVATOR': '在电梯内',
    'OUT_OF_ELEVATOR': '在电梯外',
    'TURNING_ROUND_IN_ELEVATOR': '电梯内即将转身',
    'ENTER_ELEVATOR_PATH_FOUND': '进电梯搜路成功',
    'START_FROM_DOCK': '从桩上出发',
    'START_TO_WORK': '开始工作',
    'GET_OFF_WORK': '结束工作',
    'NEW_TASK_RECEIVED': '收到新任务',
    'DELIVERY_TASK_START': '开始配送',
    'STATION_TASK_START': '开始货柜取物',
    'OPERATING_CABINET': '正在操作货柜',
    'DELIVERY_SETTINGS_CHANGED': '配送设置已更新',
  };

  /// 未收录类型的级别推断规则（开发文档 §15.3）
  ///
  /// FAIL|ERROR|FAULT|_ANOMALY → 错误
  /// OCCUPIED|BLOCK|LOW_|WARN|RETRY|REBOOT → 警告
  /// 其余 → 信息
  static EventLevel levelOf(String type) {
    final known = _knownLevels[type];
    if (known != null) return known;

    final upper = type.toUpperCase();
    if (RegExp(r'FAIL|ERROR|FAULT|_ANOMALY').hasMatch(upper)) {
      return EventLevel.error;
    }
    if (RegExp(r'OCCUPIED|BLOCK|LOW_|WARN|RETRY|REBOOT').hasMatch(upper)) {
      return EventLevel.warning;
    }
    return EventLevel.info;
  }

  /// 中文说明；未收录时返回原文 + 推断提示
  static String describe(String type) {
    final hit = zh[type];
    if (hit != null) return hit;
    return '未收录事件类型（按关键词推断级别）';
  }

  /// 是否已收录（未收录时 UI 需同时显示原文）
  static bool isKnown(String type) => zh.containsKey(type);

  /// 已知类型的级别表（与 [zh] 表分级一致，逐项列出以便精确判定）
  static const Map<String, EventLevel> _knownLevels = <String, EventLevel>{
    'DEVICE_ERROR': EventLevel.error,
    'WAIT_PLANNING_FAILED': EventLevel.error,
    'MOVE_TO_LANDING_POINT_FAILED': EventLevel.error,
    'SEARCH_DOCK_FAILED': EventLevel.error,
    'CHARGING_BASE_FAILED': EventLevel.error,
    'DOCK_ID_NOT_FOUND': EventLevel.error,
    'CLIFF_DETECTED': EventLevel.error,
    'CURRENT_POSE_OCCUPIED': EventLevel.error,
    'LOCALIZATION_ANOMALY': EventLevel.error,
    'ENTER_ELEVATOR_FAILED': EventLevel.error,
    'LEAVE_ELEVATOR_FAILED': EventLevel.error,
    'SEARCH_ELEVATOR_PATH_FAILED': EventLevel.error,
    'DISINFECT_TASK_FAILED': EventLevel.error,
    'UNDOCK_FAILED': EventLevel.error,
    'PATH_OCCUPIED': EventLevel.warning,
    'ROBOT_BLOCKED': EventLevel.warning,
    'BUMPER_TRIGGERED': EventLevel.warning,
    'BRAKE_RELEASED': EventLevel.warning,
    'ENTER_ELEVATOR_OCCUPIED': EventLevel.warning,
    'LEAVE_ELEVATOR_OCCUPIED': EventLevel.warning,
    'TAKE_ELEVATOR_OCCUPIED': EventLevel.warning,
    'LOW_BATTERY': EventLevel.warning,
    'DELIVERY_NO_PICKUP': EventLevel.warning,
    'COLLECT_NO_PICKUP': EventLevel.warning,
    'ROBOT_REBOOT': EventLevel.warning,
    'BACK_TO_RECEPTION_FOR_FAILED_ORDER': EventLevel.warning,
    'RESET_MAP_TO_DOCK': EventLevel.info,
    'START_CHARGING': EventLevel.info,
    'STOP_CHARGING': EventLevel.info,
    'ON_DOCK': EventLevel.info,
    'OFF_DOCK': EventLevel.info,
    'UPGRADE': EventLevel.info,
    'POWER_OFF': EventLevel.info,
    'PASS_THE_NARROW_CORRIDOR': EventLevel.info,
    'MAP_LOOP_CLOSURE': EventLevel.info,
    'SET_MAP_DONE': EventLevel.info,
    'SYNC_MAP_FROM_CLOUD': EventLevel.info,
    'WAIT_ELEVATOR': EventLevel.info,
    'ENTER_ELEVATOR': EventLevel.info,
    'LEAVE_ELEVATOR': EventLevel.info,
    'IN_ELEVATOR': EventLevel.info,
    'OUT_OF_ELEVATOR': EventLevel.info,
    'TURNING_ROUND_IN_ELEVATOR': EventLevel.info,
    'ENTER_ELEVATOR_PATH_FOUND': EventLevel.info,
    'START_FROM_DOCK': EventLevel.info,
    'START_TO_WORK': EventLevel.info,
    'GET_OFF_WORK': EventLevel.info,
    'NEW_TASK_RECEIVED': EventLevel.info,
    'DELIVERY_TASK_START': EventLevel.info,
    'STATION_TASK_START': EventLevel.info,
    'OPERATING_CABINET': EventLevel.info,
    'DELIVERY_SETTINGS_CHANGED': EventLevel.info,
  };

  /// 告警详情页的动作联动建议（FR-EVT-08）
  ///
  /// 只给「入口建议」，不自动执行任何动作；每个入口仍走二次确认。
  static EventSuggestion? suggestionOf(String type) {
    switch (type) {
      case 'MOVE_TO_LANDING_POINT_FAILED':
      case 'SEARCH_DOCK_FAILED':
      case 'CHARGING_BASE_FAILED':
      case 'DOCK_ID_NOT_FOUND':
      case 'UNDOCK_FAILED':
        return EventSuggestion(action: '重试回充', kind: SuggestionKind.goHome);
      case 'PATH_OCCUPIED':
      case 'ROBOT_BLOCKED':
      case 'BUMPER_TRIGGERED':
        return EventSuggestion(action: '终止行为', kind: SuggestionKind.abort);
      case 'LOCALIZATION_ANOMALY':
      case 'CURRENT_POSE_OCCUPIED':
        return EventSuggestion(action: '查看定位质量', kind: SuggestionKind.openMap);
      default:
        return null;
    }
  }
}

class EventSuggestion {
  const EventSuggestion({required this.action, required this.kind});

  final String action;
  final SuggestionKind kind;
}

enum SuggestionKind { goHome, abort, openMap }
