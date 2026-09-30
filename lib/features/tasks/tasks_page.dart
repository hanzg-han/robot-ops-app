import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/num_fmt.dart';
import '../../data/dto/models.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/services/patrol_engine.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';
import '../settings/dock_page.dart';

/// Tab ③ 任务（分段：导航 / 巡逻 / 运动）
/// 对应 P04 / P05 / P06（PRD §5.5~§5.7）。
///
/// 合并理由（PRD §3.1 D1）：三者共用同一批接口 POST /actions、
/// 同一套二次确认、同一个「终止」语义；合并后危险操作集中、便于统一门控。
class TasksPage extends StatefulWidget {
  const TasksPage({
    super.key,
    required this.services,
    required this.gate,
    required this.navigation,
    required this.patrol,
    required this.onOpenMap,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;
  final PatrolController patrol;
  final VoidCallback onOpenMap;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    widget.services.state.addListener(_onState);
    widget.patrol.addListener(_onState);
    widget.navigation.addListener(_onState);
    final s = widget.services.settings;
    widget.patrol.points
      ..clear()
      ..addAll(s.patrolDraft);
    if (s.patrolParams.loops >= 0) {
      widget.patrol.updateParams(
        loops: s.patrolParams.loops,
        dwellMs: s.patrolParams.dwellMs,
        speedRatio: s.patrolParams.speedRatio,
        usePointYaw: s.patrolParams.usePointYaw,
      );
    }
  }

  @override
  void dispose() {
    widget.services.state.removeListener(_onState);
    widget.patrol.removeListener(_onState);
    widget.navigation.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          child: Row(
            children: <Widget>[
              _seg('导航', 0),
              _seg('巡逻', 1),
              _seg('运动', 2),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: <Widget>[
              _NavSection(
                services: widget.services,
                gate: widget.gate,
                navigation: widget.navigation,
                onOpenMap: widget.onOpenMap,
              ),
              _PatrolSection(services: widget.services, gate: widget.gate, patrol: widget.patrol),
              _MotionSection(
                services: widget.services,
                gate: widget.gate,
                navigation: widget.navigation,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seg(String label, int index) {
    final selected = _segment == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _segment = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.neutral,
            ),
          ),
        ),
      ),
    );
  }
}

/// P04 任务·导航（FR-NAV-01~09）
class _NavSection extends StatefulWidget {
  const _NavSection({
    required this.services,
    required this.gate,
    required this.navigation,
    required this.onOpenMap,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;
  final VoidCallback onOpenMap;

  @override
  State<_NavSection> createState() => _NavSectionState();
}

class _NavSectionState extends State<_NavSection> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _x = TextEditingController(text: '0');
  final TextEditingController _y = TextEditingController(text: '0');
  bool _byDistance = false;
  bool _planning = false;

  @override
  void dispose() {
    _search.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  Future<void> _planManual() async {
    final x = double.tryParse(_x.text.trim());
    final y = double.tryParse(_y.text.trim());
    if (x == null || y == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的 x / y 数字（范围超出地图时仍允许搜路，由底盘判定）。')),
      );
      return;
    }
    setState(() => _planning = true);
    await widget.navigation.planOnly(x, y);
    if (mounted) setState(() => _planning = false);
  }

  Future<void> _navigate(String name, double x, double y, {String? priorWarning}) async {
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认让机器人移动？',
        actionName: 'MoveToAction',
        targetName: name,
        coordinates: 'x ${NumFmt.coord(x)}, y ${NumFmt.coord(y)}',
        extraLines: <String>[
          if (widget.navigation.lastPlanSummary != null)
            '规划：${widget.navigation.lastPlanSummary}',
          if (priorWarning != null) priorWarning,
        ],
        riskNote: '请确认行进区域无人、无障碍物。',
      ),
    );
    if (!ok) return;
    final res = await widget.navigation.navigateTo(widget.gate, name, x, y);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final state = s.state;
    final block = widget.gate.blockReason(needsDock: false);
    final pois = widget.navigation.search(_search.text, byDistance: _byDistance);

    return RefreshIndicator(
      onRefresh: () async {
        await state.runPreflight();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: <Widget>[
          if (block != null)
            NoticeBanner(text: '移动类操作不可用：$block', severity: Severity.warning, dense: true),
          SectionCard(
            title: '坐标导航',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _x,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(labelText: 'x (m)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _y,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(labelText: 'y (m)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _planning ? null : _planManual,
                  icon: _planning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.timeline),
                  label: const Text('↗ 规划路径（不移动）'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: block != null
                      ? null
                      : () {
                          final x = double.tryParse(_x.text.trim());
                          final y = double.tryParse(_y.text.trim());
                          if (x == null || y == null) return;
                          _navigate('自定义坐标', x, y);
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('▶ 导航到该坐标'),
                ),
                if (widget.navigation.lastPlanSummary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '规划结果：${widget.navigation.lastPlanSummary}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.success),
                    ),
                  ),
                if (widget.navigation.lastPlanWarning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      widget.navigation.lastPlanWarning!,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
                    ),
                  ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: widget.onOpenMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('在地图上查看路线'),
                ),
              ],
            ),
          ),
          SectionCard(
            title: '点位列表（${pois.length}）',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _byDistance = !_byDistance),
              icon: Icon(_byDistance ? Icons.sort : Icons.sort_by_alpha, size: 16),
              label: Text(_byDistance ? '按距离' : '按名称'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '搜索点位…',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                if (state.pois.isEmpty)
                  EmptyState(title: '底盘中还没有点位', hint: state.emptyPoiHint)
                else
                  ...pois.map((Poi p) {
                    final dist = widget.navigation.distanceTo(p);
                    return InkWell(
                      onTap: () => widget.navigation.planOnly(p.pose.x, p.pose.y, name: p.displayName),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.place_outlined, size: 17, color: AppColors.poi),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    p.displayName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${NumFmt.coord(p.pose.x)}, ${NumFmt.coord(p.pose.y)}'
                                    '${p.type == null ? '' : ' · type: ${p.type}'}'
                                    '${dist == null ? '' : ' · 距 ${dist.toStringAsFixed(1)} m'}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.neutral,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '规划路径',
                              onPressed: () => widget.navigation
                                  .planOnly(p.pose.x, p.pose.y, name: p.displayName),
                              icon: const Icon(Icons.timeline, size: 19),
                              color: AppColors.primary,
                            ),
                            IconButton(
                              tooltip: '导航到该 POI',
                              onPressed:
                                  block != null ? null : () => _navigate(p.displayName, p.pose.x, p.pose.y),
                              icon: const Icon(Icons.play_arrow, size: 21),
                              color: block != null ? AppColors.neutral : AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// P05 任务·巡逻（FR-PAT-01~10）
class _PatrolSection extends StatefulWidget {
  const _PatrolSection({
    required this.services,
    required this.gate,
    required this.patrol,
  });

  final AppServices services;
  final ActionGate gate;
  final PatrolController patrol;

  @override
  State<_PatrolSection> createState() => _PatrolSectionState();
}

class _PatrolSectionState extends State<_PatrolSection> {
  final TextEditingController _loops = TextEditingController();
  final TextEditingController _dwellSec = TextEditingController();
  final TextEditingController _batch = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.patrol.params;
    _loops.text = '${p.loops}';
    _dwellSec.text = '${(p.dwellMs / 1000).round()}';
  }

  @override
  void dispose() {
    _loops.dispose();
    _dwellSec.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _addPointDialog({int? index}) async {
    final existing = index == null ? null : widget.patrol.points[index];
    final name = TextEditingController(text: existing?.name ?? '');
    final x = TextEditingController(text: existing?.x.toString() ?? '0');
    final y = TextEditingController(text: existing?.y.toString() ?? '0');
    final yawDeg = TextEditingController(
      text: existing?.yaw == null ? '' : NumFmt.rad2deg(existing!.yaw).toStringAsFixed(1),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(index == null ? '新增巡逻点' : '编辑巡逻点'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(controller: name, decoration: const InputDecoration(labelText: '名称（可空）')),
              const SizedBox(height: 8),
              TextField(
                controller: x,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'x (m)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: y,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'y (m)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: yawDeg,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: '到点朝向（度，可空）',
                  helperText: '留空则不指定朝向',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
        ],
      ),
    );

    if (ok != true) return;
    final px = double.tryParse(x.text.trim());
    final py = double.tryParse(y.text.trim());
    if (px == null || py == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('坐标必须是数字。')));
      return;
    }
    final yawText = yawDeg.text.trim();
    final yaw = yawText.isEmpty ? null : NumFmt.deg2rad(double.tryParse(yawText) ?? 0);

    final point = PatrolPoint(
      name: name.text.trim().isEmpty
          ? '点 ${(index ?? widget.patrol.points.length) + 1}'
          : name.text.trim(),
      x: px,
      y: py,
      yaw: yaw,
    );
    if (index == null) {
      widget.patrol.addPoint(point);
    } else {
      widget.patrol.updatePoint(index, point);
    }
    await _persist();
  }

  Future<void> _persist() => widget.services.settings.savePatrolDraft(
        widget.patrol.points,
        widget.patrol.params,
      );

  Future<void> _importPaste() async {
    _batch.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('批量粘贴巡逻点'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _batch,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '名称,x,y[,yaw]\n# 以 # 开头或空行忽略\n3F-检验科-停留点,11.93,0.27',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('导入')),
        ],
      ),
    );
    if (ok != true) return;
    final res = widget.patrol.importText(_batch.text);
    await _persist();
    if (!mounted) return;
    // 解析失败提示具体行号（FR-PAT-02）
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.hasErrors
            ? '导入 ${res.points.length} 点；${res.errors.length} 行解析失败：\n${res.errors.take(3).join('\n')}'
            : '成功导入 ${res.points.length} 个巡逻点'),
      ),
    );
  }

  Future<void> _start() async {
    final patrol = widget.patrol;
    patrol.updateParams(
      loops: int.tryParse(_loops.text.trim()) ?? 1,
      dwellMs: ((int.tryParse(_dwellSec.text.trim()) ?? 5) * 1000),
    );
    await _persist();

    final preview = patrol.points
        .asMap()
        .entries
        .map((MapEntry<int, PatrolPoint> e) => '${e.key + 1}. ${e.value.name}')
        .join(' → ');

    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认开始巡逻？',
        actionName: '巡逻（多次 MoveToAction）',
        targetName: '${patrol.points.length} 个巡逻点',
        extraLines: <String>[
          '路径：$preview',
          '参数：${patrol.summary()}',
        ],
        riskNote: '巡逻期间机器人将连续移动，请确认路线无人、无障碍物，并保持 App 前台运行。',
        confirmLabel: '确认开始巡逻',
      ),
    );
    if (!ok) return;
    await patrol.start();
    if (!mounted) return;
    // 巡逻运行时可切到地图页观察整条路线与下一目标（FR-PAT-06）
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('巡逻已开始，可切到「地图」页查看整条路线与下一目标。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patrol = widget.patrol;
    final running = patrol.isRunning;
    final block = patrol.startBlockReason();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: <Widget>[
        if (running)
          SectionCard(
            title: '巡逻运行中',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  patrol.progressLabel(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (patrol.dwellRemainingSec > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '停留倒计时：${patrol.dwellRemainingSec} 秒',
                      style: const TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  ),
                if (patrol.nextTarget != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '下一目标：${patrol.nextTarget!.name}'
                      '（${NumFmt.coord(patrol.nextTarget!.x)}, ${NumFmt.coord(patrol.nextTarget!.y)}）',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.neutral),
                    ),
                  ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: patrol.engine.progress.clamp(0, 1)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final outcome = await patrol.stop();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${outcome.message}（巡逻已停止）')),
                      );
                    },
                    style: AppTheme.dangerButton(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('■ 停止巡逻'),
                  ),
                ),
              ],
            ),
          ),

        if (!running)
          SectionCard(
            title: '巡逻点（${patrol.points.length}）',
            trailing: TextButton.icon(
              onPressed: () async {
                final added = patrol.appendAllPois();
                await _persist();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已追加 $added 个 POI（按楼层分组）')),
                );
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('追加全部 POI'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (patrol.points.isEmpty)
                  const EmptyState(
                    title: '尚未添加巡逻点',
                    hint: '可手工新增、追加全部 POI，或批量粘贴「名称,x,y[,yaw]」。至少 2 个点才能开始。',
                  )
                else
                  ...patrol.points.asMap().entries.map((MapEntry<int, PatrolPoint> e) {
                    final i = e.key;
                    final p = e.value;
                    final isCurrent = running && patrol.engine.currentIndex - 1 == i;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFFE8F0F9) : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 6),
                          Text('${i + 1}.', style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrent)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: StatusBadge(
                                          text: '当前',
                                          color: AppColors.primary,
                                          filled: true,
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  '${NumFmt.coord(p.x)}, ${NumFmt.coord(p.y)}'
                                  '${p.yaw == null ? '' : ' · ${NumFmt.angleDeg(p.yaw)}'}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed: i == 0 ? null : () async {
                              patrol.movePoint(i, -1);
                              await _persist();
                            },
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed: i == patrol.points.length - 1 ? null : () async {
                              patrol.movePoint(i, 1);
                              await _persist();
                            },
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed: () => _addPointDialog(index: i),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            iconSize: 18,
                            onPressed: () async {
                              patrol.removePoint(i);
                              await _persist();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addPointDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增点'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importPaste,
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('批量粘贴'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () async {
                    patrol.clearPoints();
                    await _persist();
                  },
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清空巡逻点'),
                ),
              ],
            ),
          ),

        if (!running)
          SectionCard(
            title: '巡逻参数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _loops,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '圈数',
                          helperText: '0 = 无限',
                        ),
                        onChanged: (String v) => patrol.updateParams(loops: int.tryParse(v) ?? 1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _dwellSec,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '点间停留（秒）',
                          helperText: '下发为毫秒',
                        ),
                        onChanged: (String v) => patrol.updateParams(
                          dwellMs: (int.tryParse(v) ?? 5) * 1000,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 62,
                      child: Text(
                        '速度 ${(patrol.params.speedRatio * 100).round()}%',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: patrol.params.speedRatio.clamp(0.1, 1.0),
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: patrol.params.speedRatio.toStringAsFixed(1),
                        onChanged: (double v) => patrol.updateParams(speedRatio: v),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('到点定向使用点 yaw', style: TextStyle(fontSize: 13.5)),
                  value: patrol.params.usePointYaw,
                  onChanged: (bool v) => patrol.updateParams(usePointYaw: v),
                ),
                const SizedBox(height: 6),
                Text(
                  '预览：${patrol.summary()}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.neutral),
                ),
              ],
            ),
          ),

        if (!running)
          GuardedButton(
            label: '▶ 开始巡逻',
            blockReason: block,
            icon: Icons.play_circle_outline,
            onPressed: _start,
          ),
        const SizedBox(height: 8),
        const NoticeBanner(
          text: '巡逻为 App 侧状态机驱动的多点循环（底盘无原生巡逻概念），'
              '串行下发：下一目标必须等上一行为结束。',
          severity: Severity.info,
          dense: true,
        ),
      ],
    );
  }
}

/// P06 任务·运动（FR-MOT-01~09）
class _MotionSection extends StatefulWidget {
  const _MotionSection({
    required this.services,
    required this.gate,
    required this.navigation,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;

  @override
  State<_MotionSection> createState() => _MotionSectionState();
}

class _MotionSectionState extends State<_MotionSection> {
  // 回充参数（FR-MOT-02：默认 dock / 2 次 / true / mode 0，改动后本会话保持）
  String _flags = AppConfig.defaultGoHomeFlags;
  int _retry = AppConfig.defaultGoHomeRetryCount;
  bool _backToLanding = AppConfig.defaultGoHomeBackToLanding;
  int _mode = AppConfig.defaultMoveMode;

  final TextEditingController _angleDeg = TextEditingController(text: '90');

  // 参数读写（FR-MOT-09：仅 3 项白名单）
  final Map<String, String> _paramValues = <String, String>{};
  String? _paramStrategy = 'always';
  bool _paramExpanded = false;

  @override
  void initState() {
    super.initState();
    widget.services.state.addListener(_onState);
    _loadParams();
  }

  @override
  void dispose() {
    widget.services.state.removeListener(_onState);
    _angleDeg.dispose();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _loadParams() async {
    final s = widget.services;
    for (final name in ParameterWhitelist.all) {
      final res = await s.system.readParameter(name);
      if (!mounted) return;
      if (res.ok && res.data != null) {
        setState(() {
          if (name == ParameterWhitelist.dockedRegisterStrategy) {
            _paramStrategy = res.data.toString();
          } else {
            _paramValues[name] = res.data.toString();
          }
        });
      }
    }
  }

  Future<void> _goHome() async {
    final s = widget.services;
    final dock = s.state.homepose;
    final docks = s.state.docks;
    final label = docks.isNotEmpty
        ? docks.first.displayName
        : (dock == null ? '充电桩' : 'homepose');
    final coord = dock != null
        ? 'x ${NumFmt.coord(dock.x)}, y ${NumFmt.coord(dock.y)}'
        : (docks.isNotEmpty
            ? 'x ${NumFmt.coord(docks.first.pose.x)}, y ${NumFmt.coord(docks.first.pose.y)}'
            : '—');

    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认让机器人回充？',
        actionName: 'GoHomeAction',
        targetName: label,
        coordinates: coord,
        extraLines: <String>[
          '上桩方式：${_flags == 'dock' ? 'dock（上桩充电）' : 'no_dock（仅回到上桩点）'}',
          '失败回上桩点：${_backToLanding ? '开' : '关'} · 上桩重试 $_retry 次',
          '导航模式：${_mode == 0 ? '自由导航' : '轨道优先'}',
        ],
        riskNote: '请确认充电位及行进路径无人、无障碍物。',
        confirmLabel: '确认回充',
      ),
    );
    if (!ok) return;
    final res = await widget.gate.dispatchGoHome(
      flags: _flags,
      backToLanding: _backToLanding,
      retryCount: _retry,
      mode: _mode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
  }

  Future<void> _rotate() async {
    final deg = double.tryParse(_angleDeg.text.trim());
    if (deg == null || deg.abs() > 360) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('角度需为数字且范围 −360°~360°。')),
      );
      return;
    }
    final rad = NumFmt.deg2rad(deg);
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认让机器人原地旋转？',
        actionName: 'RotateToAction',
        targetName: '原地旋转 ${deg.toStringAsFixed(1)}°',
        coordinates: '${rad.toStringAsFixed(3)} rad',
        extraLines: <String>[
          if (deg.abs() > 180) '注意：将大幅转向（>180°）',
        ],
        riskNote: '旋转过程中请确保机器人周围 1 m 内无人、无障碍物。',
        confirmLabel: '确认旋转',
      ),
    );
    if (!ok) return;
    final res = await widget.gate.dispatchRotate(rad);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
  }

  Future<void> _registerDock() async {
    final pose = widget.services.state.pose;
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '把当前位置注册为充电桩？',
        actionName: 'POST homedocks/:register',
        targetName: '当前机器人位置',
        coordinates: pose == null
            ? '—'
            : 'x ${NumFmt.coord(pose.x)}, y ${NumFmt.coord(pose.y)}, ${NumFmt.angleDeg(pose.yaw)}',
        riskNote: '标定会覆盖现有充电桩位置，影响自动回充。请确认机器人已推到充电位。',
        confirmLabel: '确认注册',
      ),
    );
    if (!ok) return;
    final res = await widget.services.artifact.registerDock();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.ok ? '充电桩已注册，回充入口已可用。' : (res.error ?? '注册失败')),
      ),
    );
    await widget.services.state.refreshSlow();
  }

  Future<void> _writeParam(String name, Object? value) async {
    final err = ParameterWhitelist.validate(name, value);
    if (err != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final old = name == ParameterWhitelist.dockedRegisterStrategy
        ? _paramStrategy
        : (_paramValues[name] ?? '—');

    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认写入底盘参数？',
        actionName: 'PUT parameter',
        targetName: name,
        coordinates: '原值 $old → 新值 $value',
        extraLines: <String>[ParameterWhitelist.describe(name)],
        riskNote: name == ParameterWhitelist.dockedRegisterStrategy
            ? '该改动会影响自动回桩时的桩位注册行为。'
            : '该改动会影响机器人的运动速度，请谨慎调整。',
        confirmLabel: '确认写入',
      ),
    );
    if (!ok) return;

    final res = await widget.services.system.writeParameter(name, value);
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        if (name == ParameterWhitelist.dockedRegisterStrategy) {
          _paramStrategy = value.toString();
        } else {
          _paramValues[name] = value.toString();
        }
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? '参数已写入：$name = $value' : (res.error ?? '写入失败'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final state = s.state;
    final homeBlock = state.goHomeBlockReason;
    final rotateBlock = widget.gate.blockReason(needsDock: false);
    final deg = double.tryParse(_angleDeg.text.trim());
    final rad = deg == null ? null : NumFmt.deg2rad(deg);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: <Widget>[
        SectionCard(
          title: '回充',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('上桩方式', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _flags,
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(value: 'dock', child: Text('dock（上桩充电）')),
                        DropdownMenuItem<String>(value: 'no_dock', child: Text('no_dock（仅回到上桩点）')),
                      ],
                      onChanged: (String? v) => setState(() => _flags = v ?? 'dock'),
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('上桩重试', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: Slider(
                      value: _retry.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: '$_retry 次',
                      onChanged: (double v) => setState(() => _retry = v.round()),
                    ),
                  ),
                  Text('$_retry 次', style: const TextStyle(fontSize: 13)),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('失败回上桩点', style: TextStyle(fontSize: 13.5)),
                value: _backToLanding,
                onChanged: (bool v) => setState(() => _backToLanding = v),
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('导航模式', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _mode,
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(value: 0, child: Text('0 自由导航')),
                        DropdownMenuItem<int>(value: 2, child: Text('2 轨道优先')),
                      ],
                      onChanged: (int? v) => setState(() => _mode = v ?? 0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GuardedButton(
                label: '⌂ 开始回充',
                blockReason: homeBlock,
                icon: Icons.home_outlined,
                onPressed: _goHome,
              ),
              if (homeBlock == '未设置充电桩位置')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DockPage(services: s),
                      ),
                    ),
                    icon: const Icon(Icons.gps_fixed, size: 18),
                    label: const Text('去标定充电桩'),
                  ),
                ),
            ],
          ),
        ),

        SectionCard(
          title: '原地旋转',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _angleDeg,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '角度（度）',
                  suffixText: '°',
                  helperText: rad == null
                      ? '范围 −360°~360°'
                      : '等同 ${rad.toStringAsFixed(3)} 弧度（内部按弧度下发）',
                ),
              ),
              const SizedBox(height: 10),
              GuardedButton(
                label: '↻ 开始旋转',
                blockReason: rotateBlock,
                icon: Icons.rotate_right,
                onPressed: _rotate,
              ),
            ],
          ),
        ),

        SectionCard(
          title: '充电桩标定',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KvTile(
                label: '当前桩位姿',
                value: state.homepose == null
                    ? (state.docks.isNotEmpty
                        ? '已注册桩：x ${NumFmt.coord(state.docks.first.pose.x)}, '
                            'y ${NumFmt.coord(state.docks.first.pose.y)}'
                        : '未设置（homepose 返回 404）')
                    : 'x ${NumFmt.coord(state.homepose!.x)}, '
                        'y ${NumFmt.coord(state.homepose!.y)}, '
                        '${NumFmt.angleDeg(state.homepose!.yaw)}',
                dense: true,
              ),
              KvTile(
                label: '来源',
                value: state.homepose != null
                    ? 'homepose'
                    : (state.docks.isNotEmpty ? 'homedocks（已注册）' : '未设置'),
                dense: true,
              ),
              if (state.docks.isNotEmpty)
                KvTile(
                  label: '已注册桩',
                  value: state.docks
                      .map((Dock d) =>
                          '${d.displayName} · (${NumFmt.coord(d.pose.x)}, ${NumFmt.coord(d.pose.y)})')
                      .join('\n'),
                  dense: true,
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _registerDock,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('⌖ 把当前位置注册为充电桩'),
              ),
              const SizedBox(height: 6),
              const NoticeBanner(
                text: '标定会覆盖现有充电桩位置，影响自动回充。请确认机器人已推到充电位。',
                severity: Severity.warning,
                dense: true,
              ),
            ],
          ),
        ),

        SectionCard(
          title: '运动参数（受控白名单）',
          trailing: TextButton(
            onPressed: () => setState(() => _paramExpanded = !_paramExpanded),
            child: Text(_paramExpanded ? '收起' : '展开'),
          ),
          child: _paramExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _paramField(ParameterWhitelist.maxMovingSpeed, '最大线速度 (m/s)'),
                    _paramField(ParameterWhitelist.maxAngularSpeed, '最大角速度 (rad/s)'),
                    const SizedBox(height: 6),
                    Text(
                      ParameterWhitelist.dockedRegisterStrategy,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      ParameterWhitelist.describe(ParameterWhitelist.dockedRegisterStrategy),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
                    ),
                    const SizedBox(height: 6),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: ParameterWhitelist.strategyOptions.contains(_paramStrategy)
                          ? _paramStrategy
                          : ParameterWhitelist.strategyOptions.first,
                      items: ParameterWhitelist.strategyOptions
                          .map((String v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (String? v) {
                        if (v == null) return;
                        _writeParam(ParameterWhitelist.dockedRegisterStrategy, v);
                      },
                    ),
                    const SizedBox(height: 8),
                    const NoticeBanner(
                      text: '仅支持这 3 项（spec 明确为枚举/数值白名单），不支持自定义参数名。',
                      severity: Severity.info,
                      dense: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '运动策略：${state.strategy ?? '—'}（F6：v1.0 只读展示，不提供切换）',
                      style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                    ),
                  ],
                )
              : const Text(
                  '最大线速度 / 最大角速度 / 充电桩注册策略（共 3 项白名单，改动需二次确认）。',
                  style: TextStyle(fontSize: 12.5, color: AppColors.neutral),
                ),
        ),

        SectionCard(
          title: '终止当前行为',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '终止无需二次确认（危险操作加摩擦、终止类零摩擦）。'
                '底盘在无行为时也返回 200，因此 App 依据终止前后 :current 是否 404 判定。',
                style: TextStyle(fontSize: 12.5, color: AppColors.neutral),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: state.hasRunningAction
                      ? () async {
                          final outcome = await widget.gate.abort();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(outcome.message)));
                        }
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('当前没有正在执行的行为。')),
                          );
                        },
                  style: AppTheme.dangerButton(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(state.hasRunningAction ? '■ 终止当前行为' : '当前无行为可终止'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paramField(String name, String label) {
    final current = _paramValues[name];
    final controller = TextEditingController(text: current ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: label,
                helperText: name,
                helperMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _writeParam(name, controller.text.trim()),
            child: const Text('写入'),
          ),
        ],
      ),
    );
  }
}
