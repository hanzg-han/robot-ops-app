import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ops_app/core/network/api_client.dart';
import 'package:robot_ops_app/core/network/api_endpoints.dart';

/// 安全与工程红线测试（PRD §4.10 FR-SAFE-01~07 / §10.1 安全边界 / §11.2 工程验收）。
///
/// 这些断言用于在 CI 中**自动**防止实现漂移：
/// - 地址规范化规则（FR-CON-01 / 开发文档 §8.1）；
/// - 路径常量必须与开发文档 §10 完全一致（含 `:current` / `:search_path` 字面量）；
/// - 代码库中不得存在 Mock / 假数据源（FR-CON-10 / FR-SAFE-05）；
/// - 遥控「进入确认一次」是唯一例外，不得被其他移动入口复用（FR-SAFE-07）。
void main() {
  group('地址规范化（FR-CON-01 / 开发文档 §8.1）', () {
    test('裸 IP:端口 自动补 http://', () {
      expect(ApiClient.normalizeBase('192.168.0.16:1448'), 'http://192.168.0.16:1448');
    });

    test('带协议与结尾斜杠被规范化', () {
      expect(ApiClient.normalizeBase('  http://192.168.0.16:1448/  '), 'http://192.168.0.16:1448');
      expect(ApiClient.normalizeBase('http://192.168.0.16:1448///'), 'http://192.168.0.16:1448');
    });

    test('首尾空白被去除', () {
      expect(ApiClient.normalizeBase('\t 10.0.0.5:1448 \n'), 'http://10.0.0.5:1448');
    });

    test('空地址回落到默认地址', () {
      expect(ApiClient.normalizeBase(''), 'http://192.168.0.16:1448');
      expect(ApiClient.normalizeBase(null), 'http://192.168.0.16:1448');
      expect(ApiClient.normalizeBase('   '), 'http://192.168.0.16:1448');
    });

    test('两种写法规范化后一致（验收：两种写法均能连上）', () {
      final a = ApiClient.normalizeBase('192.168.0.16:1448');
      final b = ApiClient.normalizeBase('  http://192.168.0.16:1448/ ');
      expect(a, b);
    });
  });

  group('路径常量与开发文档 §10 一致（事实来源约束）', () {
    test('系统 / 电源 / 健康', () {
      expect(ApiEndpoints.capabilities, '/api/core/system/v1/capabilities');
      expect(ApiEndpoints.powerStatus, '/api/core/system/v1/power/status');
      expect(ApiEndpoints.robotInfo, '/api/core/system/v1/robot/info');
      expect(ApiEndpoints.robotHealth, '/api/core/system/v1/robot/health');
      expect(ApiEndpoints.odometry, '/api/core/statistics/v1/odometry');
      expect(ApiEndpoints.laserscan, '/api/core/system/v1/laserscan');
    });

    test('行为与运动：:current 与 :search_path 是字面量而非占位符', () {
      expect(ApiEndpoints.actions, '/api/core/motion/v1/actions');
      expect(ApiEndpoints.currentAction, '/api/core/motion/v1/actions/:current');
      expect(ApiEndpoints.actionFactories, '/api/core/motion/v1/action-factories');
      expect(ApiEndpoints.searchPath, '/api/core/motion/v1/:search_path');
      expect(ApiEndpoints.speed, '/api/core/motion/v1/speed');
      expect(ApiEndpoints.strategies, '/api/core/motion/v1/strategies/:current');
    });

    test('定位与地图', () {
      expect(ApiEndpoints.pose, '/api/core/slam/v1/localization/pose');
      expect(ApiEndpoints.quality, '/api/core/slam/v1/localization/quality');
      expect(ApiEndpoints.localizationEnable, '/api/core/slam/v1/localization/:enable');
      expect(ApiEndpoints.mapGrid, '/api/core/slam/v1/maps/explore');
      expect(ApiEndpoints.homepose, '/api/core/slam/v1/homepose');
      expect(ApiEndpoints.homedocks, '/api/core/slam/v1/homedocks');
      expect(ApiEndpoints.dockRegister, '/api/core/slam/v1/homedocks/:register');
    });

    test('POI / 虚拟墙 / 事件 / 时间', () {
      expect(ApiEndpoints.pois, '/api/core/artifact/v1/pois');
      expect(ApiEndpoints.walls, '/api/core/artifact/v1/lines/walls');
      expect(ApiEndpoints.tracks, '/api/core/artifact/v1/lines/tracks');
      expect(ApiEndpoints.events, '/api/platform/v1/events');
      expect(ApiEndpoints.machineTimestamp, '/api/platform/v1/timestamp');
    });

    test('遥控相关：建图开关与保存地图（:enable / :save 为字面量）', () {
      expect(ApiEndpoints.mappingEnable, '/api/core/slam/v1/mapping/:enable');
      expect(ApiEndpoints.saveStcm, '/api/core/multi-floor/map/v1/stcm/:save');
    });

    test('所有路径必须以 /api/ 开头（局域网直连前缀）', () {
      for (final p in <String>[
        ApiEndpoints.capabilities,
        ApiEndpoints.powerStatus,
        ApiEndpoints.robotInfo,
        ApiEndpoints.robotHealth,
        ApiEndpoints.parameter,
        ApiEndpoints.odometry,
        ApiEndpoints.laserscan,
        ApiEndpoints.actions,
        ApiEndpoints.currentAction,
        ApiEndpoints.actionFactories,
        ApiEndpoints.strategies,
        ApiEndpoints.speed,
        ApiEndpoints.searchPath,
        ApiEndpoints.pose,
        ApiEndpoints.quality,
        ApiEndpoints.localizationEnable,
        ApiEndpoints.mapGrid,
        ApiEndpoints.homepose,
        ApiEndpoints.homedocks,
        ApiEndpoints.dockRegister,
        ApiEndpoints.pois,
        ApiEndpoints.walls,
        ApiEndpoints.tracks,
        ApiEndpoints.events,
        ApiEndpoints.machineTimestamp,
        ApiEndpoints.mappingEnable,
        ApiEndpoints.saveStcm,
      ]) {
        expect(p.startsWith('/api/'), isTrue, reason: '$p 应以 /api/ 开头');
      }
    });

    test('动作名末段常量与接口枚举一致', () {
      expect(ApiEndpoints.suffixMoveTo, 'MoveToAction');
      expect(ApiEndpoints.suffixRotateTo, 'RotateToAction');
      expect(ApiEndpoints.suffixGoHome, 'GoHomeAction');
      expect(ApiEndpoints.suffixMoveBy, 'MoveByAction');
    });
  });

  group('FR-CON-10 / FR-SAFE-05：代码库中不得存在 Mock 数据源', () {
    test('lib 下不存在 mock/fake 数据源文件', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib 目录应存在（在工程根目录运行测试）');

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lower = entity.path.toLowerCase();
        // 允许出现「不使用 Mock」这类说明性注释，但不得存在 mock/fake 命名的文件
        if (lower.contains('mock') || lower.contains('fake_data')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: '发现疑似 Mock 数据源：$offenders');
    });

    test('lib 下不存在可切换到假数据的开关标识', () {
      final libDir = Directory('lib');
      final patterns = <RegExp>[
        RegExp(r'useMock', caseSensitive: false),
        RegExp(r'mockMode', caseSensitive: false),
        RegExp(r'fakeDataSource', caseSensitive: false),
        RegExp(r'enableMock', caseSensitive: false),
      ];

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        for (final re in patterns) {
          if (re.hasMatch(content)) {
            offenders.add('${entity.path} :: ${re.pattern}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '发现疑似 Mock 开关：$offenders');
    });
  });

  group('FR-SAFE-07：遥控「进入确认一次」不得被复用', () {
    test('只有遥控页面调用 confirmRemoteEntry', () {
      final libDir = Directory('lib');
      final callers = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('confirmRemoteEntry(')) {
          callers.add(entity.path.replaceAll(r'\', '/'));
        }
      }
      // 定义处 1 个（confirm_danger.dart）+ 调用处 1 个（map_page.dart）
      expect(
        callers.any((c) => c.endsWith('shared/widgets/confirm_danger.dart')),
        isTrue,
        reason: 'confirmRemoteEntry 应在 confirm_danger.dart 中定义',
      );
      expect(
        callers.where((c) => c.endsWith('features/map/map_page.dart')).length,
        1,
        reason: '遥控进入确认应只在地图页（遥控入口）调用一次',
      );
      expect(
        callers.length,
        2,
        reason: '除定义与地图页入口外，不得有第三处使用该例外确认：$callers',
      );
    });

    test('移动类下发的二次确认统一走 ConfirmDanger.show', () {
      final offenders = <String>[];
      for (final path in <String>[
        'lib/features/dashboard/dashboard_page.dart',
        'lib/features/tasks/tasks_page.dart',
        'lib/features/map/map_page.dart',
        'lib/features/settings/dock_page.dart',
        'lib/features/remote/remote_control_page.dart',
      ]) {
        final f = File(path);
        if (!f.existsSync()) {
          offenders.add('$path（文件缺失）');
          continue;
        }
        if (!f.readAsStringSync().contains('ConfirmDanger.show')) {
          offenders.add('$path（未使用统一确认组件）');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('；'));
    });

    test('API 客户端不使用硬编码的 slamtec.agent.actions 前缀', () {
      final offenders = <String>[];
      final libDir = Directory('lib');
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        // 仅允许在注释/文档中提及；不得作为字符串字面量使用
        if (content.contains("'slamtec.agent.actions.") ||
            content.contains('"slamtec.agent.actions.')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: '不得硬编码官方前缀（实机只认 agent.actions.*）：$offenders');
    });
  });
}
