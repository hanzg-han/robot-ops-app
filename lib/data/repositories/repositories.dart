import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_result.dart';
import '../../core/utils/num_fmt.dart';
import '../dto/models.dart';
import '../map/grid_codec.dart';
import '../../domain/services/action_name_resolver.dart';

/// 系统 / 电源 / 健康 / 参数（开发文档 §10.1）
class SystemRepository {
  SystemRepository(this.client);
  final ApiClient client;

  Future<ApiResult<List<Capability>>> capabilities({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.capabilities, polling: polling);
    return r.cast<List<Capability>>((d) {
      final list = <Capability>[];
      if (d is List) {
        for (final item in d) {
          if (item is Map) list.add(Capability.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    });
  }

  Future<ApiResult<PowerStatus>> powerStatus({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.powerStatus, polling: polling);
    return r.cast<PowerStatus>(
      (d) => d is Map ? PowerStatus.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  Future<ApiResult<RobotInfo>> robotInfo({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.robotInfo, polling: polling);
    return r.cast<RobotInfo>(
      (d) => d is Map ? RobotInfo.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  Future<ApiResult<RobotHealth>> robotHealth({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.robotHealth, polling: polling);
    return r.cast<RobotHealth>((d) {
      if (d is Map) return RobotHealth.fromJson(Map<String, dynamic>.from(d));
      if (d is List) {
        // 兼容数组形式（开发文档 §15.4 调试台的做法）
        return RobotHealth.fromJson(<String, dynamic>{
          'baseError': d,
          'hasError': d.any((e) => e is Map && (e['level'] ?? 0) >= 2),
          'hasWarning': d.isNotEmpty,
        });
      }
      return null;
    });
  }

  /// 累计里程（GET /statistics/v1/odometry，返回数字）
  Future<ApiResult<double>> odometry({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.odometry, polling: polling);
    return r.cast<double>((d) {
      if (d is num) return d.toDouble();
      if (d is String) return double.tryParse(d.trim());
      return null;
    });
  }

  /// 参数读取（FR-MOT-09：仅 3 项白名单）
  Future<ApiResult<dynamic>> readParameter(String name) =>
      client.get(ApiEndpoints.parameter, query: <String, dynamic>{'param': name});

  /// 参数写入（受控；调用方必须二次确认）
  Future<ApiResult<dynamic>> writeParameter(String name, Object? value) =>
      client.put(ApiEndpoints.parameter, body: <String, dynamic>{'param': name, 'value': value});

  /// 激光扫描（GET /system/v1/laserscan）
  Future<ApiResult<LaserScan>> laserScan({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.laserscan, polling: polling);
    return r.cast<LaserScan>(
      (d) => d is Map ? LaserScan.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }
}

/// 行为与运动（开发文档 §10.2 / §10.6）
class MotionRepository {
  MotionRepository(this.client, this.resolver);

  final ApiClient client;
  final ActionNameResolver resolver;

  // -------------------------------------------------------- 动作名预解析
  /// 启动时拉取动作工厂清单（开发文档 §9：必须做，否则下发静默失败）
  Future<ApiResult<List<String>>> loadActionFactories() async {
    final r = await client.get(ApiEndpoints.actionFactories);
    final list = <String>[];
    if (r.data is List) {
      for (final item in r.data as List) {
        if (item is Map) {
          final n = item['action_name'];
          if (n is String && n.isNotEmpty) list.add(n);
        } else if (item is String && item.isNotEmpty) {
          list.add(item);
        }
      }
    }
    if (list.isNotEmpty) resolver.load(list);
    return r.cast<List<String>>((_) => list);
  }

  /// 当前行为。**404 = 空闲，不是错误**（开发文档 §17 坑 8）。
  Future<ApiResult<ActionState?>> currentAction({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.currentAction, polling: polling);
    if (r.status == 404) {
      return ApiResult<ActionState?>(
        ok: true,
        status: 404,
        ms: r.ms,
        data: null,
      );
    }
    return r.cast<ActionState?>((d) {
      if (d is! Map) return null;
      final json = Map<String, dynamic>.from(d);
      if (json['action_id'] == null) return null;
      return ActionState.fromJson(json);
    });
  }

  /// F3：按 action_id 查询（行为被替换时不丢失）
  Future<ApiResult<ActionState?>> actionById(Object actionId) async {
    final r = await client.get(ApiEndpoints.actionById(actionId));
    if (r.status == 404) {
      return ApiResult<ActionState?>(
        ok: true,
        status: 404,
        ms: r.ms,
        data: null,
      );
    }
    return r.cast<ActionState?>(
      (d) => d is Map ? ActionState.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  /// F4：剩余时间
  Future<ApiResult<double?>> remainingTime() async {
    final r = await client.get(ApiEndpoints.actionTime);
    return r.cast<double?>((d) {
      if (d is num) return d.toDouble();
      if (d is String) return double.tryParse(d.trim());
      return null;
    });
  }

  /// 下发动作（移动级：调用方必须已完成二次确认）
  Future<ApiResult<dynamic>> createAction(String suffix, {Object? options}) {
    final body = <String, dynamic>{'action_name': resolver.resolve(suffix)};
    if (options != null) body['options'] = options;
    return client.post(ApiEndpoints.actions, body: body);
  }

  // ------------------------------------------------------------ 具体动作
  /// MoveToAction：导航到坐标
  Future<ApiResult<dynamic>> moveTo({
    required double x,
    required double y,
    double z = 0,
    int? mode,
    double? speedRatio,
    double? yawRad,
  }) {
    final moveOptions = <String, dynamic>{};
    if (mode != null) moveOptions['mode'] = mode;
    if (speedRatio != null) moveOptions['speed_ratio'] = speedRatio;
    if (yawRad != null) {
      moveOptions['yaw'] = yawRad;
      moveOptions['flags'] = <String>['with_yaw', 'precise'];
    }
    return createAction(
      ApiEndpoints.suffixMoveTo,
      options: <String, dynamic>{
        'target': <String, dynamic>{'x': x, 'y': y, 'z': z},
        if (moveOptions.isNotEmpty) 'move_options': moveOptions,
      },
    );
  }

  /// RotateToAction：原地旋转（单位弧度；界面用度，内部转换）
  Future<ApiResult<dynamic>> rotateTo(double angleRad) => createAction(
        ApiEndpoints.suffixRotateTo,
        options: <String, dynamic>{'angle': angleRad},
      );

  /// GoHomeAction：回充
  Future<ApiResult<dynamic>> goHome({
    String flags = AppConfig.defaultGoHomeFlags,
    bool backToLanding = AppConfig.defaultGoHomeBackToLanding,
    int retryCount = AppConfig.defaultGoHomeRetryCount,
    int mode = AppConfig.defaultMoveMode,
  }) =>
      createAction(
        ApiEndpoints.suffixGoHome,
        options: <String, dynamic>{
          'gohome_options': <String, dynamic>{
            'flags': flags,
            'back_to_landing': backToLanding,
            'charging_retry_count': retryCount,
            'move_options': <String, dynamic>{'mode': mode},
          },
        },
      );

  /// MoveByAction：遥控驾驶（FR-RC：direction 0 前进 / 1 后退 / 2 右转 / 3 左转）
  Future<ApiResult<dynamic>> moveBy({
    required int direction,
    int durationMs = AppConfig.rcDurationMs,
    double? thetaRad,
  }) {
    final options = <String, dynamic>{
      if (thetaRad == null) 'direction': direction,
      if (thetaRad != null) 'theta': thetaRad,
      'duration': durationMs,
    };
    return createAction(ApiEndpoints.suffixMoveBy, options: options);
  }

  /// 终止当前行为（急停）。
  ///
  /// Q4/F7：无行为时也返回 200 且响应体为空，因此
  /// **不能凭状态码判定「是否真的终止了什么」**，必须比对终止前后 :current 是否 404。
  Future<ApiResult<dynamic>> deleteCurrentAction() =>
      client.delete(ApiEndpoints.currentAction);

  /// 搜路（只读，不移动）。
  ///
  /// 失败常见 HTTP 500（目标不可达/被占据，开发文档 §17 坑 9）。
  Future<ApiResult<List<List<double>>>> searchPath({
    required double x,
    required double y,
    double z = 0,
    int timeoutMs = 8000,
  }) async {
    final r = await client.post(
      ApiEndpoints.searchPath,
      body: <String, dynamic>{
        'target': <String, dynamic>{'x': x, 'y': y, 'z': z},
        'timeout': timeoutMs,
      },
      longTimeout: true,
    );
    return r.cast<List<List<double>>>((d) {
      if (d is! Map) return <List<double>>[];
      final raw = d['path_points'];
      final pts = <List<double>>[];
      if (raw is List) {
        for (final p in raw) {
          if (p is List && p.length >= 2) {
            final px = p[0];
            final py = p[1];
            final x1 = px is num ? px.toDouble() : double.tryParse('$px');
            final y1 = py is num ? py.toDouble() : double.tryParse('$py');
            if (x1 != null && y1 != null) pts.add(<double>[x1, y1]);
          }
        }
      }
      return pts;
    });
  }

  /// 实时速度（FR-MOT-07）
  Future<ApiResult<RobotSpeed>> speed({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.speed, polling: polling);
    return r.cast<RobotSpeed>(
      (d) => d is Map ? RobotSpeed.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  /// 运动策略（F6：只读展示，v1.0 不提供切换）
  Future<ApiResult<String?>> strategy() async {
    final r = await client.get(ApiEndpoints.strategies);
    return r.cast<String?>((d) => d is String ? d : (d == null ? null : d.toString()));
  }
}

/// 定位与地图（开发文档 §10.3）
class SlamRepository {
  SlamRepository(this.client);
  final ApiClient client;

  Future<ApiResult<Pose>> pose({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.pose, polling: polling);
    return r.cast<Pose>(
      (d) => d is Map ? Pose.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  Future<ApiResult<double>> quality({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.quality, polling: polling);
    return r.cast<double>((d) {
      if (d is num) return d.toDouble();
      if (d is String) return double.tryParse(d.trim());
      return null;
    });
  }

  /// 定位是否开启。
  ///
  /// F2：true = 定位生效；false = 已暂停定位（纯里程模式）。
  /// 导航与回充的前置校验**必须同时检查本项为 true**。
  Future<ApiResult<bool>> localizationEnabled({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.localizationEnable, polling: polling);
    return r.cast<bool>((d) {
      if (d is bool) return d;
      if (d is num) return d != 0;
      if (d is String) return d.toLowerCase() == 'true';
      return null;
    });
  }

  /// 栅格地图（二进制，约 320KB，按需加载 + 手动刷新，不进 2s 轮询）
  Future<ApiResult<GridMap>> mapGrid() async {
    final r = await client.getBytes(ApiEndpoints.mapGrid, longTimeout: true);
    if (!r.ok || r.data == null) {
      return ApiResult<GridMap>(
        ok: false,
        status: r.status,
        ms: r.ms,
        error: r.error ?? '地图加载失败',
      );
    }
    final grid = GridCodec.decode(r.data!);
    if (grid == null) {
      return ApiResult<GridMap>(
        ok: false,
        status: r.status,
        ms: r.ms,
        error: '地图解析失败：${GridCodec.lastError ?? '未知原因'}',
      );
    }
    return ApiResult<GridMap>(ok: true, status: r.status, ms: r.ms, data: grid);
  }

  /// 充电桩位姿；**未设置返回 404**（开发文档 §17 坑 12）
  Future<ApiResult<Pose?>> homepose({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.homepose, polling: polling);
    if (r.status == 404) {
      return ApiResult<Pose?>(ok: true, status: 404, ms: r.ms, data: null);
    }
    return r.cast<Pose?>(
      (d) => d is Map ? Pose.fromJson(Map<String, dynamic>.from(d)) : null,
    );
  }

  /// 建图模式开关（FR-RC-10：GET/PUT mapping/:enable）
  Future<ApiResult<bool>> mappingEnabled() async {
    final r = await client.get(ApiEndpoints.mappingEnable);
    return r.cast<bool>((d) => d == true || d == 'true' || d == 1);
  }

  Future<ApiResult<dynamic>> setMappingEnabled(bool enabled) =>
      client.put(ApiEndpoints.mappingEnable, body: <String, dynamic>{'enable': enabled});

  /// 保存地图（FR-RC-12：多楼层环境禁止，会丢失其他楼层地图）
  Future<ApiResult<dynamic>> saveMap() =>
      client.post(ApiEndpoints.saveStcm, longTimeout: true);
}

/// POI / 充电桩 / 虚拟墙（开发文档 §10.4）
class ArtifactRepository {
  ArtifactRepository(this.client);
  final ApiClient client;

  Future<ApiResult<List<Poi>>> pois({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.pois, polling: polling);
    return r.cast<List<Poi>>((d) {
      final list = <Poi>[];
      if (d is List) {
        for (final item in d) {
          if (item is Map) list.add(Poi.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    });
  }

  Future<ApiResult<List<Dock>>> docks({bool polling = false}) async {
    final r = await client.get(ApiEndpoints.homedocks, polling: polling);
    return r.cast<List<Dock>>((d) {
      final list = <Dock>[];
      if (d is List) {
        for (final item in d) {
          if (item is Map) list.add(Dock.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return list;
    });
  }

  /// 把当前位置注册为充电桩（FR-MOT-08，可写，需二次确认）
  Future<ApiResult<dynamic>> registerDock() => client.post(ApiEndpoints.dockRegister);

  Future<ApiResult<List<WallLine>>> walls() async {
    final r = await client.get(ApiEndpoints.walls);
    return r.cast<List<WallLine>>(_lines);
  }

  Future<ApiResult<List<WallLine>>> tracks() async {
    final r = await client.get(ApiEndpoints.tracks);
    return r.cast<List<WallLine>>(_lines);
  }

  static List<WallLine> _lines(dynamic d) {
    final list = <WallLine>[];
    if (d is List) {
      for (final item in d) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          if (m['start'] != null && m['end'] != null) list.add(WallLine.fromJson(m));
        }
      }
    }
    return list;
  }
}

/// 事件与时间（开发文档 §10.5）
class EventRepository {
  EventRepository(this.client);
  final ApiClient client;

  Future<ApiResult<dynamic>> events({bool polling = true}) =>
      client.get(ApiEndpoints.events, polling: polling);

  /// 机器运行毫秒（事件时间换算基准）
  Future<ApiResult<double?>> machineTimestamp({bool polling = true}) async {
    final r = await client.get(ApiEndpoints.machineTimestamp, polling: polling);
    return r.cast<double?>((d) {
      if (d is num) return d.toDouble();
      if (d is String) return double.tryParse(d.trim());
      return null;
    });
  }
}

/// 参数白名单（FR-MOT-09 / F5：spec 明确为 3 项枚举，不做自由文本输入）
class ParameterWhitelist {
  const ParameterWhitelist._();

  static const String maxMovingSpeed = 'base.max_moving_speed';
  static const String maxAngularSpeed = 'base.max_angular_speed';
  static const String dockedRegisterStrategy = 'docking.docked_register_strategy';

  static const List<String> all = <String>[
    maxMovingSpeed,
    maxAngularSpeed,
    dockedRegisterStrategy,
  ];

  static const List<String> strategyOptions = <String>['always', 'when_not_exists'];

  /// 中文说明（写入前提示影响）
  static String describe(String param) {
    switch (param) {
      case maxMovingSpeed:
        return '最大线速度（m/s）：影响所有导航动作的行驶速度';
      case maxAngularSpeed:
        return '最大角速度（rad/s）：影响原地旋转与转向速度';
      case dockedRegisterStrategy:
        return '充电桩注册策略：影响自动回桩时的桩位注册行为';
      default:
        return param;
    }
  }

  static bool isEnum(String param) => param == dockedRegisterStrategy;

  /// 数值范围校验（避免把底盘调到危险值）
  static String? validate(String param, Object? value) {
    if (isEnum(param)) {
      if (value is String && strategyOptions.contains(value)) return null;
      return '${describe(param)}：只能取 ${strategyOptions.join(' / ')}';
    }
    final v = value is num ? value.toDouble() : double.tryParse('$value');
    if (v == null || !v.isFinite) return '${describe(param)}：请输入有效数字';
    if (v <= 0) return '${describe(param)}：必须大于 0';
    if (v > 5) return '${describe(param)}：数值过大（上限 5）';
    return null;
  }
}

/// 数值格式化的统一入口（供上层复用，避免各页重复依赖）
typedef NumericFormat = NumFmt;
