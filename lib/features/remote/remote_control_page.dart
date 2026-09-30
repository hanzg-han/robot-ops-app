import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/num_fmt.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';

/// P02a 手动遥控面板（PRD §5.12；FR-RC-01~15）。
///
/// 这是全 App **最危险**的功能，安全约束必须逐条实现：
/// - 顶部红色风险条常驻不可关闭（"不会自动避障 · 按住行走 · 松开即停"）；
/// - 方向键 ≥64dp、间距 ≥12dp；按住即连续下发，抬起/滑出/切后台/锁屏/断连/关面板立即停止；
/// - 同一时刻只允许一个方向生效（后按者优先）；
/// - 遥控期间禁止导航/巡逻/回充（由 ActionGate 双向互斥）；
/// - 退出时清理状态，下次进入必须重新确认（不持久化）。
class RemoteControlPage extends StatefulWidget {
  const RemoteControlPage({
    super.key,
    required this.services,
    required this.remote,
    required this.gate,
  });

  final AppServices services;
  final RemoteControlController remote;
  final ActionGate gate;

  @override
  State<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends State<RemoteControlPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.remote.addListener(_onState);
    widget.services.state.addListener(_onState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.remote.removeListener(_onState);
    widget.services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  /// 切后台 / 锁屏 → 立即停止（六路之一），返回前台需重新确认
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.remote.onAppBackground();
    }
  }

  Future<void> _exit() async {
    final wasMapping = widget.remote.mappingEnabled == true;
    await widget.remote.exit();
    if (!mounted) return;
    if (wasMapping) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('当前仍处于建图模式'),
          content: const Text('退出遥控后底盘仍处于建图模式，是否同时退出建图模式？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('保持建图模式'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('退出建图模式'),
            ),
          ],
        ),
      );
      if (leave == true) {
        await widget.remote.setMapping(false);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _toggleMapping() async {
    final target = !(widget.remote.mappingEnabled ?? false);
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: target ? '开启建图模式？' : '关闭建图模式？',
        actionName: 'PUT mapping/:enable',
        targetName: target ? '建图模式' : '定位模式',
        extraLines: const <String>[
          '该操作不会移动机器人，但会影响地图数据。',
          '建图中定位质量可能异常（返回 0），位姿仅供参考。',
        ],
        riskNote: '请确认当前处于正确的建图阶段。',
        confirmLabel: '确认切换',
      ),
    );
    if (!ok) return;
    final done = await widget.remote.setMapping(target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done ? '已切换为${target ? '建图' : '定位'}模式' : (widget.remote.lastError ?? '切换失败'))),
    );
  }

  Future<void> _saveMap() async {
    // FR-RC-12：若 capabilities 含 multi_floor，保存地图前须强制提示多楼层风险
    final multiFloor = widget.services.state.capabilities
        .any((Capability c) => c.name.toLowerCase().contains('multi_floor'));
    if (multiFloor) {
      final proceed = await ConfirmDanger.show(
        context,
        const ConfirmRequest(
          title: '检测到多楼层能力',
          actionName: 'POST stcm/:save',
          targetName: '保存地图（强制拦截确认）',
          extraLines: <String>[
            '底盘 capabilities 含 multi_floor。',
            '接口文档明确：多楼层环境中禁止该操作，否则会丢失其他楼层的地图。',
          ],
          riskNote: '若本次为多楼层场景，请勿保存。建议仅单楼层建图场景使用。',
          confirmLabel: '我确认仅单楼层，继续',
        ),
      );
      if (!proceed) return;
    }
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '保存地图？',
        actionName: 'POST stcm/:save',
        targetName: '保存当前地图',
        extraLines: <String>[
          '接口文档明确：多楼层环境中禁止该操作，否则会丢失其他楼层的地图。',
          if (multiFloor) '检测到多楼层能力，请务必确认。',
        ],
        riskNote: '若当前为多楼层场景，请勿执行本操作。建议先停止遥控再保存。',
        confirmLabel: '确认保存地图',
      ),
    );
    if (!ok) return;

    // 保存前先停止运动（流程：走完场地 → 松手停止 → 保存地图）
    await widget.remote.stopAll(reason: '保存地图前停止');
    final res = await widget.remote.saveMap();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? '地图已保存。' : (res.error ?? '保存地图失败'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final remote = widget.remote;
    final pose = s.state.pose;
    final connected = s.state.isConnected;
    final locked = remote.isErrorLocked;

    // 连接中断 → 方向键立即禁用 + 红色横幅（FR-RC-06 六路之一）
    if (!connected) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('手动遥控'),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: <Widget>[
            const NoticeBanner(
              text: '连接已中断，运动已停止。恢复连接后需重新确认。',
              severity: Severity.error,
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('方向键已禁用', style: TextStyle(fontSize: 15)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _exit,
                      child: const Text('退出遥控'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('手动遥控'),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StatusBadge(
                text: (remote.mappingEnabled ?? false) ? '建图模式' : '定位模式',
                color: (remote.mappingEnabled ?? false) ? AppColors.warning : AppColors.success,
                filled: (remote.mappingEnabled ?? false),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // 顶部风险条：常驻红色、不可关闭
            Container(
              width: double.infinity,
              color: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '不会自动避障 · 按住行走 · 松开即停',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              NoticeBanner(
                text: remote.lastError ?? '指令下发失败，已停止（3 秒后可重试）',
                severity: Severity.warning,
                dense: true,
              ),
            if ((remote.mappingEnabled ?? false))
              const NoticeBanner(
                text: '建图中，位姿仅供参考（定位质量可能为 0）。',
                severity: Severity.info,
                dense: true,
              ),
            if (remote.lowBatteryWarning)
              NoticeBanner(
                text: '电量 ${NumFmt.battery(s.state.power?.batteryPercentage)}，'
                    '低于阈值 ${s.settings.lowBatteryThreshold}%。',
                severity: Severity.warning,
                dense: true,
              ),

            // 状态行（运动期间 1s 刷新）
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          pose == null
                              ? '位姿 —'
                              : '位姿 ${NumFmt.coord(pose.x)}, ${NumFmt.coord(pose.y)} · '
                                  '${NumFmt.angleDeg(pose.yaw)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Text(
                        '质量 ${s.state.quality?.round() ?? '—'}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.qualityColor(s.state.quality),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '本次行进 ${remote.travelledMeters.toStringAsFixed(2)} m'
                          ' · 已 ${remote.pressSeconds}s'
                          ' · 会话 ${remote.sessionDurationLabel}',
                          style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                        ),
                      ),
                      Text(
                        '档位 ${remote.gear.label}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: <Widget>[
                    // 方向键区（十字布局，四键各 ≥64dp，间距 ≥12dp）
                    _RcPad(remote: remote),
                    const SizedBox(height: 12),
                    Text(
                      remote.isMoving
                          ? '${remote.pressedDirection!.label}中…（松手即停）'
                          : '手指按住方向键开始移动，抬起即停',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.neutral),
                    ),
                    const SizedBox(height: 14),

                    // 速度档（三档分段控件，默认「慢」）
                    Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 52,
                          child: Text('速度档', style: TextStyle(fontSize: 13)),
                        ),
                        Expanded(
                          child: SegmentedButton<int>(
                            segments: <ButtonSegment<int>>[
                              for (var i = 0; i < 3; i++)
                                ButtonSegment<int>(
                                  value: i,
                                  label: Text(AppConfigGears.labels[i]),
                                ),
                            ],
                            selected: <int>{remote.gearIndex},
                            onSelectionChanged: (Set<int> v) {
                              // 切档即时生效，不需重新确认（FR-RC-05）
                              remote.setGear(v.first);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 终止运动（红色实心，拇指易达区）
                    SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => remote.stopAll(reason: '面板终止按钮'),
                        style: AppTheme.dangerButton(),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('■ 终止运动'),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 建图模式 / 保存地图
                    SectionCard(
                      title: '建图控制',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '当前为「${(remote.mappingEnabled ?? false) ? '建图模式' : '定位模式'}」',
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ),
                              TextButton(
                                onPressed: _toggleMapping,
                                child: Text(
                                  (remote.mappingEnabled ?? false) ? '切到定位模式' : '切到建图模式',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _saveMap,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存地图（多楼层环境禁止）'),
                          ),
                        ],
                      ),
                    ),

                    // 退出遥控（文字按钮，位于最底部，避免误触）
                    TextButton.icon(
                      onPressed: _exit,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('退出遥控'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '会话统计：${remote.summaryText}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: AppColors.neutral),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 速度档标签（避免在 UI 里直接依赖 AppConfig 常量列表）
class AppConfigGears {
  const AppConfigGears._();
  static const List<String> labels = <String>['慢', '中', '快'];
}

/// 四向方向键（十字布局；四键 ≥64dp，间距 ≥12dp）
class _RcPad extends StatelessWidget {
  const _RcPad({required this.remote});

  final RemoteControlController remote;

  static const double _size = 78;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _key(RcDirection.forward, Icons.keyboard_arrow_up, '前进'),
        const SizedBox(height: _gap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _key(RcDirection.left, Icons.keyboard_arrow_left, '左转'),
            const SizedBox(width: _gap),
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
              child: const Center(
                child: Icon(Icons.gps_fixed, color: AppColors.neutral, size: 22),
              ),
            ),
            const SizedBox(width: _gap),
            _key(RcDirection.right, Icons.keyboard_arrow_right, '右转'),
          ],
        ),
        const SizedBox(height: _gap),
        _key(RcDirection.backward, Icons.keyboard_arrow_down, '后退'),
      ],
    );
  }

  /// 按住即走、抬起即停；滑出（onTapCancel / onHorizontalDragEnd）立即停止
  Widget _key(RcDirection dir, IconData icon, String label) {
    final pressed = remote.pressedDirection == dir;
    return Listener(
      onPointerDown: (_) => remote.press(dir),
      onPointerUp: (_) => remote.release(),
      onPointerCancel: (_) => remote.release(),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: pressed ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: pressed ? AppColors.primary : AppColors.line,
            width: pressed ? 2 : 1,
          ),
          boxShadow: pressed
              ? null
              : const <BoxShadow>[
                  BoxShadow(color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 30, color: pressed ? Colors.white : AppColors.primary),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: pressed ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
