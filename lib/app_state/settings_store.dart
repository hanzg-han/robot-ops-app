import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../domain/services/patrol_engine.dart';

/// 本地持久化（PRD §9.3）。
///
/// 键名与 PRD §9.3 表一一对应，便于现场排障时核对。
class SettingsStore extends ChangeNotifier {
  static const String kBaseUrl = 'baseUrl';
  static const String kTimeoutMs = 'timeoutMs';
  static const String kLongTimeoutMs = 'longTimeoutMs';
  static const String kAutoPoll = 'autoPoll';
  static const String kPollIntervalMs = 'pollIntervalMs';
  static const String kLaserIntervalMs = 'laserIntervalMs';
  static const String kLowBatteryThreshold = 'lowBatteryThreshold';
  static const String kAlertBanner = 'alertBanner';
  static const String kAlertSound = 'alertSound';
  static const String kLayerVisibility = 'layerVisibility';
  static const String kPatrolDraft = 'patrolDraft';
  static const String kPinHash = 'pinHash';
  static const String kRecentBaseUrls = 'recentBaseUrls';
  static const String kAngleInDegrees = 'angleInDegrees';
  static const String kCoordDecimals = 'coordDecimals';
  static const String kMapDefaultFit = 'mapDefaultFit';
  static const String kLogCapacity = 'logCapacity';
  static const String kRcIntervalMs = 'rcIntervalMs';
  static const String kRcDurationMs = 'rcDurationMs';
  static const String kRcSpeedStep = 'rcSpeedStep';
  static const String kMapViewport = 'mapViewport';

  // ------------------------------------------------------------- 连接设置
  String baseUrl = AppConfig.defaultBaseUrl;
  int timeoutMs = AppConfig.defaultTimeoutMs;
  int longTimeoutMs = AppConfig.defaultLongTimeoutMs;
  bool autoPoll = true;
  int pollIntervalMs = AppConfig.defaultPollIntervalMs;
  int laserIntervalMs = AppConfig.defaultLaserIntervalMs;

  /// 历史地址（FR-CON-09：最近 3 个）
  List<String> recentBaseUrls = <String>[];

  // ------------------------------------------------------------- 告警设置
  int lowBatteryThreshold = AppConfig.defaultLowBatteryThreshold;
  bool alertBanner = true;
  bool alertSound = false;

  // ------------------------------------------------------------- 显示设置
  bool angleInDegrees = true;
  int coordDecimals = 3;

  /// 地图默认取景：'all' 整图 / 'robot' 居中机器人
  String mapDefaultFit = 'all';

  // ------------------------------------------------------------- 容量设置
  int logCapacity = AppConfig.defaultLogCapacity;

  // --------------------------------------------------------- 遥控节奏设置
  int rcIntervalMs = AppConfig.rcDispatchIntervalMs;
  int rcDurationMs = AppConfig.rcDurationMs;
  double rcSpeedStep = AppConfig.rcLinearStepM;

  // ------------------------------------------------------------- 地图图层
  /// 图层开关状态（FR-MAP-11：同一次会话内保持）
  Map<String, bool> layerVisibility = <String, bool>{
    'grid': true,
    'gridLines': true,
    'trail': true,
    'laser': false,
    'poi': true,
    'dock': true,
    'walls': true,
    'route': true,
    'target': true,
    'trajectoryLabel': true,
  };

  /// 地图视野（会话内保持，非持久化项，这里只做内存缓存）
  Map<String, double>? mapViewport;

  // ------------------------------------------------------------- 巡逻草稿
  List<PatrolPoint> patrolDraft = <PatrolPoint>[];
  PatrolParams patrolParams = PatrolParams();

  /// PIN 锁（FR-SET-04，P2，默认关闭）
  String? pinHash;
  bool pinEnabled = false;

  bool isLoaded = false;

  // ---------------------------------------------------------------- 读写
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      baseUrl = ApiClient.normalizeBase(sp.getString(kBaseUrl) ?? AppConfig.defaultBaseUrl);
      timeoutMs = sp.getInt(kTimeoutMs) ?? AppConfig.defaultTimeoutMs;
      longTimeoutMs = sp.getInt(kLongTimeoutMs) ?? AppConfig.defaultLongTimeoutMs;
      autoPoll = sp.getBool(kAutoPoll) ?? true;
      pollIntervalMs = sp.getInt(kPollIntervalMs) ?? AppConfig.defaultPollIntervalMs;
      laserIntervalMs = sp.getInt(kLaserIntervalMs) ?? AppConfig.defaultLaserIntervalMs;
      lowBatteryThreshold =
          sp.getInt(kLowBatteryThreshold) ?? AppConfig.defaultLowBatteryThreshold;
      alertBanner = sp.getBool(kAlertBanner) ?? true;
      alertSound = sp.getBool(kAlertSound) ?? false;
      angleInDegrees = sp.getBool(kAngleInDegrees) ?? true;
      coordDecimals = sp.getInt(kCoordDecimals) ?? 3;
      mapDefaultFit = sp.getString(kMapDefaultFit) ?? 'all';
      logCapacity = sp.getInt(kLogCapacity) ?? AppConfig.defaultLogCapacity;
      rcIntervalMs = sp.getInt(kRcIntervalMs) ?? AppConfig.rcDispatchIntervalMs;
      rcDurationMs = sp.getInt(kRcDurationMs) ?? AppConfig.rcDurationMs;
      rcSpeedStep = sp.getDouble(kRcSpeedStep) ?? AppConfig.rcLinearStepM;

      final urls = sp.getStringList(kRecentBaseUrls);
      if (urls != null) recentBaseUrls = urls;

      final layers = sp.getString(kLayerVisibility);
      if (layers != null) {
        final decoded = jsonDecode(layers);
        if (decoded is Map) {
          layerVisibility = <String, bool>{
            ...layerVisibility,
            for (final e in decoded.entries)
              if (e.value is bool) e.key.toString(): e.value as bool,
          };
        }
      }

      final draft = sp.getString(kPatrolDraft);
      if (draft != null) {
        final decoded = jsonDecode(draft);
        if (decoded is Map) {
          final points = decoded['points'];
          if (points is List) {
            final parsed = <PatrolPoint>[];
            for (final p in points) {
              if (p is Map) {
                final pt = _tryPoint(Map<String, dynamic>.from(p));
                if (pt != null) parsed.add(pt);
              }
            }
            patrolDraft = parsed;
          }
          final params = decoded['params'];
          if (params is Map) {
            patrolParams = PatrolParams(
              loops: (params['loops'] as num?)?.toInt() ?? 1,
              dwellMs: (params['dwellMs'] as num?)?.toInt() ?? AppConfig.defaultPatrolDwellMs,
              speedRatio: (params['speedRatio'] as num?)?.toDouble() ??
                  AppConfig.defaultPatrolSpeedRatio,
              usePointYaw: params['usePointYaw'] as bool? ?? true,
              pointTimeoutMs: (params['pointTimeoutMs'] as num?)?.toInt() ??
                  AppConfig.defaultPatrolPointTimeoutMs,
            );
          }
        }
      }

      pinHash = sp.getString(kPinHash);
      pinEnabled = pinHash != null;
    } catch (_) {
      // FR：读取异常回落默认值，不阻断启动
    } finally {
      isLoaded = true;
      notifyListeners();
    }
  }

  static PatrolPoint? _tryPoint(Map<String, dynamic> json) {
    try {
      return PatrolPoint.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(String key, Object? value) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (value == null) {
        await sp.remove(key);
      } else if (value is String) {
        await sp.setString(key, value);
      } else if (value is int) {
        await sp.setInt(key, value);
      } else if (value is bool) {
        await sp.setBool(key, value);
      } else if (value is double) {
        await sp.setDouble(key, value);
      } else if (value is List<String>) {
        await sp.setStringList(key, value);
      }
    } catch (_) {
      // 持久化失败不影响当前会话
    }
  }

  Future<void> setBaseUrl(String raw) async {
    baseUrl = ApiClient.normalizeBase(raw);
    await _save(kBaseUrl, baseUrl);
    // 历史地址：最近 3 个（去重、最新在前）
    recentBaseUrls = <String>[
      baseUrl,
      ...recentBaseUrls.where((u) => u != baseUrl),
    ].take(3).toList();
    await _save(kRecentBaseUrls, recentBaseUrls);
    notifyListeners();
  }

  Future<void> setTimeoutMs(int v) async {
    timeoutMs = v;
    await _save(kTimeoutMs, v);
    notifyListeners();
  }

  Future<void> setAutoPoll(bool v) async {
    autoPoll = v;
    await _save(kAutoPoll, v);
    notifyListeners();
  }

  Future<void> setLaserIntervalMs(int v) async {
    laserIntervalMs = v;
    await _save(kLaserIntervalMs, v);
    notifyListeners();
  }

  /// 低电阈值（FR-DASH-07/FR-SET-03）
  Future<void> setLowBatteryThreshold(int v) async {
    lowBatteryThreshold = v.clamp(1, 100);
    await _save(kLowBatteryThreshold, lowBatteryThreshold);
    notifyListeners();
  }

  Future<void> setAlertBanner(bool v) async {
    alertBanner = v;
    await _save(kAlertBanner, v);
    notifyListeners();
  }

  Future<void> setAlertSound(bool v) async {
    alertSound = v;
    await _save(kAlertSound, v);
    notifyListeners();
  }

  Future<void> setAngleInDegrees(bool v) async {
    angleInDegrees = v;
    await _save(kAngleInDegrees, v);
    notifyListeners();
  }

  Future<void> setCoordDecimals(int v) async {
    coordDecimals = v;
    await _save(kCoordDecimals, v);
    notifyListeners();
  }

  Future<void> setMapDefaultFit(String v) async {
    mapDefaultFit = v;
    await _save(kMapDefaultFit, v);
    notifyListeners();
  }

  Future<void> setLogCapacity(int v) async {
    logCapacity = v;
    await _save(kLogCapacity, v);
    notifyListeners();
  }

  Future<void> setRcTuning({int? intervalMs, int? durationMs}) async {
    if (intervalMs != null) {
      rcIntervalMs = intervalMs.clamp(50, 300);
      await _save(kRcIntervalMs, rcIntervalMs);
    }
    if (durationMs != null) {
      rcDurationMs = durationMs.clamp(100, 500);
      await _save(kRcDurationMs, rcDurationMs);
    }
    notifyListeners();
  }

  Future<void> setLayer(String key, bool value) async {
    layerVisibility = <String, bool>{...layerVisibility, key: value};
    await _save(kLayerVisibility, jsonEncode(layerVisibility));
    notifyListeners();
  }

  void setMapViewport(Map<String, double>? viewport) {
    mapViewport = viewport;
  }

  Future<void> savePatrolDraft(List<PatrolPoint> points, PatrolParams params) async {
    patrolDraft = points;
    patrolParams = params;
    await _save(
      kPatrolDraft,
      jsonEncode(<String, dynamic>{
        'points': points.map((p) => p.toJson()).toList(),
        'params': <String, dynamic>{
          'loops': params.loops,
          'dwellMs': params.dwellMs,
          'speedRatio': params.speedRatio,
          'usePointYaw': params.usePointYaw,
          'pointTimeoutMs': params.pointTimeoutMs,
        },
      }),
    );
    notifyListeners();
  }

  /// 保存巡逻方案（FR-PAT-10，P2）
  Future<void> saveNamedPatrol(String name, List<PatrolPoint> points) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      'patrol_plan_$name',
      jsonEncode(points.map((p) => p.toJson()).toList()),
    );
  }

  Future<List<String>> listNamedPatrols() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getKeys().where((k) => k.startsWith('patrol_plan_')).map((k) => k.substring(12)).toList();
  }

  Future<List<PatrolPoint>?> loadNamedPatrol(String name) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('patrol_plan_$name');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final parsed = <PatrolPoint>[];
    for (final p in decoded) {
      if (p is Map) {
        final pt = _tryPoint(Map<String, dynamic>.from(p));
        if (pt != null) parsed.add(pt);
      }
    }
    return parsed;
  }

  /// 诊断信息一键复制（FR-SET-05）
  String diagnosticHeader({required String model, required String firmware}) =>
      '底盘地址：$baseUrl\n机型：$model\n固件：$firmware\n'
      'App 版本：${AppConfig.appVersion}\n超时：${timeoutMs}ms / 长超时：${longTimeoutMs}ms';
}
