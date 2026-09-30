import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/num_fmt.dart';
import '../../data/dto/models.dart';
import '../../data/map/grid_codec.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';
import '../remote/remote_control_page.dart';
import 'map_canvas.dart';

/// P02 地图 + P03 选点面板（PRD §5.3 / §5.4；FR-MAP-01~15、FR-NAV-04~07）。
///
/// 关键约束：
/// - 地图二进制**按需加载**（不进 2s 轮询），停留地图页 60s 时 maps/explore 请求数为 1；
/// - 激光限流 4s；
/// - 有导航/巡逻目标时用 fitPoints 取景，确保机器人、目标、路径同时在屏内；
/// - 所有目标入口走同一 showRouteTo 逻辑。
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.services,
    required this.gate,
    required this.navigation,
    required this.patrol,
    required this.remote,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;
  final PatrolController patrol;
  final RemoteControlController remote;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapLayers _layers = MapLayers();
  late MapViewport _viewport;

  GridMap? _grid;
  ui.Image? _gridImage;
  String? _mapError;
  bool _mapLoading = false;

  final List<List<double>> _trail = <List<double>>[];
  List<List<double>> _laserPoints = <List<double>>[];
  DateTime? _lastLaserAt;

  Timer? _trailTimer;
  bool _legendExpanded = false;

  /// 巡逻/遥控期间地图自动刷新（FR-RC-11）
  Timer? _mappingRefreshTimer;

  @override
  void initState() {
    super.initState();
    _viewport = MapViewport(x0: -15, y0: -15, x1: 15, y1: 15);
    widget.services.state.addListener(_onState);
    widget.remote.addListener(_onState);
    widget.patrol.addListener(_onState);
    widget.navigation.addListener(_onState);

    // 首次加载地图（按需，不进轮询）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadMap();
    });
    // 轨迹按 0.05m 采样累积
    _trailTimer = Timer.periodic(const Duration(seconds: 1), (_) => _appendTrail());
    widget.remote.addListener(_syncMappingRefresh);
  }

  @override
  void dispose() {
    _trailTimer?.cancel();
    _mappingRefreshTimer?.cancel();
    widget.remote.removeListener(_syncMappingRefresh);
    widget.services.state.removeListener(_onState);
    widget.remote.removeListener(_onState);
    widget.patrol.removeListener(_onState);
    widget.navigation.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  /// 遥控/建图进行中 → 地图按较低频率自动刷新（默认 3s，不得高于 2s）
  void _syncMappingRefresh() {
    if (widget.remote.active) {
      _mappingRefreshTimer ??=
          Timer.periodic(const Duration(milliseconds: AppConfig.defaultMappingMapIntervalMs), (_) {
        unawaited(_loadMap(silent: true));
      });
    } else {
      _mappingRefreshTimer?.cancel();
      _mappingRefreshTimer = null;
    }
  }

  /// 加载地图（FR-MAP-03 按需 + FR-MAP-14 失败原因）
  Future<void> _loadMap({bool silent = false}) async {
    if (_mapLoading || !mounted) return;
    _mapLoading = true;
    if (!silent) setState(() => _mapError = null);

    final res = await widget.services.slam.mapGrid();
    if (!mounted) return;

    if (!res.ok || res.data == null) {
      setState(() {
        _mapLoading = false;
        if (!silent) {
          _mapError = res.error ?? '地图加载失败，请重试';
        }
      });
      return;
    }

    final grid = res.data!;
    final image = await buildGridImage(grid);
    if (!mounted) return;

    setState(() {
      _grid = grid;
      _gridImage = image;
      _mapError = null;
      _mapLoading = false;
    });

    // 取景：有目标优先 fitPoints，否则整图/居中机器人
    _fitInitial();
    unawaited(_loadMapExtras());
  }

  /// 地图要素（POI / 桩 / 墙线 / 轨道）+ 激光（限流 4s）
  Future<void> _loadMapExtras() async {
    await widget.services.state.refreshMapArtifacts();

    if (_layers.laser) {
      final now = DateTime.now();
      final last = _lastLaserAt;
      if (last == null || now.difference(last).inMilliseconds > widget.services.settings.laserIntervalMs) {
        _lastLaserAt = now;
        final res = await widget.services.system.laserScan();
        if (res.ok && res.data != null && mounted) {
          setState(() => _laserPoints = res.data!.points);
        }
      }
    }
  }

  /// FR-MAP-10 视野自适应三态 + 有目标时 fitPoints 优先
  void _fitInitial() {
    final g = _grid;
    if (g == null) return;
    final mode = widget.services.settings.mapDefaultFit;

    final target = _currentTargetPoints();
    if (target.isNotEmpty) {
      _fitPoints(target, pad: 3);
      return;
    }
    final pose = widget.services.state.pose;
    if (mode == 'robot' && pose != null) {
      _centerOn(pose.x, pose.y, 24);
    } else {
      _fitAll();
    }
  }

  List<List<double>> _currentTargetPoints() {
    final pts = <List<double>>[];
    final pose = widget.services.state.pose;
    final nav = widget.navigation.target;
    final patrol = widget.patrol;

    if (patrol.isRunning && patrol.nextTarget != null) {
      if (pose != null) pts.add(<double>[pose.x, pose.y]);
      pts.add(<double>[patrol.nextTarget!.x, patrol.nextTarget!.y]);
      pts.addAll(patrol.currentSegmentPath);
      pts.addAll(patrol.fullRoute);
      return pts;
    }
    if (nav != null) {
      if (pose != null) pts.add(<double>[pose.x, pose.y]);
      pts.add(<double>[nav.x, nav.y]);
      pts.addAll(nav.points);
    }
    return pts;
  }

  void _fitAll() {
    final g = _grid;
    if (g == null) return;
    setState(() {
      _viewport = MapViewport(x0: g.minX, y0: g.minY, x1: g.maxX, y1: g.maxY);
    });
  }

  void _centerOn(double x, double y, double spanM) {
    setState(() {
      _viewport = MapViewport(
        x0: x - spanM / 2,
        y0: y - spanM / 2,
        x1: x + spanM / 2,
        y1: y + spanM / 2,
      );
    });
  }

  /// 把若干点全框进来（避免目标被挤出视野，开发文档 §13.5 / §17 坑 6）
  void _fitPoints(List<List<double>> pts, {double pad = 3}) {
    if (pts.isEmpty) return;
    var minX = pts.first[0], maxX = pts.first[0];
    var minY = pts.first[1], maxY = pts.first[1];
    for (final p in pts) {
      if (p[0] < minX) minX = p[0];
      if (p[0] > maxX) maxX = p[0];
      if (p[1] < minY) minY = p[1];
      if (p[1] > maxY) maxY = p[1];
    }
    // 最小跨度，避免单点时无限放大
    final w = (maxX - minX) < 1 ? 1.0 : (maxX - minX);
    final h = (maxY - minY) < 1 ? 1.0 : (maxY - minY);
    setState(() {
      _viewport = MapViewport(
        x0: minX - pad,
        y0: minY - pad,
        x1: minX + w + pad,
        y1: minY + h + pad,
      );
    });
  }

  /// 轨迹采样（FR-MAP-05：0.05m 间隔，上限 4000 点，超出丢弃最早点）
  void _appendTrail() {
    final pose = widget.services.state.pose;
    if (pose == null || !_layers.trail) return;
    if (_trail.isNotEmpty) {
      final last = _trail.last;
      final d = NumFmt.lineDistance(last[0], last[1], pose.x, pose.y);
      if (d < AppConfig.trailSampleMeters) return;
    }
    setState(() {
      _trail.add(<double>[pose.x, pose.y]);
      while (_trail.length > AppConfig.maxTrailPoints) {
        _trail.removeAt(0);
      }
    });
  }

  /// 地图点击选点（FR-MAP-13：点击误差 ≤ 1 格 = 0.05m）
  void _onTapMap(Offset local, Size size) {
    final g = _grid;
    if (g == null) return;
    final vp = _viewport;
    final x = vp.x0 + local.dx / size.width * vp.width;
    final y = vp.y0 + (1 - local.dy / size.height) * vp.height;
    // 吸附到格中心，保证与地图坐标系一致
    final sx = (x / g.res).round() * g.res;
    final sy = (y / g.res).round() * g.res;

    // POI 吸附提示（0.5m 内）
    Poi? nearest;
    var nearestD = double.infinity;
    for (final p in widget.services.state.pois) {
      final d = NumFmt.lineDistance(sx, sy, p.pose.x, p.pose.y);
      if (d < nearestD) {
        nearestD = d;
        nearest = p;
      }
    }
    final poi = (nearest != null && nearestD <= 0.5) ? nearest : null;
    unawaited(_showTargetSheet(sx, sy, poi: poi, poiDistance: nearestD));
  }

  /// P03 选点面板：坐标 + POI 吸附 + 操作三选
  Future<void> _showTargetSheet(
    double x,
    double y, {
    Poi? poi,
    double? poiDistance,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          final block = widget.gate.blockReason(needsDock: false);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  '已选点',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'x = ${NumFmt.coord(x)}　y = ${NumFmt.coord(y)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                if (poi != null && poiDistance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '距「${poi.displayName}」${poiDistance.toStringAsFixed(2)} m',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.poi),
                    ),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await widget.navigation.planOnly(x, y);
                    _fitInitial();
                  },
                  icon: const Icon(Icons.timeline),
                  label: const Text('↗ 规划路径（不移动）'),
                ),
                const SizedBox(height: 10),
                if (poi != null && poiDistance != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(_navigateToPoi(poi));
                    },
                    icon: const Icon(Icons.my_location),
                    label: Text('吸附到「${poi.displayName}」并导航'),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: block != null
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          final ok = await ConfirmDanger.show(
                            context,
                            ConfirmRequest(
                              title: '确认让机器人移动？',
                              actionName: 'MoveToAction',
                              targetName: poi?.displayName ?? '自定义坐标',
                              coordinates:
                                  'x ${NumFmt.coord(poi?.pose.x ?? x)}, y ${NumFmt.coord(poi?.pose.y ?? y)}',
                              riskNote: '请确认行进区域无人、无障碍物。',
                            ),
                          );
                          if (!ok) return;
                          await widget.navigation
                              .navigateTo(widget.gate, poi?.displayName ?? '自定义坐标',
                                  poi?.pose.x ?? x, poi?.pose.y ?? y);
                          _fitInitial();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(block == null ? '▶ 导航到这里' : '导航不可用：$block'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('坐标已复制：$x, $y')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('⧉ 复制坐标'),
                ),
                const SizedBox(height: 4),
                Text(
                  '吸附规则：落点半径 0.5m 内若存在 POI 会给出提示，默认不吸附以避免误操作。',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _navigateToPoi(Poi poi) async {
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认让机器人移动？',
        actionName: 'MoveToAction',
        targetName: poi.displayName,
        coordinates: 'x ${NumFmt.coord(poi.pose.x)}, y ${NumFmt.coord(poi.pose.y)}',
        riskNote: '请确认行进区域无人、无障碍物。',
      ),
    );
    if (!ok) return;
    final res = await widget.navigation
        .navigateTo(widget.gate, poi.displayName, poi.pose.x, poi.pose.y);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    _fitInitial();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final state = s.state;
    final nav = widget.navigation.target;
    final patrol = widget.patrol;

    return Column(
      children: <Widget>[
        // 导航目标常驻提示（FR-NAV-08）
        if (nav != null)
          Container(
            color: const Color(0xFFE8F0F9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: <Widget>[
                const Icon(Icons.flag_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '目标：${nav.name} (${nav.coordinateLabel})'
                    '${widget.navigation.lastPlanSummary == null ? '' : ' · ${widget.navigation.lastPlanSummary}'}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    widget.navigation.clearTarget();
                    _fitInitial();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: AppColors.neutral),
                  ),
                ),
              ],
            ),
          ),
        if (widget.navigation.lastPlanWarning != null)
          NoticeBanner(
            text: widget.navigation.lastPlanWarning!,
            severity: Severity.warning,
            dense: true,
          ),
        if (patrol.isRunning)
          NoticeBanner(
            text: '巡逻中 · ${patrol.progressLabel()}'
                '${patrol.dwellRemainingSec > 0 ? ' · 停留倒计时 ${patrol.dwellRemainingSec}s' : ''}',
            severity: Severity.info,
            dense: true,
          ),
        // 定位质量低提示（FR-DASH-05）
        if (state.quality != null && state.quality! < 40 && !widget.remote.active)
          const NoticeBanner(
            text: '定位质量低（<40）：位姿可能不可靠，建议重新定位或推回桩。',
            severity: Severity.warning,
            dense: true,
          ),

        // 工具栏
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              _toolButton(
                icon: Icons.refresh,
                label: '加载/刷新地图',
                onTap: _loadMap,
              ),
              _toolButton(
                icon: Icons.center_focus_strong,
                label: '整图',
                onTap: _fitAll,
              ),
              _toolButton(
                icon: Icons.my_location,
                label: '居中机器人',
                onTap: () {
                  final p = state.pose;
                  if (p != null) _centerOn(p.x, p.y, 24);
                },
              ),
              _toolButton(
                icon: Icons.layers,
                label: '图层',
                onTap: () => setState(() => _legendExpanded = !_legendExpanded),
              ),
              _toolButton(
                icon: Icons.cleaning_services_outlined,
                label: '清除轨迹',
                onTap: () => setState(_trail.clear),
              ),
              const Spacer(),
              if (_mapLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),

        // 图层开关（FR-MAP-11）
        if (_legendExpanded)
          Container(
            color: const Color(0xFFF9FBFD),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: <Widget>[
                _layerChip('栅格', _layers.grid, (bool v) => setState(() => _layers.grid = v)),
                _layerChip('网格', _layers.gridLines,
                    (bool v) => setState(() => _layers.gridLines = v)),
                _layerChip('轨迹', _layers.trail, (bool v) => setState(() => _layers.trail = v)),
                _layerChip('激光', _layers.laser, (bool v) {
                  setState(() => _layers.laser = v);
                  if (v) {
                    _lastLaserAt = null;
                    unawaited(_loadMapExtras());
                  }
                }),
                _layerChip('POI', _layers.poi, (bool v) => setState(() => _layers.poi = v)),
                _layerChip('桩', _layers.dock, (bool v) => setState(() => _layers.dock = v)),
                _layerChip('墙线', _layers.walls, (bool v) => setState(() => _layers.walls = v)),
                _layerChip('路线', _layers.route, (bool v) => setState(() => _layers.route = v)),
                _layerChip('目标', _layers.target, (bool v) => setState(() => _layers.target = v)),
                _layerChip('名称', _layers.labels, (bool v) => setState(() => _layers.labels = v)),
              ],
            ),
          ),

        // 地图画布
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              if (_mapError != null) {
                return EmptyState(
                  title: '地图加载失败',
                  hint: _mapError,
                  action: FilledButton.icon(
                    onPressed: _loadMap,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                );
              }
              return GestureDetector(
                onTapUp: (TapUpDetails d) => _onTapMap(d.localPosition, size),
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: GridMapPainter(
                          gridImage: _gridImage,
                          grid: _grid,
                          viewport: _viewport,
                          layers: _layers,
                          robotPose: state.pose,
                          trail: _trail,
                          laserPoints: _laserPoints,
                          pois: state.pois,
                          docks: state.docks,
                          walls: state.walls,
                          tracks: state.tracks,
                          routePoints: patrol.currentSegmentPath.isNotEmpty
                              ? patrol.currentSegmentPath
                              : (widget.navigation.target?.points ?? const <List<double>>[]),
                          patrolRoute: patrol.fullRoute,
                          nextTarget: patrol.nextTarget == null
                              ? null
                              : <double>[patrol.nextTarget!.x, patrol.nextTarget!.y],
                          navTarget: nav == null ? null : MapNavTarget(name: nav.name, x: nav.x, y: nav.y),
                          repaintTick: DateTime.now().millisecondsSinceEpoch ~/ 500,
                        ),
                      ),
                    ),
                    if (_grid == null && !_mapLoading)
                      const Center(
                        child: Text(
                          '尚未加载地图，点击「加载/刷新地图」',
                          style: TextStyle(fontSize: 13, color: AppColors.neutral),
                        ),
                      ),
                    // 图例（常驻可折叠，FR-MAP-02）
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _legend(),
                    ),
                    // 手动控制入口（FR-RC-01：地图页常驻可见，不藏二级菜单）
                    Positioned(
                      right: 8,
                      top: 8,
                      child: FilledButton.icon(
                        onPressed: () => _openRemoteControl(),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.remote.active
                              ? AppColors.error
                              : AppColors.primary,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: Icon(
                          widget.remote.active ? Icons.warning_amber_rounded : Icons.gamepad,
                          size: 17,
                        ),
                        label: Text(widget.remote.active ? '遥控中' : '手动控制（建图用）'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 19, color: AppColors.primary),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _layerChip(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              value ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
              color: value ? AppColors.primary : AppColors.neutral,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: value ? AppColors.primary : AppColors.neutral,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend() {
    const items = <MapEntry<Color, String>>[
      MapEntry(AppColors.gridPassable, '可通行'),
      MapEntry(AppColors.gridUnexplored, '未探索'),
      MapEntry(AppColors.gridObstacle, '障碍'),
      MapEntry(AppColors.gridUnknown, '其它'),
      MapEntry(AppColors.laser, '激光点'),
      MapEntry(AppColors.trail, '行走轨迹'),
      MapEntry(AppColors.route, '规划路径'),
      MapEntry(AppColors.navTarget, '导航终点'),
      MapEntry(AppColors.patrolRoute, '巡逻路线'),
      MapEntry(AppColors.poi, 'POI'),
      MapEntry(AppColors.dock, '充电桩'),
      MapEntry(AppColors.wall, '虚拟墙'),
      MapEntry(AppColors.track, '虚拟轨道'),
      MapEntry(AppColors.robot, '机器人'),
    ];

    final scale = MediaQuery.of(context).size.width < 380 ? 0.85 : 1.0;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('图例', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Wrap(
            direction: Axis.vertical,
            spacing: 2 * scale,
            children: items
                .map((MapEntry<Color, String> e) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: e.key,
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(e.value, style: const TextStyle(fontSize: 10)),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  /// 进入手动遥控（FR-RC-02：进入时一次性确认）
  Future<void> _openRemoteControl() async {
    final block = widget.remote.enterBlockReason();
    if (block != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(block)));
      return;
    }
    // 存在自动行为时不允许进入，须先终止（FR-RC-07）
    if (widget.gate.patrolRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('巡逻正在运行，请先停止巡逻再进入遥控。')),
      );
      return;
    }
    if (widget.services.state.hasRunningAction) {
      final stop = await ConfirmDanger.show(
        context,
        const ConfirmRequest(
          title: '存在正在执行的行为',
          actionName: '终止行为',
          extraLines: <String>['进入遥控前必须先终止当前行为。'],
          riskNote: '确认后将先终止当前行为，机器人就地停止。',
          confirmLabel: '终止并进入遥控',
        ),
      );
      if (!stop) return;
      await widget.gate.abort();
    }

    final accepted = await ConfirmDanger.confirmRemoteEntry(
      context,
      lowBattery: widget.remote.lowBatteryWarning,
    );
    if (!accepted) return;
    await widget.remote.confirm();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteControlPage(
          services: widget.services,
          remote: widget.remote,
          gate: widget.gate,
        ),
      ),
    );
  }
}
