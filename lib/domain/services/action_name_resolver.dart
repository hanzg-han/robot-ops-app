import '../../core/network/api_endpoints.dart';

/// 动作名解析（开发文档 §9「必须做」）。
///
/// 官方 Swagger 写 `slamtec.agent.actions.MoveToAction`，但**实机只认 `agent.actions.*`**。
/// 硬编码官方名会导致下发静默失败，因此必须：
/// 1. 启动时拉取 `action-factories`；
/// 2. 按**末段精确匹配**（而非 contains），避免误中 `SchedulableMoveToAction` 等变体；
/// 3. 兜底 `agent.actions.$suffix`。
class ActionNameResolver {
  ActionNameResolver();

  List<String> _factories = <String>[];

  /// 完整动作工厂清单（F9：实机返回 24 种），用于诊断展示
  List<String> get factories => List<String>.unmodifiable(_factories);

  bool get isLoaded => _factories.isNotEmpty;

  /// 用实机返回的工厂清单初始化。接受 [{action_name: ...}] 或 ["..."] 两种形态。
  void load(dynamic raw) {
    final list = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final n = item['action_name'];
          if (n is String && n.isNotEmpty) list.add(n);
        } else if (item is String && item.isNotEmpty) {
          list.add(item);
        }
      }
    }
    if (list.isNotEmpty) _factories = list;
  }

  /// 末段精确匹配解析；未加载或未命中时兜底 `agent.actions.$suffix`。
  String resolve(String suffix) {
    final hit = matchFactory(_factories, suffix);
    return hit ?? 'agent.actions.$suffix';
  }

  String moveTo() => resolve(ApiEndpoints.suffixMoveTo);
  String rotateTo() => resolve(ApiEndpoints.suffixRotateTo);
  String goHome() => resolve(ApiEndpoints.suffixGoHome);
  String moveBy() => resolve(ApiEndpoints.suffixMoveBy);

  /// 纯函数：从工厂清单中按末段精确匹配。
  ///
  /// 独立为静态方法以便单元测试（不接触网络）。
  static String? matchFactory(List<String> factories, String suffix) {
    for (final name in factories) {
      final parts = name.split('.');
      if (parts.isNotEmpty && parts.last == suffix) return name;
    }
    return null;
  }

  /// 用于诊断的完整清单文本（预检记录，PRD §3.2 FR-CON-08）
  String dumpFactories() => _factories.isEmpty
      ? '（未获取到动作工厂清单）'
      : '共 ${_factories.length} 种：\n${_factories.join('\n')}';
}
