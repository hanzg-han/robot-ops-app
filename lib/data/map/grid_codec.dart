import 'dart:typed_data';

/// 栅格地图解析结果（开发文档 §13）。
class GridMap {
  GridMap({
    required this.startX,
    required this.startY,
    required this.width,
    required this.height,
    required this.res,
    required this.cells,
  });

  final double startX;
  final double startY;
  final int width;
  final int height;

  /// 分辨率（m/格，实机 0.05）
  final double res;

  /// 栅格值，行优先（row 0 = 最小 Y）
  final Uint8List cells;

  bool get isUsable => width > 0 && height > 0 && cells.length >= width * height;

  double get minX => startX;
  double get maxX => startX + width * res;
  double get minY => startY;
  double get maxY => startY + height * res;

  /// 地图坐标 → 栅格下标（开发文档 §13.3）
  ///
  /// row = round((y - startY) / res)   —— row 0 对应【最小 Y】
  /// col = round((x - startX) / res)
  ///
  /// 注意：**直接按 row 顺序绘制会导致地图上下颠倒**，绘制时需要垂直翻转一次。
  bool contains(double x, double y) {
    final col = ((x - startX) / res).round();
    final row = ((y - startY) / res).round();
    return col >= 0 && col < width && row >= 0 && row < height;
  }

  /// 取指定地图坐标的栅格值；越界返回 null
  int? valueAt(double x, double y) {
    final col = ((x - startX) / res).round();
    final row = ((y - startY) / res).round();
    if (col < 0 || col >= width || row < 0 || row >= height) return null;
    final idx = row * width + col;
    if (idx < 0 || idx >= cells.length) return null;
    return cells[idx];
  }
}

/// 栅格地图二进制解析（开发文档 §13.1）。
///
/// 偏移 | 类型        | 含义
/// 0    | float32 LE  | startX
/// 4    | float32 LE  | startY
/// 8    | uint32 LE   | width 列数
/// 12   | uint32 LE   | height 行数
/// 16   | float32 LE  | res 分辨率
/// 20-31| —           | 保留
/// 32   | uint32 LE   | dataLen 栅格数据字节数
/// 36…  | uint8 × w×h | 栅格值，行优先
class GridCodec {
  const GridCodec._();

  /// 当前支持的头部长度
  static const int headerLength = 36;

  /// 解析失败原因（FR-MAP-14：给出重试按钮与原因）
  static String? lastError;

  /// 解析二进制地图。失败返回 null，并把原因写入 [lastError]。
  static GridMap? decode(Uint8List bytes) {
    lastError = null;

    if (bytes.lengthInBytes < headerLength) {
      lastError = '地图数据不足（${bytes.lengthInBytes} 字节，至少需要 $headerLength 字节）';
      return null;
    }

    final view = ByteData.sublistView(bytes);
    final startX = view.getFloat32(0, Endian.little);
    final startY = view.getFloat32(4, Endian.little);
    final width = view.getUint32(8, Endian.little);
    final height = view.getUint32(12, Endian.little);
    final resRaw = view.getFloat32(16, Endian.little);
    final dataLen = view.getUint32(32, Endian.little);

    if (width == 0 || height == 0) {
      lastError = '地图尺寸异常（$width × $height）';
      return null;
    }

    // 防御：避免异常尺寸导致内存爆掉（PRD §8.2 地图二进制尺寸异常校验）
    if (width > 20000 || height > 20000) {
      lastError = '地图尺寸超出合理范围（$width × $height）';
      return null;
    }

    final res = (resRaw.isFinite && resRaw > 0) ? resRaw : 0.05;
    final need = width * height;
    final available = bytes.lengthInBytes - headerLength;

    if (dataLen != need) {
      lastError = '栅格数据长度与尺寸不一致（声明 $dataLen，应为 $need）';
      return null;
    }
    if (available < need) {
      lastError = '栅格数据不足（$available/$need 字节）';
      return null;
    }

    final cells = Uint8List.sublistView(bytes, headerLength, headerLength + need);
    return GridMap(
      startX: startX,
      startY: startY,
      width: width,
      height: height,
      res: res,
      cells: cells,
    );
  }

  /// 栅格语义（开发文档 §13.2，4 项实证）
  ///
  /// 127 可通行 / 0 未探索 / 1–126 障碍 / ≥128 其它未知标记
  static GridCellKind kindOf(int value) {
    if (value == 127) return GridCellKind.passable;
    if (value == 0) return GridCellKind.unexplored;
    if (value >= 128) return GridCellKind.unknown;
    return GridCellKind.obstacle;
  }

  /// 绘制用颜色值（ARGB），与 PRD §7.2 地图配色一致。
  static int colorOf(int value) {
    switch (kindOf(value)) {
      case GridCellKind.passable:
        return 0xFFFFFFFF; // 白
      case GridCellKind.unexplored:
        return 0xFFEEF1F5; // 浅灰
      case GridCellKind.obstacle:
        return 0xFF3A4652; // 深灰
      case GridCellKind.unknown:
        return 0xFF8D98A4; // 中灰
    }
  }
}

enum GridCellKind { passable, unexplored, obstacle, unknown }

extension GridCellKindLabel on GridCellKind {
  String get label {
    switch (this) {
      case GridCellKind.passable:
        return '可通行 (127)';
      case GridCellKind.unexplored:
        return '未探索 (0)';
      case GridCellKind.obstacle:
        return '障碍 (1–126)';
      case GridCellKind.unknown:
        return '其它 (≥128)';
    }
  }
}
