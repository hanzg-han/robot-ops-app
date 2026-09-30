import 'dart:math' as math;

/// 电源状态（GET /api/core/system/v1/power/status，PRD §9.1）
class PowerStatus {
  PowerStatus({
    this.batteryPercentage,
    this.dockingStatus,
    this.isCharging,
    this.isDCConnected,
    this.powerStage,
    this.sleepMode,
  });

  final double? batteryPercentage;

  /// on_dock | not_on_dock | 其它（PRD：其它值原样显示并标记为未知）
  final String? dockingStatus;

  final bool? isCharging;
  final bool? isDCConnected;

  /// starting | running | restarting | shutingdown | error（Q1 已确认枚举）
  final String? powerStage;

  /// awake | waking_up | asleep（Q1 已确认枚举）
  final String? sleepMode;

  factory PowerStatus.fromJson(Map<String, dynamic> json) => PowerStatus(
        batteryPercentage: _num(json['batteryPercentage']),
        dockingStatus: _str(json['dockingStatus']),
        isCharging: _bool(json['isCharging']),
        isDCConnected: _bool(json['isDCConnected']),
        powerStage: _str(json['powerStage']),
        sleepMode: _str(json['sleepMode']),
      );

  /// FR-DASH-02：on_dock →「已上桩」，not_on_dock →「未上桩」，其它原样 + 未知标记
  String get dockingLabel {
    switch (dockingStatus) {
      case 'on_dock':
        return '已上桩';
      case 'not_on_dock':
        return '未上桩';
      case null:
      case '':
        return '—';
      default:
        return '$dockingStatus（未知）';
    }
  }

  /// FR-DASH-03：powerStage 中文映射，未知值原样显示
  String get powerStageLabel {
    switch (powerStage) {
      case 'starting':
        return '启动中';
      case 'running':
        return '运行中';
      case 'restarting':
        return '重启中';
      case 'shutingdown':
        return '关机中';
      case 'error':
        return '电源异常';
      case null:
      case '':
        return '—';
      default:
        return '$powerStage（未知）';
    }
  }

  /// FR-DASH-03：sleepMode 中文映射，未知值原样显示
  String get sleepModeLabel {
    switch (sleepMode) {
      case 'awake':
        return '唤醒';
      case 'waking_up':
        return '唤醒中';
      case 'asleep':
        return '休眠';
      case null:
      case '':
        return '—';
      default:
        return '$sleepMode（未知）';
    }
  }
}

/// 机型与固件（GET /api/core/system/v1/robot/info，FR-DASH-04）
class RobotInfo {
  RobotInfo({
    this.modelName,
    this.softwareVersion,
    this.modelId,
    this.hardwareVersion,
    this.deviceId,
  });

  final String? modelName;
  final String? softwareVersion;

  /// F8：实机另有 modelId / hardwareVersion / deviceID
  final Object? modelId;
  final String? hardwareVersion;
  final String? deviceId;

  factory RobotInfo.fromJson(Map<String, dynamic> json) => RobotInfo(
        modelName: _str(json['modelName']),
        softwareVersion: _str(json['softwareVersion']),
        modelId: json['modelId'],
        hardwareVersion: _str(json['hardwareVersion']),
        deviceId: _str(json['deviceID'] ?? json['deviceId']),
      );

  /// 机型 + 型号 ID（调试台展示方式）
  String get modelLabel {
    final name = modelName ?? '—';
    return modelId == null ? name : '$name（$modelId）';
  }
}

/// 一条 baseError（开发文档 §15.4）
class BaseErrorItem {
  BaseErrorItem({this.message, this.errorCode, this.level});

  final String? message;
  final Object? errorCode;

  /// level ≥ 2 记为红色告警
  final num? level;

  factory BaseErrorItem.fromJson(Map<String, dynamic> json) => BaseErrorItem(
        message: _str(json['message']),
        errorCode: json['errorCode'],
        level: _num(json['level']),
      );

  bool get isRed => (level ?? 0) >= 2;

  String get label {
    final m = message ?? '底盘错误';
    return errorCode == null ? m : '$m（$errorCode）';
  }
}

/// 设备健康（GET /api/core/system/v1/robot/health）
///
/// F1：实机返回 8 字段（spec 仅 4 个），以实机为准。
class RobotHealth {
  RobotHealth({
    required this.baseErrors,
    this.hasError,
    this.hasWarning,
    this.hasFatal,
    this.hasSystemEmergencyStop,
    this.hasLidarDisconnected,
    this.hasDepthCameraDisconnected,
    this.hasSdpDisconnected,
  });

  final List<BaseErrorItem> baseErrors;
  final bool? hasError;
  final bool? hasWarning;
  final bool? hasFatal;
  final bool? hasSystemEmergencyStop;
  final bool? hasLidarDisconnected;
  final bool? hasDepthCameraDisconnected;
  final bool? hasSdpDisconnected;

  factory RobotHealth.fromJson(Map<String, dynamic> json) {
    final raw = json['baseError'];
    final list = <BaseErrorItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(BaseErrorItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return RobotHealth(
      baseErrors: list,
      hasError: _bool(json['hasError']),
      hasWarning: _bool(json['hasWarning']),
      hasFatal: _bool(json['hasFatal']),
      hasSystemEmergencyStop: _bool(json['hasSystemEmergencyStop']),
      hasLidarDisconnected: _bool(json['hasLidarDisconnected']),
      hasDepthCameraDisconnected: _bool(json['hasDepthCameraDisconnected']),
      hasSdpDisconnected: _bool(json['hasSdpDisconnected']),
    );
  }

  bool get isAllClear =>
      baseErrors.isEmpty &&
      !(hasError ?? false) &&
      !(hasWarning ?? false) &&
      !(hasFatal ?? false) &&
      !(hasSystemEmergencyStop ?? false) &&
      !(hasLidarDisconnected ?? false) &&
      !(hasDepthCameraDisconnected ?? false) &&
      !(hasSdpDisconnected ?? false);

  /// 是否禁止进入遥控（FR-RC-15）
  bool get blocksRemoteControl =>
      (hasFatal ?? false) || (hasSystemEmergencyStop ?? false);

  /// 健康告警明细（FR-DASH-09 / FR-EVT-06：专项中文文案）
  List<HealthAlert> get alerts {
    final list = <HealthAlert>[];
    if (hasFatal ?? false) {
      list.add(HealthAlert('设备致命告警（Fatal）', '设备健康报警（Error/Fatal）', isRed: true));
    }
    if (hasError ?? false) {
      list.add(HealthAlert('设备错误（Error）', '设备健康报警（Error/Fatal）', isRed: true));
    }
    if (hasWarning ?? false) {
      list.add(const HealthAlert('设备警告（Warning）', '设备健康报警', isRed: false));
    }
    if (hasSystemEmergencyStop ?? false) {
      list.add(const HealthAlert('系统急停', '底盘急停被触发', isRed: true));
    }
    if (hasLidarDisconnected ?? false) {
      list.add(const HealthAlert('雷达断开', '雷达连接丢失', isRed: true));
    }
    if (hasDepthCameraDisconnected ?? false) {
      list.add(const HealthAlert('深度相机断开', '深度相机连接丢失', isRed: false));
    }
    if (hasSdpDisconnected ?? false) {
      list.add(const HealthAlert('SDP 断开', 'SDP 连接丢失', isRed: false));
    }
    for (final e in baseErrors) {
      list.add(HealthAlert(e.label, '底盘上报错误', isRed: e.isRed));
    }
    return list;
  }
}

class HealthAlert {
  const HealthAlert(this.title, this.detail, {required this.isRed});

  final String title;
  final String detail;
  final bool isRed;
}

/// 位姿（GET /api/core/slam/v1/localization/pose）
class Pose {
  Pose({required this.x, required this.y, required this.yaw, this.z, this.pitch, this.roll});

  final double x;
  final double y;

  /// 弧度
  final double yaw;

  final double? z;
  final double? pitch;
  final double? roll;

  factory Pose.fromJson(Map<String, dynamic> json) => Pose(
        x: _num(json['x'])?.toDouble() ?? 0,
        y: _num(json['y'])?.toDouble() ?? 0,
        yaw: _num(json['yaw'])?.toDouble() ?? 0,
        z: _num(json['z'])?.toDouble(),
        pitch: _num(json['pitch'])?.toDouble(),
        roll: _num(json['roll'])?.toDouble(),
      );

  bool get isValid =>
      !x.isNaN && !y.isNaN && !yaw.isNaN && !x.isInfinite && !y.isInfinite;
}

/// 当前行为（GET /api/core/motion/v1/actions/:current；404 时为 null）
class ActionState {
  ActionState({
    required this.actionId,
    required this.actionName,
    this.stage,
    required this.status,
    this.result,
    this.reason,
    this.createdAt,
  });

  final Object actionId;
  final String actionName;
  final String? stage;

  /// 0 NewBorn | 1 Working | 3 Paused | 4 Done
  final int status;

  /// 0 Success | -1 Failed | -2 Aborted（未给出视为成功）
  final int? result;

  final String? reason;

  /// 本地记录的下发时刻（用于「已耗时」）
  final DateTime? createdAt;

  factory ActionState.fromJson(Map<String, dynamic> json) {
    final state = json['state'];
    final s = state is Map ? Map<String, dynamic>.from(state) : <String, dynamic>{};
    final id = json['action_id'];
    return ActionState(
      actionId: id ?? 0,
      actionName: _str(json['action_name']) ?? '',
      stage: _str(json['stage']),
      status: _num(s['status'])?.toInt() ?? 1,
      result: _num(s['result'])?.toInt(),
      reason: _str(s['reason']),
    );
  }

  /// 动作短名（末段），如 MoveToAction
  String get shortName {
    final parts = actionName.split('.');
    return parts.isEmpty ? actionName : parts.last;
  }

  /// 中文短名（PRD §7.2 术语按用户说）
  String get shortLabel {
    switch (shortName) {
      case 'MoveToAction':
        return '导航';
      case 'RotateToAction':
        return '原地旋转';
      case 'GoHomeAction':
        return '回充';
      case 'MoveByAction':
        return '遥控';
      default:
        return shortName;
    }
  }

  /// 是否已结束（status ∈ {0,4}，开发文档 §10.2）
  bool get isFinished => status == 0 || status == 4;

  bool get isWorking => status == 1;

  bool get isPaused => status == 3;

  String get statusLabel {
    switch (status) {
      case 0:
        return '已结束';
      case 1:
        return '运行中';
      case 3:
        return '已暂停';
      case 4:
        return '已结束';
      default:
        return '状态 $status';
    }
  }

  /// result 判定（未给出视为成功）
  ActionOutcome get outcome {
    if (!isFinished) return ActionOutcome.running;
    switch (result) {
      case -1:
        return ActionOutcome.failed;
      case -2:
        return ActionOutcome.aborted;
      default:
        return ActionOutcome.success;
    }
  }

  /// 失败原因中文说明（FR-NAV-09：显示 reason 中文说明）
  String get reasonLabel {
    if (reason == null || reason!.isEmpty) {
      switch (outcome) {
        case ActionOutcome.failed:
          return '导航失败（未给出原因）';
        case ActionOutcome.aborted:
          return '已被终止';
        case ActionOutcome.success:
          return '已完成';
        case ActionOutcome.running:
          return '';
      }
    }
    final zh = _reasonZh[reason!];
    return zh == null ? reason! : '$zh（$reason）';
  }

  ActionState copyWith({DateTime? createdAt}) => ActionState(
        actionId: actionId,
        actionName: actionName,
        stage: stage,
        status: status,
        result: result,
        reason: reason,
        createdAt: createdAt ?? this.createdAt,
      );

  static const Map<String, String> _reasonZh = <String, String>{
    'target occupied': '目标点被占据',
    'occupied': '目标点被占据',
    'timeout': '超时',
    'aborted': '行为被终止',
    'canceled': '行为被取消',
    'cancelled': '行为被取消',
    'no path': '无可行路径',
    'unreachable': '目标不可达',
    'localization error': '定位异常',
    'dock not found': '找不到充电桩',
  };
}

enum ActionOutcome { running, success, failed, aborted }

/// POI（GET /api/core/artifact/v1/pois，PRD §9.1 三级兜底命名）
class Poi {
  Poi({required this.id, required this.pose, required this.metadata});

  final String id;
  final Pose pose;
  final Map<String, dynamic> metadata;

  factory Poi.fromJson(Map<String, dynamic> json) => Poi(
        id: _str(json['id']) ?? '未知',
        pose: Pose.fromJson(
          json['pose'] is Map ? Map<String, dynamic>.from(json['pose'] as Map) : <String, dynamic>{},
        ),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : <String, dynamic>{},
      );

  /// display_name → name → id（三级兜底，不出现空白名称）
  String get displayName {
    final d = metadata['display_name'];
    if (d is String && d.trim().isNotEmpty) return d.trim();
    final n = metadata['name'];
    if (n is String && n.trim().isNotEmpty) return n.trim();
    return id;
  }

  String? get type => _str(metadata['type']);

  /// POI 命名规范首段（楼层），用于分组（PRD §14.3）
  String get floorGroup {
    final name = displayName;
    final idx = name.indexOf('-');
    if (idx <= 0) return '未分组';
    final head = name.substring(0, idx);
    return RegExp(r'^(B\d+|\d+F)$', caseSensitive: false).hasMatch(head) ? head : '未分组';
  }

  /// 末段（用途），用于图标着色（PRD §14.3 R3）
  String get usageTail {
    final parts = displayName.split('-');
    return parts.length <= 1 ? '' : parts.last;
  }
}

/// 充电桩（GET /api/core/slam/v1/homedocks）
class Dock {
  Dock({required this.id, required this.pose, required this.metadata});

  final String id;
  final Pose pose;
  final Map<String, dynamic> metadata;

  factory Dock.fromJson(Map<String, dynamic> json) => Dock(
        id: _str(json['id']) ?? '未知',
        pose: Pose.fromJson(
          json['pose'] is Map ? Map<String, dynamic>.from(json['pose'] as Map) : <String, dynamic>{},
        ),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : <String, dynamic>{},
      );

  String get displayName {
    final d = metadata['display_name'];
    if (d is String && d.trim().isNotEmpty) return d.trim();
    final n = metadata['name'];
    if (n is String && n.trim().isNotEmpty) return n.trim();
    return id;
  }
}

/// 一条虚拟墙/虚拟轨道线段（由 {start,end} 展平）
class WallLine {
  WallLine({required this.x1, required this.y1, required this.x2, required this.y2});

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  factory WallLine.fromJson(Map<String, dynamic> json) {
    final s = json['start'] is Map ? Map<String, dynamic>.from(json['start'] as Map) : <String, dynamic>{};
    final e = json['end'] is Map ? Map<String, dynamic>.from(json['end'] as Map) : <String, dynamic>{};
    return WallLine(
      x1: _num(s['x'])?.toDouble() ?? 0,
      y1: _num(s['y'])?.toDouble() ?? 0,
      x2: _num(e['x'])?.toDouble() ?? 0,
      y2: _num(e['y'])?.toDouble() ?? 0,
    );
  }
}

/// 激光扫描（GET /api/core/system/v1/laserscan）
class LaserScan {
  LaserScan({required this.pose, required this.points});

  final Pose pose;

  /// 已转换为地图坐标系的点（FR-MAP-06）
  final List<List<double>> points;

  factory LaserScan.fromJson(Map<String, dynamic> json) {
    final pose = Pose.fromJson(
      json['pose'] is Map ? Map<String, dynamic>.from(json['pose'] as Map) : <String, dynamic>{},
    );
    final raw = json['laser_points'];
    final pts = <List<double>>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is! Map) continue;
        final valid = p['valid'];
        final distance = _num(p['distance'])?.toDouble();
        final angle = _num(p['angle'])?.toDouble();
        if (valid == false || distance == null || angle == null) continue;
        if (distance <= 0.05 || distance > 30) continue;
        final a = pose.yaw + angle;
        pts.add(<double>[
          pose.x + distance * _cos(a),
          pose.y + distance * _sin(a),
        ]);
      }
    }
    return LaserScan(pose: pose, points: pts);
  }
}

/// 速度（GET /api/core/motion/v1/speed，FR-MOT-07）
class RobotSpeed {
  RobotSpeed({this.vx, this.vy, this.omega});

  final double? vx;
  final double? vy;
  final double? omega;

  factory RobotSpeed.fromJson(Map<String, dynamic> json) => RobotSpeed(
        vx: _num(json['vx'])?.toDouble(),
        vy: _num(json['vy'])?.toDouble(),
        omega: _num(json['omega'])?.toDouble(),
      );
}

/// 能力项（GET /api/core/system/v1/capabilities；F10：实机返回 4 项含版本）
class Capability {
  Capability({required this.name, this.enabled, this.version});

  final String name;
  final bool? enabled;
  final String? version;

  factory Capability.fromJson(Map<String, dynamic> json) => Capability(
        name: _str(json['name']) ?? '未知能力',
        enabled: _bool(json['enabled']),
        version: _str(json['version']),
      );

  String get label => version == null ? name : '$name（$version）';
}

// ---------------------------------------------------------------- 解析辅助
double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String? _str(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

bool? _bool(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return null;
}

double _sin(double x) => math.sin(x);
double _cos(double x) => math.cos(x);
