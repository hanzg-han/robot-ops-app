import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ops_app/core/config/app_config.dart';
import 'package:robot_ops_app/domain/services/action_name_resolver.dart';

/// 动作名解析单元测试（开发文档 §9「必须做」）。
///
/// 硬编码官方名 `slamtec.agent.actions.*` 会导致下发**静默失败**，
/// 因此必须验证「末段精确匹配」与兜底行为。
void main() {
  group('ActionNameResolver.matchFactory 末段精确匹配', () {
    test('实机返回 agent.actions.* 时命中实机名', () {
      final factories = <String>[
        'agent.actions.MoveToAction',
        'agent.actions.RotateToAction',
        'agent.actions.GoHomeAction',
      ];
      expect(
        ActionNameResolver.matchFactory(factories, 'MoveToAction'),
        'agent.actions.MoveToAction',
      );
    });

    test('不得误中 SchedulableMoveToAction 之类的变体', () {
      final factories = <String>[
        'agent.actions.SchedulableMoveToAction',
        'agent.actions.MoveToAction',
        'agent.actions.SeriesMoveToAction',
      ];
      // 末段精确匹配 → 命中真正的 MoveToAction，而非前缀/包含匹配
      expect(
        ActionNameResolver.matchFactory(factories, 'MoveToAction'),
        'agent.actions.MoveToAction',
      );
    });

    test('只有变体存在时不得错误命中（返回 null，由兜底处理）', () {
      final factories = <String>[
        'agent.actions.SchedulableMoveToAction',
        'agent.actions.SeriesMoveToAction',
      ];
      expect(ActionNameResolver.matchFactory(factories, 'MoveToAction'), isNull);
    });

    test('未命中返回 null', () {
      expect(ActionNameResolver.matchFactory(<String>[], 'GoHomeAction'), isNull);
      expect(
        ActionNameResolver.matchFactory(<String>['agent.actions.OtherAction'], 'GoHomeAction'),
        isNull,
      );
    });
  });

  group('ActionNameResolver.resolve 兜底', () {
    test('未加载 factories 时兜底 agent.actions.\$suffix（不是 slamtec.agent）', () {
      final resolver = ActionNameResolver();
      expect(resolver.isLoaded, isFalse);
      expect(resolver.moveTo(), 'agent.actions.MoveToAction');
      expect(resolver.rotateTo(), 'agent.actions.RotateToAction');
      expect(resolver.goHome(), 'agent.actions.GoHomeAction');
      expect(resolver.moveBy(), 'agent.actions.MoveByAction');
    });

    test('load 支持 [{action_name: ...}] 形态并可用于解析', () {
      final resolver = ActionNameResolver();
      resolver.load(<Map<String, String>>[
        <String, String>{'action_name': 'agent.actions.MoveToAction'},
        <String, String>{'action_name': 'agent.actions.GoHomeAction'},
      ]);
      expect(resolver.isLoaded, isTrue);
      expect(resolver.factories.length, 2);
      expect(resolver.goHome(), 'agent.actions.GoHomeAction');
    });

    test('load 支持纯字符串数组形态', () {
      final resolver = ActionNameResolver();
      resolver.load(<String>['agent.actions.MoveByAction']);
      expect(resolver.moveBy(), 'agent.actions.MoveByAction');
    });

    test('resolve 结果始终以 agent.actions. 开头（前缀事实）', () {
      final resolver = ActionNameResolver();
      resolver.load(<String>['agent.actions.MoveToAction']);
      expect(resolver.moveTo().startsWith('agent.actions.'), isTrue);
      expect(resolver.moveTo().startsWith('slamtec.'), isFalse);
    });
  });

  group('遥控节奏常量护栏（FR-RC-04）', () {
    test('下发间隔 ≤300ms、单次 duration ≤500ms', () {
      expect(AppConfig.rcDispatchIntervalMs <= 300, isTrue);
      expect(AppConfig.rcDurationMs <= 500, isTrue);
    });

    test('默认速度档为最低档，且三档占空比递增', () {
      expect(AppConfig.rcDefaultGearIndex, 0);
      expect(AppConfig.rcGears.length >= 3, isTrue);
      expect(AppConfig.rcGears[0].duty < AppConfig.rcGears[1].duty, isTrue);
      expect(AppConfig.rcGears[1].duty <= AppConfig.rcGears[2].duty, isTrue);
    });
  });
}
