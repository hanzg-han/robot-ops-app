import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/request_log.dart';
import '../data/repositories/repositories.dart';
import '../domain/services/action_name_resolver.dart';
import '../app_state/robot_state.dart';
import '../app_state/settings_store.dart';

/// 极简依赖注入容器。
///
/// PRD/开发文档建议使用 Riverpod；本工程为现场运维工具、依赖关系单一，
/// 这里用等价的显式容器 + [ChangeNotifier] 提供同样的「单一入口 + 可测试」效果，
/// 同时避免为 12 个 DTO 引入代码生成（开发文档 §4.2 明确允许）。
class AppServices {
  AppServices._({
    required this.log,
    required this.settings,
    required this.resolver,
    required this.client,
    required this.system,
    required this.motion,
    required this.slam,
    required this.artifact,
    required this.eventsRepo,
    required this.state,
  });

  final RequestLogBuffer log;
  final SettingsStore settings;
  final ActionNameResolver resolver;
  final ApiClient client;
  final SystemRepository system;
  final MotionRepository motion;
  final SlamRepository slam;
  final ArtifactRepository artifact;
  final EventRepository eventsRepo;
  final RobotState state;

  static AppServices? _instance;

  static AppServices get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppServices 尚未初始化，请先调用 AppServices.init()');
    }
    return i;
  }

  /// 启动时初始化：加载本地设置 → 构建客户端 → 应用设置 → 启动轮询
  static Future<AppServices> init() async {
    final log = RequestLogBuffer(capacity: AppConfig.defaultLogCapacity);
    final settings = SettingsStore();
    await settings.load();
    log.capacity = settings.logCapacity;

    final client = ApiClient(log: log)
      ..configure(
        baseUrl: settings.baseUrl,
        timeoutMs: settings.timeoutMs,
        longTimeoutMs: settings.longTimeoutMs,
      );

    final resolver = ActionNameResolver();
    final system = SystemRepository(client);
    final motion = MotionRepository(client, resolver);
    final slam = SlamRepository(client);
    final artifact = ArtifactRepository(client);
    final eventsRepo = EventRepository(client);

    final state = RobotState(
      client: client,
      settings: settings,
      log: log,
      resolver: resolver,
      system: system,
      motion: motion,
      slam: slam,
      artifact: artifact,
      eventsRepo: eventsRepo,
    );

    final services = AppServices._(
      log: log,
      settings: settings,
      resolver: resolver,
      client: client,
      system: system,
      motion: motion,
      slam: slam,
      artifact: artifact,
      eventsRepo: eventsRepo,
      state: state,
    );
    _instance = services;
    return services;
  }

  /// 设置变更后把新配置同步到客户端与轮询节奏
  void applySettingsToClient() {
    client.configure(
      baseUrl: settings.baseUrl,
      timeoutMs: settings.timeoutMs,
      longTimeoutMs: settings.longTimeoutMs,
    );
    log.capacity = settings.logCapacity;
    state.restartPolling();
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
