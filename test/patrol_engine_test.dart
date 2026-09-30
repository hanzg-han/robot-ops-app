import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ops_app/core/config/app_config.dart';
import 'package:robot_ops_app/domain/services/patrol_engine.dart';

/// 巡逻状态机单元测试（验收要求：patrol_engine 有单元测试且通过）。
///
/// 覆盖：多点顺序、圈数（含 0 无限 + 护栏）、停留/速度参数、单点超时、
/// 异常中断与「保留已完成进度」。
void main() {
  List<PatrolPoint> pts(int n) => <PatrolPoint>[
        for (var i = 0; i < n; i++) PatrolPoint(name: '点${i + 1}', x: i.toDouble(), y: 0),
      ];

  group('校验与开始条件（FR-PAT-01）', () {
    test('少于 2 个点不可开始', () {
      final engine = PatrolEngine(points: pts(1));
      expect(engine.canStart, isFalse);
      expect(engine.validate(), contains('至少需要 2 个巡逻点'));
      expect(engine.start(), isFalse);
    });

    test('2 个点可以开始', () {
      final engine = PatrolEngine(points: pts(2));
      expect(engine.canStart, isTrue);
      expect(engine.validate(), isNull);
      expect(engine.start(), isTrue);
      expect(engine.state, PatrolRunState.running);
    });

    test('坐标非法的点给出具体行号提示', () {
      final engine = PatrolEngine(points: <PatrolPoint>[
        PatrolPoint(name: 'A', x: 0, y: 0),
        PatrolPoint(name: 'B', x: double.nan, y: 0),
      ]);
      expect(engine.validate(), contains('第 2 点'));
    });

    test('坐标超出合理范围给出提示', () {
      final engine = PatrolEngine(points: <PatrolPoint>[
        PatrolPoint(name: 'A', x: 0, y: 0),
        PatrolPoint(name: 'B', x: 9999, y: 0),
      ]);
      expect(engine.validate(), contains('超出合理范围'));
    });
  });

  group('多点顺序与圈数推进（FR-PAT-03/05）', () {
    test('2 点 × 2 圈：advance 顺序严格为 1-2-1-2，再返回 null', () {
      final engine = PatrolEngine(
        points: pts(2),
        params: PatrolParams(loops: 2),
      );
      engine.start();

      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        final step = engine.advance();
        expect(step, isNotNull);
        seen.add('${step!.loop}-${step.index}');
        engine.markPointDone();
      }
      expect(seen, <String>['1-0', '1-1', '2-0', '2-1']);

      // 第 5 次 advance：跑完所有圈
      final extra = engine.advance();
      expect(extra, isNull);
      expect(engine.state, PatrolRunState.done);
    });

    test('3 点 × 1 圈：每点只下发一次，isLastPointOfLoop 正确', () {
      final engine = PatrolEngine(points: pts(3), params: PatrolParams(loops: 1));
      engine.start();

      final flags = <bool>[];
      for (var i = 0; i < 3; i++) {
        final step = engine.advance()!;
        flags.add(step.isLastPointOfLoop);
        engine.markPointDone();
      }
      expect(flags, <bool>[false, false, true]);
      expect(engine.advance(), isNull);
    });

    test('圈数 0（无限）：受 AppConfig.patrolLoopGuard 护栏保护', () {
      final engine = PatrolEngine(points: pts(2), params: PatrolParams(loops: 0));
      engine.start();
      expect(engine.effectiveLoops, AppConfig.patrolLoopGuard);

      // 推进若干轮仍保持 running（说明护栏远大于实际使用量）
      for (var i = 0; i < 20; i++) {
        engine.advance();
        engine.markPointDone();
      }
      expect(engine.state, PatrolRunState.running);
      expect(engine.currentLoop, greaterThanOrEqualTo(1));
    });

    test('进度与剩余点数（FR-PAT-05）', () {
      final engine = PatrolEngine(points: pts(2), params: PatrolParams(loops: 3));
      engine.start();
      expect(engine.remainingPoints, 6);
      engine.advance();
      engine.markPointDone();
      expect(engine.remainingPoints, 5);
      expect(engine.progress, closeTo(1 / 6, 1e-6));
    });
  });

  group('参数与预计时长（FR-PAT-03/04）', () {
    test('默认值符合 PRD：圈数 1、停留 5000ms、速度比例 0.5、使用点 yaw', () {
      final p = PatrolParams();
      expect(p.loops, 1);
      expect(p.dwellMs, AppConfig.defaultPatrolDwellMs);
      expect(p.dwellMs, 5000);
      expect(p.speedRatio, AppConfig.defaultPatrolSpeedRatio);
      expect(p.usePointYaw, isTrue);
      expect(p.pointTimeoutMs, AppConfig.defaultPatrolPointTimeoutMs);
    });

    test('预计时长随点数与圈数单调增长', () {
      final p = PatrolParams(loops: 2);
      final small = p.estimate(2);
      final big = p.estimate(4);
      expect(big.inMilliseconds > small.inMilliseconds, isTrue);

      final singleLoop = PatrolParams(loops: 1).estimate(2);
      expect(small.inMilliseconds > singleLoop.inMilliseconds, isTrue);
    });

    test('无限模式的预计时长使用护栏值（不会返回 0）', () {
      final p = PatrolParams(loops: 0);
      expect(p.estimate(2).inMilliseconds > 0, isTrue);
    });
  });

  group('停止与异常中断（FR-PAT-07/08/09）', () {
    test('requestStop → stopping，confirmStopped → done', () {
      final engine = PatrolEngine(points: pts(2));
      engine.start();
      engine.requestStop(reason: '用户停止');
      expect(engine.state, PatrolRunState.stopping);
      engine.confirmStopped();
      expect(engine.state, PatrolRunState.done);
      expect(engine.stopReason, '用户停止');
    });

    test('异常中断保留已完成进度（FR-PAT-09）', () {
      final engine = PatrolEngine(points: pts(3), params: PatrolParams(loops: 2));
      engine.start();
      engine.advance();
      engine.markPointDone();
      engine.advance();
      engine.markPointDone();
      final doneBefore = engine.completedPoints;

      engine.failAt(2, '点3', '该目标不可达');
      expect(engine.state, PatrolRunState.aborted);
      expect(engine.failedIndex, 2);
      expect(engine.failedName, '点3');
      expect(engine.stopReason, '该目标不可达');
      // 已完成进度不被清零
      expect(engine.completedPoints, doneBefore);
      expect(engine.completedPoints, 2);
    });

    test('单点超时按「未到达」处理（FR-PAT-08）', () {
      final engine = PatrolEngine(points: pts(2));
      engine.start();
      engine.failAt(0, '点1', '单点超时（未到达）');
      expect(engine.state, PatrolRunState.aborted);
      expect(engine.stopReason, contains('超时'));
    });

    test('停止状态下不再推进', () {
      final engine = PatrolEngine(points: pts(2));
      engine.start();
      engine.requestStop();
      expect(engine.advance(), isNull);
    });

    test('reset 后回到可用状态', () {
      final engine = PatrolEngine(points: pts(2));
      engine.start();
      engine.advance();
      engine.failAt(0, 'x', 'y');
      engine.reset();
      expect(engine.state, PatrolRunState.idle);
      expect(engine.completedPoints, 0);
      expect(engine.canStart, isTrue);
    });

    test('statusLabel 反映当前圈与状态', () {
      final engine = PatrolEngine(points: pts(2), params: PatrolParams(loops: 3));
      engine.start();
      engine.advance();
      expect(engine.statusLabel, contains('1/3'));
      engine.requestStop();
      expect(engine.statusLabel, contains('正在停止'));
    });
  });

  group('批量文本解析（FR-PAT-02）', () {
    test('正常解析 名称,x,y[,yaw]，忽略 # 与空行', () {
      const text = '''
# 这是注释
门诊大厅,1.0,2.0
电梯口,3.5,-4.25,1.5708

三楼检验科,11.93,0.27
''';
      final res = PatrolTextParser.parse(text);
      expect(res.hasErrors, isFalse);
      expect(res.points.length, 3);
      expect(res.points[0].name, '门诊大厅');
      expect(res.points[0].x, 1.0);
      expect(res.points[1].yaw, closeTo(1.5708, 1e-6));
      expect(res.points[2].name, '三楼检验科');
    });

    test('解析失败给出具体行号与原文', () {
      const text = '''
好点,1.0,2.0
坏行只有两段
坏数字,abc,2.0
坏yaw,1.0,2.0,xyz
''';
      final res = PatrolTextParser.parse(text);
      expect(res.points.length, 1);
      expect(res.hasErrors, isTrue);
      expect(res.errors.length, 3);
      // Dart 的多行字符串会去掉开头紧跟 ''' 的换行，故首行为第 1 行
      expect(res.errors[0], contains('第 2 行'));
      expect(res.errors[0], contains('字段不足'));
      expect(res.errors[1], contains('第 3 行'));
      expect(res.errors[1], contains('x 不是数字'));
      expect(res.errors[2], contains('第 4 行'));
      expect(res.errors[2], contains('yaw 不是数字'));
    });

    test('名称为空时自动编号', () {
      final res = PatrolTextParser.parse(',1.0,2.0');
      expect(res.points.single.name, '点 1');
    });

    test('往返序列化保持坐标精度', () {
      final p = PatrolPoint(name: 'A', x: 11.93, y: -0.271, yaw: 1.5708);
      final line = p.toLine();
      final back = PatrolTextParser.parse(line).points.single;
      expect(back.name, 'A');
      expect(back.x, closeTo(11.93, 1e-3));
      expect(back.y, closeTo(-0.271, 1e-3));
      expect(back.yaw, closeTo(1.5708, 1e-3));
    });
  });
}
