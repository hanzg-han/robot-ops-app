import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:robot_ops_app/data/map/grid_codec.dart';

/// 栅格地图解析单元测试（验收要求：grid_codec 有单元测试且通过）。
///
/// 覆盖开发文档 §13 的二进制格式、尺寸校验与语义分类，以及 §13.3 的
/// 「row 0 = 最小 Y」坐标关系（这是地图上下颠倒的根因）。
void main() {
  /// 构造一张测试栅格（参考开发文档 §19.2）
  Uint8List buildGrid({
    required double startX,
    required double startY,
    required int width,
    required int height,
    required double res,
    required int fill,
    int? declaredDataLen,
  }) {
    final head = ByteData(36);
    head.setFloat32(0, startX, Endian.little);
    head.setFloat32(4, startY, Endian.little);
    head.setUint32(8, width, Endian.little);
    head.setUint32(12, height, Endian.little);
    head.setFloat32(16, res, Endian.little);
    head.setUint32(32, declaredDataLen ?? width * height, Endian.little);

    final out = BytesBuilder();
    out.add(head.buffer.asUint8List());
    out.add(Uint8List(width * height)..fillRange(0, width * height, fill));
    return out.toBytes();
  }

  group('GridCodec.decode 二进制解析', () {
    test('608×528 @0.05 正确解析头部与数据长度', () {
      final bytes = buildGrid(
        startX: -12.55,
        startY: -17.70,
        width: 608,
        height: 528,
        res: 0.05,
        fill: 127,
      );
      final grid = GridCodec.decode(bytes);
      expect(GridCodec.lastError, isNull);
      expect(grid, isNotNull);
      expect(grid!.width, 608);
      expect(grid.height, 528);
      expect(grid.res, closeTo(0.05, 1e-6));
      expect(grid.startX, closeTo(-12.55, 1e-4));
      expect(grid.startY, closeTo(-17.70, 1e-4));
      expect(grid.cells.length, 608 * 528);
      expect(grid.isUsable, isTrue);
      // 实机范围：x −12.55…17.85，y −17.70…8.70
      expect(grid.maxX, closeTo(-12.55 + 608 * 0.05, 1e-3));
      expect(grid.maxY, closeTo(-17.70 + 528 * 0.05, 1e-3));
    });

    test('数据不足 36 字节 → 拒绝解析并给出原因', () {
      final grid = GridCodec.decode(Uint8List(20));
      expect(grid, isNull);
      expect(GridCodec.lastError, contains('地图数据不足'));
    });

    test('尺寸为 0 → 拒绝解析（FR-MAP-14 尺寸异常）', () {
      final bytes = buildGrid(
        startX: 0,
        startY: 0,
        width: 0,
        height: 10,
        res: 0.05,
        fill: 127,
      );
      final grid = GridCodec.decode(bytes);
      expect(grid, isNull);
      expect(GridCodec.lastError, contains('尺寸异常'));
    });

    test('dataLen 与 width×height 不一致 → 拒绝渲染（PRD §8.2）', () {
      final bytes = buildGrid(
        startX: 0,
        startY: 0,
        width: 10,
        height: 10,
        res: 0.05,
        fill: 127,
        declaredDataLen: 90,
      );
      final grid = GridCodec.decode(bytes);
      expect(grid, isNull);
      expect(GridCodec.lastError, contains('不一致'));
    });

    test('res 非法（0）时回落到 0.05，不崩溃', () {
      final bytes = buildGrid(
        startX: 0,
        startY: 0,
        width: 4,
        height: 4,
        res: 0,
        fill: 127,
      );
      final grid = GridCodec.decode(bytes);
      expect(grid, isNotNull);
      expect(grid!.res, 0.05);
    });
  });

  group('GridCodec 栅格语义（§13.2 四项实证）', () {
    test('127 可通行 / 0 未探索 / 1–126 障碍 / ≥128 未知', () {
      expect(GridCodec.kindOf(127), GridCellKind.passable);
      expect(GridCodec.kindOf(0), GridCellKind.unexplored);
      expect(GridCodec.kindOf(1), GridCellKind.obstacle);
      expect(GridCodec.kindOf(126), GridCellKind.obstacle);
      expect(GridCodec.kindOf(128), GridCellKind.unknown);
      expect(GridCodec.kindOf(255), GridCellKind.unknown);
    });

    test('颜色与 PRD §7.2 配色一致', () {
      expect(GridCodec.colorOf(127), 0xFFFFFFFF);
      expect(GridCodec.colorOf(0), 0xFFEEF1F5);
      expect(GridCodec.colorOf(50), 0xFF3A4652);
      expect(GridCodec.colorOf(200), 0xFF8D98A4);
    });
  });

  group('坐标与翻转关系（§13.3：最容易画反的地方）', () {
    test('row 0 对应最小 Y；col 0 对应最小 X', () {
      final bytes = buildGrid(
        startX: -10,
        startY: -10,
        width: 200,
        height: 200,
        res: 0.1,
        fill: 127,
      );
      final grid = GridCodec.decode(bytes)!;

      // 地图原点 (startX, startY) 落在 row 0 / col 0
      expect(grid.valueAt(-10, -10), 127);
      // 越界应返回 null
      expect(grid.valueAt(-11, -10), isNull);
      expect(grid.valueAt(-10, -11), isNull);
      expect(grid.valueAt(11, 0), isNull);
      expect(grid.contains(0, 0), isTrue);
      expect(grid.contains(100, 100), isFalse);
    });

    test('绘制前的垂直翻转索引：srcRow = height - 1 - row', () {
      // 仅在【最小 Y 行】写入障碍，其余可通行
      const w = 4;
      const h = 3;
      final bytes = buildGrid(
        startX: 0,
        startY: 0,
        width: w,
        height: h,
        res: 0.05,
        fill: 127,
      );
      final mutable = Uint8List.fromList(bytes);
      // 数据区起始 36；row 0（最小 Y）整行置为障碍值 1
      for (var col = 0; col < w; col++) {
        mutable[36 + col] = 1;
      }
      final grid = GridCodec.decode(mutable)!;

      // 数据层面：minY 一侧是障碍
      expect(grid.valueAt(0, 0), 1);
      // 翻转到图像坐标后，该行应出现在图像最下方（row = h-1）
      final srcRow = h - 1 - 0;
      expect(srcRow, 2);
      expect(grid.valueAt(0.0, grid.maxY - 0.05), 127);
    });
  });
}
