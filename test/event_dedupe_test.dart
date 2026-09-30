import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ops_app/domain/models/event_catalog.dart';
import 'package:robot_ops_app/domain/services/event_dedupe.dart';

/// 事件去重 / 级别推断 / 时间换算单元测试（FR-EVT-01~06）。
void main() {
  group('三种响应结构兼容（FR-EVT-01）', () {
    test('数组结构', () {
      final list = EventDedupe.parseEvents(<dynamic>[
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': 1000},
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 2000},
      ]);
      expect(list.length, 2);
      expect(list.first.type, 'ON_DOCK');
      expect(list.first.timestamp, 1000);
    });

    test('{events:[…]} 结构', () {
      final list = EventDedupe.parseEvents(<String, dynamic>{
        'events': <dynamic>[
          <String, dynamic>{'type': 'DEVICE_ERROR', 'timestamp': 3000},
        ],
      });
      expect(list.length, 1);
      expect(list.single.type, 'DEVICE_ERROR');
    });

    test('单对象结构', () {
      final list = EventDedupe.parseEvents(<String, dynamic>{
        'type': 'START_CHARGING',
        'timestamp': 4000,
      });
      expect(list.length, 1);
    });

    test('timestamp 为字符串数字时也能解析', () {
      final list = EventDedupe.parseEvents(<dynamic>[
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': '1500'},
      ]);
      expect(list.single.timestamp, 1500);
    });

    test('缺失 type 或 timestamp 的条目被丢弃', () {
      final list = EventDedupe.parseEvents(<dynamic>[
        <String, dynamic>{'timestamp': 1},
        <String, dynamic>{'type': 'ON_DOCK'},
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': 2},
      ]);
      expect(list.length, 1);
    });
  });

  group('去重（FR-EVT-03 / 开发文档 §15.2）', () {
    test('同一 type#timestamp 只入列一次，不重复弹', () {
      final dedupe = EventDedupe();
      final raw = <dynamic>[
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 1000},
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 1000},
      ];
      final fresh1 = dedupe.merge(raw);
      expect(fresh1.length, 1);
      expect(dedupe.length, 1);

      // 再次轮询到同一批事件：不新增
      final fresh2 = dedupe.merge(raw);
      expect(fresh2, isEmpty);
      expect(dedupe.length, 1);
    });

    test('同 type 但 timestamp 不同视为不同事件', () {
      final dedupe = EventDedupe();
      dedupe.merge(<dynamic>[
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 1000},
      ]);
      final fresh = dedupe.merge(<dynamic>[
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 2000},
      ]);
      expect(fresh.length, 1);
      expect(dedupe.length, 2);
    });

    test('连续多轮轮询列表长度稳定不膨胀', () {
      final dedupe = EventDedupe();
      final raw = <dynamic>[
        for (var i = 0; i < 5; i++)
          <String, dynamic>{'type': 'ON_DOCK', 'timestamp': i * 100},
      ];
      for (var round = 0; round < 10; round++) {
        dedupe.merge(raw);
      }
      expect(dedupe.length, 5);
    });

    test('容量上限：超出滚动丢弃最早条目（FR-EVT-09）', () {
      final dedupe = EventDedupe(capacity: 10);
      for (var i = 0; i < 25; i++) {
        dedupe.merge(<dynamic>[
          <String, dynamic>{'type': 'ON_DOCK', 'timestamp': i},
        ]);
      }
      expect(dedupe.length, 10);
      // 最新在前
      expect(dedupe.events.first.timestamp, 24);
    });

    test('时间倒序排列', () {
      final dedupe = EventDedupe();
      dedupe.merge(<dynamic>[
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': 100},
        <String, dynamic>{'type': 'OFF_DOCK', 'timestamp': 300},
        <String, dynamic>{'type': 'START_CHARGING', 'timestamp': 200},
      ]);
      expect(dedupe.events.map((e) => e.timestamp).toList(), <double>[300, 200, 100]);
    });

    test('未读计数与最高级别（铃铛徽标着色）', () {
      final dedupe = EventDedupe();
      dedupe.merge(<dynamic>[
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': 1}, // info
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 2}, // warning
        <String, dynamic>{'type': 'DEVICE_ERROR', 'timestamp': 3}, // error
      ]);
      expect(dedupe.unreadCount, 3);
      expect(dedupe.highestUnreadLevel, EventLevel.error);

      dedupe.markAllRead();
      expect(dedupe.unreadCount, 0);
      expect(dedupe.highestUnreadLevel, isNull);
    });

    test('clearRead 只清本地已读记录，保留未读（FR-EVT-07）', () {
      final dedupe = EventDedupe();
      dedupe.merge(<dynamic>[
        <String, dynamic>{'type': 'ON_DOCK', 'timestamp': 1},
        <String, dynamic>{'type': 'PATH_OCCUPIED', 'timestamp': 2},
      ]);
      // events 按时间倒序：first = PATH_OCCUPIED(2, 警告)，last = ON_DOCK(1, 信息)
      // 把「信息」那条标记为已读，清空后应保留未读的「警告」那条
      dedupe.events.last.read = true;
      dedupe.clearRead();
      expect(dedupe.length, 1);
      expect(dedupe.events.single.type, 'PATH_OCCUPIED');
      expect(dedupe.events.single.level, EventLevel.warning);
    });
  });

  group('级别与中文说明（FR-EVT-04 / 开发文档 §15.3）', () {
    test('表中类型级别正确', () {
      expect(EventCatalog.levelOf('PATH_OCCUPIED'), EventLevel.warning);
      expect(EventCatalog.levelOf('WAIT_PLANNING_FAILED'), EventLevel.error);
      expect(EventCatalog.levelOf('ON_DOCK'), EventLevel.info);
      expect(EventCatalog.levelOf('LOW_BATTERY'), EventLevel.warning);
      expect(EventCatalog.levelOf('CLIFF_DETECTED'), EventLevel.error);
    });

    test('未收录类型按关键词推断：FAIL|ERROR|FAULT|_ANOMALY → 错误', () {
      expect(EventCatalog.levelOf('SOMETHING_FAILED'), EventLevel.error);
      expect(EventCatalog.levelOf('FOO_ERROR'), EventLevel.error);
      expect(EventCatalog.levelOf('BAR_ANOMALY'), EventLevel.error);
      expect(EventCatalog.levelOf('NEW_FAULT_X'), EventLevel.error);
    });

    test('未收录类型按关键词推断：OCCUPIED|BLOCK|LOW_|WARN|RETRY|REBOOT → 警告', () {
      expect(EventCatalog.levelOf('NEW_OCCUPIED_EVENT'), EventLevel.warning);
      expect(EventCatalog.levelOf('X_BLOCK_Y'), EventLevel.warning);
      expect(EventCatalog.levelOf('LOW_SOMETHING'), EventLevel.warning);
      expect(EventCatalog.levelOf('MY_WARN'), EventLevel.warning);
      expect(EventCatalog.levelOf('RETRY_TASK'), EventLevel.warning);
      expect(EventCatalog.levelOf('AUTO_REBOOT'), EventLevel.warning);
    });

    test('其余 → 信息', () {
      expect(EventCatalog.levelOf('SOME_UNKNOWN_THING'), EventLevel.info);
    });

    test('中文说明已内置，未收录时显示原文提示', () {
      expect(EventCatalog.describe('PATH_OCCUPIED'), '行进路径被阻挡');
      expect(EventCatalog.describe('MOVE_TO_LANDING_POINT_FAILED'), '前往充电桩失败');
      expect(EventCatalog.isKnown('ON_DOCK'), isTrue);
      expect(EventCatalog.isKnown('SOME_UNKNOWN_THING'), isFalse);
      expect(EventCatalog.describe('SOME_UNKNOWN_THING'), contains('未收录'));
    });

    test('事件目录覆盖开发文档 §15.3 关键类型（抽样）', () {
      for (final t in <String>[
        'DEVICE_ERROR',
        'WAIT_PLANNING_FAILED',
        'MOVE_TO_LANDING_POINT_FAILED',
        'SEARCH_DOCK_FAILED',
        'CHARGING_BASE_FAILED',
        'DOCK_ID_NOT_FOUND',
        'LOCALIZATION_ANOMALY',
        'ROBOT_BLOCKED',
        'BUMPER_TRIGGERED',
        'START_CHARGING',
        'STOP_CHARGING',
        'OFF_DOCK',
        'RESET_MAP_TO_DOCK',
      ]) {
        expect(EventCatalog.isKnown(t), isTrue, reason: '$t 应已内置中文说明');
      }
    });
  });

  group('事件→动作联动建议（FR-EVT-08）', () {
    test('回充类失败 → 重试回充', () {
      final s = EventCatalog.suggestionOf('MOVE_TO_LANDING_POINT_FAILED');
      expect(s, isNotNull);
      expect(s!.kind, SuggestionKind.goHome);
    });

    test('被阻挡类 → 终止行为', () {
      final s = EventCatalog.suggestionOf('PATH_OCCUPIED');
      expect(s, isNotNull);
      expect(s!.kind, SuggestionKind.abort);
    });

    test('无建议的类型返回 null（不自动执行任何动作）', () {
      expect(EventCatalog.suggestionOf('ON_DOCK'), isNull);
    });
  });
}
