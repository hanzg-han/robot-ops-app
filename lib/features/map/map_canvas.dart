import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/dto/models.dart';
import '../../data/map/grid_codec.dart';

/// 地图图层可见性（FR-MAP-11）
class MapLayers {
  MapLayers({
    this.grid = true,
    this.gridLines = true,
    this.trail = true,
    this.laser = false,
    this.poi = true,
    this.dock = true,
    this.walls = true,
    this.route = true,
    this.target = true,
    this.labels = true,
    this.robot = true,
  });

  bool grid;
  bool gridLines;
  bool trail;
  bool laser;
  bool poi;
  bool dock;
  bool walls;
  bool route;
  bool target;
  bool labels;
  bool robot;
}

/// 地图视野（世界坐标范围，单位 m）
class MapViewport {
  MapViewport({required this.x0, required this.y0, required this.x1, required this.y1});

  double x0;
  double y0;
  double x1;
  double y1;

  double get width => (x1 - x0).abs();
  double get height => (y1 - y0).abs();

  MapViewport copy() => MapViewport(x0: x0, y0: y0, x1: x1, y1: y1);
}

/// 栅格位图构建（开发文档 §13）。
///
/// **必须**做一次垂直翻转：数据 row 0 对应**最小 Y**，直接按 row 顺序绘制会上下颠倒
/// （开发文档 §13.3 / §17 坑 2）。
Future<ui.Image> buildGridImage(GridMap g) async {
  final pixels = Uint8List(g.width * g.height * 4);
  for (var row = 0; row < g.height; row++) {
    final srcRow = g.height - 1 - row;
    for (var col = 0; col < g.width; col++) {
      final v = g.cells[srcRow * g.width + col];
      final o = (row * g.width + col) * 4;
      final c = GridCodec.colorOf(v);
      pixels[o] = (c >> 16) & 0xFF;
      pixels[o + 1] = (c >> 8) & 0xFF;
      pixels[o + 2] = c & 0xFF;
      pixels[o + 3] = 0xFF;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: g.width,
    height: g.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// 导航终点标记
class MapNavTarget {
  const MapNavTarget({required this.name, required this.x, required this.y});

  final String name;
  final double x;
  final double y;
}

/// 地图绘制管线（绘制顺序不可乱，PRD §5.3 / 开发文档 §13.4）。
class GridMapPainter extends CustomPainter {
  GridMapPainter({
    required this.gridImage,
    required this.grid,
    required this.viewport,
    required this.layers,
    this.robotPose,
    this.trail = const <List<double>>[],
    this.laserPoints = const <List<double>>[],
    this.pois = const <Poi>[],
    this.docks = const <Dock>[],
    this.walls = const <WallLine>[],
    this.tracks = const <WallLine>[],
    this.routePoints = const <List<double>>[],
    this.patrolRoute = const <List<double>>[],
    this.nextTarget,
    this.navTarget,
    this.repaintTick = 0,
  });

  final ui.Image? gridImage;
  final GridMap? grid;
  final MapViewport viewport;
  final MapLayers layers;
  final Pose? robotPose;
  final List<List<double>> trail;
  final List<List<double>> laserPoints;
  final List<Poi> pois;
  final List<Dock> docks;
  final List<WallLine> walls;
  final List<WallLine> tracks;
  final List<List<double>> routePoints;
  final List<List<double>> patrolRoute;
  final List<double>? nextTarget;
  final MapNavTarget? navTarget;
  final int repaintTick;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = viewport;
    final sx = size.width / (vp.width == 0 ? 1 : vp.width);
    final sy = size.height / (vp.height == 0 ? 1 : vp.height);

    Offset toScreen(double x, double y) =>
        Offset((x - vp.x0) * sx, size.height - (y - vp.y0) * sy);

    // 1. 栅格位图（已垂直翻转）
    final g = grid;
    final img = gridImage;
    if (layers.grid && g != null && img != null && g.isUsable) {
      final dst = Rect.fromLTRB(
        toScreen(g.minX, g.maxY).dx,
        toScreen(g.minX, g.maxY).dy,
        toScreen(g.maxX, g.minY).dx,
        toScreen(g.maxX, g.minY).dy,
      );
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, g.width.toDouble(), g.height.toDouble()),
        Rect.fromLTRB(dst.left, dst.top, dst.right, dst.bottom),
        Paint()..filterQuality = FilterQuality.low,
      );
    }

    // 2. 5m 网格线（FR-MAP-12）
    if (layers.gridLines) _paintGridLines(canvas, size, toScreen, vp);

    // 3. 激光点（青色，限流 4s）
    if (layers.laser && laserPoints.isNotEmpty) {
      final paint = Paint()..color = AppColors.laser;
      for (final p in laserPoints) {
        canvas.drawCircle(toScreen(p[0], p[1]), 1.2, paint);
      }
    }

    // 4. 行走轨迹（橙色折线）
    if (layers.trail && trail.length > 1) {
      _paintPolyline(
        canvas,
        trail,
        toScreen,
        Paint()
          ..color = AppColors.trail
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    }

    // 5. 巡逻整路线（浅橙虚线 + 节点）
    if (layers.route && patrolRoute.length > 1) {
      for (var i = 1; i < patrolRoute.length; i++) {
        _paintDashed(
          canvas,
          toScreen(patrolRoute[i - 1][0], patrolRoute[i - 1][1]),
          toScreen(patrolRoute[i][0], patrolRoute[i][1]),
          AppColors.patrolRoute,
          1.6,
        );
      }
      for (final p in patrolRoute) {
        canvas.drawCircle(toScreen(p[0], p[1]), 3, Paint()..color = AppColors.patrolRoute);
      }
    }

    // 6. 规划路径（蓝色虚线 + 终点圆点）
    if (layers.route && routePoints.length > 1) {
      for (var i = 1; i < routePoints.length; i++) {
        _paintDashed(
          canvas,
          toScreen(routePoints[i - 1][0], routePoints[i - 1][1]),
          toScreen(routePoints[i][0], routePoints[i][1]),
          AppColors.route,
          2.0,
        );
      }
      final last = routePoints.last;
      canvas.drawCircle(toScreen(last[0], last[1]), 3.5, Paint()..color = AppColors.route);
    }

    // 7. 巡逻下一目标（十字）
    final nt = nextTarget;
    if (layers.target && nt != null) {
      _paintCross(canvas, toScreen(nt[0], nt[1]), AppColors.patrolSegment);
    }

    // 8. 导航终点（十字 + 白心 + 标签，始终在最上层目标标记）
    final nav = navTarget;
    if (layers.target && nav != null) {
      final o = toScreen(nav.x, nav.y);
      _paintCross(canvas, o, AppColors.navTarget, whiteCenter: true);
      if (layers.labels) _paintLabel(canvas, o, nav.name, AppColors.navTarget, size);
    }

    // 9. 虚拟墙（红实线）/ 虚拟轨道（青虚线）
    if (layers.walls) {
      for (final w in walls) {
        canvas.drawLine(
          toScreen(w.x1, w.y1),
          toScreen(w.x2, w.y2),
          Paint()
            ..color = AppColors.wall
            ..strokeWidth = 2,
        );
      }
      for (final t in tracks) {
        _paintDashed(
          canvas,
          toScreen(t.x1, t.y1),
          toScreen(t.x2, t.y2),
          AppColors.track,
          1.6,
        );
      }
    }

    // 10. POI（紫）/ 充电桩（红）
    if (layers.poi) {
      for (final p in pois) {
        final o = toScreen(p.pose.x, p.pose.y);
        canvas.drawCircle(o, 4, Paint()..color = AppColors.poi);
        canvas.drawCircle(
          o,
          4,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke,
        );
        if (layers.labels) _paintLabel(canvas, o, p.displayName, AppColors.poi, size);
      }
    }
    if (layers.dock) {
      for (final d in docks) {
        final o = toScreen(d.pose.x, d.pose.y);
        final path = Path()
          ..moveTo(o.dx, o.dy - 5)
          ..lineTo(o.dx + 5, o.dy)
          ..lineTo(o.dx, o.dy + 5)
          ..lineTo(o.dx - 5, o.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = AppColors.dock);
        if (layers.labels) _paintLabel(canvas, o, d.displayName, AppColors.dock, size);
      }
    }

    // 11. 机器人箭头（最上层，永不被遮挡）
    final pose = robotPose;
    if (layers.robot && pose != null) {
      _paintRobot(canvas, toScreen(pose.x, pose.y), pose.yaw);
    }

    // 12. 比例尺（右下角，随缩放变化）
    _paintScaleBar(canvas, size, sx);
  }

  void _paintGridLines(
    Canvas canvas,
    Size size,
    Offset Function(double, double) toScreen,
    MapViewport vp,
  ) {
    const step = 5.0;
    final paint = Paint()
      ..color = const Color(0x331F4E79)
      ..strokeWidth = 0.8;
    final startX = (vp.x0 / step).floor() * step;
    final startY = (vp.y0 / step).floor() * step;

    for (var x = startX; x <= vp.x1 + step; x += step) {
      final o = toScreen(x, vp.y0);
      canvas.drawLine(Offset(o.dx, 0), Offset(o.dx, size.height), paint);
    }
    for (var y = startY; y <= vp.y1 + step; y += step) {
      final o = toScreen(vp.x0, y);
      canvas.drawLine(Offset(0, o.dy), Offset(size.width, o.dy), paint);
    }
  }

  void _paintPolyline(
    Canvas canvas,
    List<List<double>> pts,
    Offset Function(double, double) toScreen,
    Paint paint,
  ) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = toScreen(pts[i][0], pts[i][1]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintDashed(Canvas canvas, Offset a, Offset b, Color color, double width) {
    const dash = 6.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final t2 = (t + dash) > total ? total : (t + dash);
      canvas.drawLine(a + dir * t, a + dir * t2, paint);
      t = t2 + dash * 0.6;
    }
  }

  void _paintCross(Canvas canvas, Offset o, Color color, {bool whiteCenter = false}) {
    const r = 9.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4;
    canvas.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), paint);
    canvas.drawLine(Offset(o.dx, o.dy - r), Offset(o.dx, o.dy + r), paint);
    if (whiteCenter) {
      canvas.drawCircle(o, 2.4, Paint()..color = Colors.white);
    }
  }

  void _paintRobot(Canvas canvas, Offset o, double yaw) {
    canvas.save();
    canvas.translate(o.dx, o.dy);
    // 屏幕 Y 轴向下，世界 yaw 逆时针为正 → 旋转取 -yaw
    canvas.rotate(-yaw);
    final body = Path()
      ..moveTo(9, 0)
      ..lineTo(-6, 6)
      ..lineTo(-3, 0)
      ..lineTo(-6, -6)
      ..close();
    canvas.drawPath(body, Paint()..color = AppColors.robot);
    canvas.drawCircle(Offset.zero, 2, Paint()..color = Colors.white);
    canvas.restore();
  }

  void _paintLabel(Canvas canvas, Offset o, String text, Color color, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);

    final rect = Rect.fromLTWH(o.dx + 6, o.dy - 16, tp.width + 8, tp.height + 4);
    final clamped = rect.shift(Offset(
      rect.right > size.width ? size.width - rect.right - 2 : 0,
      rect.top < 0 ? -rect.top + 2 : 0,
    ));
    canvas.drawRRect(
      RRect.fromRectAndRadius(clamped, const Radius.circular(3)),
      Paint()..color = color.withOpacity(0.86),
    );
    tp.paint(canvas, Offset(clamped.left + 4, clamped.top + 2));
  }

  /// 比例尺（FR-MAP-12：缩放时长度正确变化）
  void _paintScaleBar(Canvas canvas, Size size, double pxPerMeter) {
    if (pxPerMeter <= 0) return;
    final target = 70 / pxPerMeter;
    final pow = _pow10(_digits(target));
    final candidates = <double>[1 * pow, 2 * pow, 5 * pow, 10 * pow];
    var meters = candidates.first;
    for (final c in candidates) {
      if (c * pxPerMeter <= 92) meters = c;
    }
    final lengthPx = meters * pxPerMeter;

    const margin = 12.0;
    final y = size.height - margin;
    final x1 = size.width - margin;
    final x0 = x1 - lengthPx;

    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
    canvas.drawLine(Offset(x0, y - 4), Offset(x0, y + 4), paint);
    canvas.drawLine(Offset(x1, y - 4), Offset(x1, y + 4), paint);

    final tp = TextPainter(
      text: TextSpan(
        text: meters >= 1000
            ? '${(meters / 1000).toStringAsFixed(1)} km'
            : '${meters.toStringAsFixed(0)} m',
        style: const TextStyle(fontSize: 10, color: AppColors.primary),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((x0 + x1) / 2 - tp.width / 2, y - 17));
  }

  /// target 的十进制位数（用于取 1/2/5 × 10^n 的整数量级）
  static int _digits(double v) {
    final abs = v.abs();
    if (abs >= 1) return abs.floor().toString().length - 1;
    if (abs >= 0.1) return -1;
    if (abs >= 0.01) return -2;
    if (abs >= 0.001) return -3;
    return -4;
  }

  static double _pow10(int exp) {
    var v = 1.0;
    if (exp >= 0) {
      for (var i = 0; i < exp; i++) {
        v *= 10;
      }
    } else {
      for (var i = 0; i < -exp; i++) {
        v /= 10;
      }
    }
    return v;
  }

  @override
  bool shouldRepaint(GridMapPainter oldDelegate) =>
      oldDelegate.repaintTick != repaintTick ||
      oldDelegate.gridImage != gridImage ||
      oldDelegate.grid != grid ||
      oldDelegate.viewport.x0 != viewport.x0 ||
      oldDelegate.viewport.y0 != viewport.y0 ||
      oldDelegate.viewport.x1 != viewport.x1 ||
      oldDelegate.viewport.y1 != viewport.y1;
}
