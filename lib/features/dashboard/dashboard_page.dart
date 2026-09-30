import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/num_fmt.dart';
import '../../core/utils/time_fmt.dart';
import '../../data/dto/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';

/// P01 总览（PRD §5.2；FR-DASH-01~12）。
///
/// 取舍：只放「判断健康所必需」的 6 类信息，一屏内可见电量、上桩、连接、
/// 当前行为、告警；技术字段折叠在「更多状态」里。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.services,
    required this.gate,
    required this.navigation,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _moreExpanded = false;

  /// 低电提醒只在跨阈值时出现一次（FR-DASH-07：不反复弹）
  bool _lowBatteryShown = false;
  bool _hadLowBattery = false;

  @override
  void initState() {
    super.initState();
    widget.services.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    final low = widget.services.state.isLowBattery;
    if (low && !_hadLowBattery) {
      _lowBatteryShown = true;
    }
    if (!low) _lowBatteryShown = false;
    _hadLowBattery = low;
    setState(() {});
  }

  Future<void> _goHome() async {
    final s = widget.services;
    final dock = s.state.homepose;
    final dockLabel = dock == null
        ? (s.state.docks.isNotEmpty ? s.state.docks.first.displayName : '充电桩')
        : 'return-dock';
    final coord = dock == null
        ? (s.state.docks.isNotEmpty
            ? 'x ${NumFmt.coord(s.state.docks.first.pose.x)}, y ${NumFmt.coord(s.state.docks.first.pose.y)}'
            : '—')
        : 'x ${NumFmt.coord(dock.x)}, y ${NumFmt.coord(dock.y)}';

    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '确认让机器人回充？',
        actionName: 'GoHomeAction',
        targetName: dockLabel,
        coordinates: coord,
        extraLines: <String>[
          '上桩方式：${s.settings.baseUrl.isEmpty ? 'dock' : 'dock（上桩充电）'}',
          '失败回上桩点：开 · 上桩重试 2 次',
        ],
        riskNote: '请确认充电位及行进路径无人、无障碍物。',
        confirmLabel: '确认回充',
      ),
    );
    if (!ok || !mounted) return;

    final res = await widget.gate.dispatchGoHome(
      flags: 'dock',
      backToLanding: true,
      retryCount: 2,
      mode: 0,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
  }

  Future<void> _abort() async {
    final outcome = await widget.gate.abort();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final state = s.state;
    final power = state.power;
    final info = state.robotInfo;
    final pose = state.pose;
    final stale = s.client.isStale;

    return RefreshIndicator(
      onRefresh: state.pullToRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: <Widget>[
          // ------------------------------------------------ 低电提醒卡（P0）
          if (_lowBatteryShown && state.isLowBattery)
            SectionCard(
              title: '低电提醒',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '电量 ${NumFmt.battery(power?.batteryPercentage)}，'
                    '低于设定阈值 ${s.settings.lowBatteryThreshold}%。'
                    '底盘无低电自动回桩策略，请立即回充。',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.error),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: state.canGoHome ? _goHome : null,
                      icon: const Icon(Icons.battery_charging_full),
                      label: Text(
                        state.canGoHome ? '立即回充' : '${state.goHomeBlockReason}',
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ------------------------------------------------------ 电量与上桩
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _BatteryRing(
                  value: power?.batteryPercentage,
                  color: AppColors.batteryColor(
                    power?.batteryPercentage,
                    threshold: s.settings.lowBatteryThreshold,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          StatusBadge(
                            text: power?.dockingLabel ?? '—',
                            color: power?.dockingStatus == 'on_dock'
                                ? AppColors.success
                                : AppColors.neutral,
                            filled: power?.dockingStatus == 'on_dock',
                          ),
                          const SizedBox(width: 6),
                          if (power?.isCharging == true)
                            const StatusBadge(
                              text: '⚡ 充电中',
                              color: AppColors.success,
                              icon: Icons.bolt,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      KvTile(
                        label: '定位质量',
                        value: state.quality == null
                            ? '—'
                            : '${state.quality!.round()} '
                                '${_qualityLabel(state.quality)}',
                        valueColor: AppColors.qualityColor(state.quality),
                        valueMono: true,
                      ),
                      KvTile(
                        label: '位姿',
                        value: pose == null
                            ? '—'
                            : '${NumFmt.coord(pose.x)}, ${NumFmt.coord(pose.y)} · '
                                '${NumFmt.angleDeg(pose.yaw)}',
                        sub: pose == null
                            ? null
                            : 'yaw ${NumFmt.angleRad(pose.yaw)}',
                        valueMono: true,
                      ),
                      KvTile(
                        label: '累计里程',
                        value: NumFmt.odometry(state.odometry),
                        valueMono: true,
                      ),
                      KvTile(
                        label: '更新时间',
                        value: TimeFmt.ago(s.client.lastSuccessAt),
                        sub: stale ? '数据可能过期，下拉可刷新' : null,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------- 当前行为卡
          SectionCard(
            title: '当前行为',
            trailing: Text(
              TimeFmt.ago(state.actionAt),
              style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (state.currentAction == null)
                  const Text(
                    '空闲（无正在执行的行为）',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  )
                else
                  ..._actionRows(state.currentAction!),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: state.hasRunningAction ? _abort : null,
                    style: AppTheme.dangerButton(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(state.hasRunningAction ? '■ 终止当前行为' : '当前无行为可终止'),
                  ),
                ),
              ],
            ),
          ),

          // ------------------------------------------------- 机型 / 固件卡
          SectionCard(
            title: '机型与固件',
            trailing: IconButton(
              tooltip: '复制机型信息',
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              onPressed: () {
                final text = '${info?.modelLabel ?? '—'} / ${info?.softwareVersion ?? '—'}';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制：$text')),
                );
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                KvTile(label: '机型', value: info?.modelLabel ?? '—', dense: true),
                KvTile(
                  label: '固件',
                  value: info?.softwareVersion ?? '—',
                  dense: true,
                ),
                KvTile(
                  label: '电源阶段',
                  value: power?.powerStageLabel ?? '—',
                  dense: true,
                ),
                KvTile(
                  label: '休眠模式',
                  value: power?.sleepModeLabel ?? '—',
                  dense: true,
                ),
              ],
            ),
          ),

          // ------------------------------------------------------ 健康告警
          SectionCard(
            title: '设备健康',
            child: state.healthAlerts.isEmpty
                ? const Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                      SizedBox(width: 6),
                      Text('健康，无告警', style: TextStyle(fontSize: 13.5)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: state.healthAlerts
                        .map((HealthAlert a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Icon(
                                    a.isRed ? Icons.error_outline : Icons.warning_amber_outlined,
                                    size: 16,
                                    color: a.isRed ? AppColors.error : AppColors.warning,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${a.title} · ${a.detail}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),

          // ------------------------------------------------------ 更多状态
          SectionCard(
            title: '更多状态',
            trailing: TextButton(
              onPressed: () => setState(() => _moreExpanded = !_moreExpanded),
              child: Text(_moreExpanded ? '收起' : '展开'),
            ),
            child: _moreExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      KvTile(
                        label: '充电座连接',
                        value: power?.isDCConnected == null
                            ? '—'
                            : (power!.isDCConnected! ? '是' : '否'),
                        dense: true,
                      ),
                      KvTile(
                        label: 'dock 状态原文',
                        value: power?.dockingStatus ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: 'powerStage 原文',
                        value: power?.powerStage ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: 'sleepMode 原文',
                        value: power?.sleepMode ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: '硬件版本',
                        value: info?.hardwareVersion ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: '设备 ID',
                        value: info?.deviceId ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: '运动策略',
                        value: state.strategy ?? '—',
                        dense: true,
                      ),
                      KvTile(
                        label: '定位使能',
                        value: state.localizationEnabled == null
                            ? '—'
                            : (state.localizationEnabled! ? '已开启' : '已暂停（纯里程）'),
                        dense: true,
                      ),
                    ],
                  )
                : const Text(
                    '电源阶段、休眠、充电座连接、硬件版本等技术字段折叠于此，'
                    '避免日常运维时的信息噪音。',
                    style: TextStyle(fontSize: 12.5, color: AppColors.neutral),
                  ),
          ),

          // ------------------------------------------------------ 快捷动作
          SectionCard(
            title: '快捷动作',
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: state.canGoHome ? _goHome : null,
                      icon: const Icon(Icons.home_outlined),
                      label: Text(state.canGoHome ? '立即回充' : '回充不可用'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: state.hasRunningAction ? _abort : null,
                      icon: const Icon(Icons.stop_outlined),
                      label: Text(state.hasRunningAction ? '终止行为' : '无行为'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            state.canGoHome ? '' : '回充不可用原因：${state.goHomeBlockReason}'
                '${state.goHomeBlockReason == '未设置充电桩位置' ? '（请先完成充电桩标定）' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.neutral),
          ),
        ],
      ),
    );
  }

  List<Widget> _actionRows(ActionState a) {
    final elapsed = a.createdAt == null
        ? '—'
        : '${DateTime.now().difference(a.createdAt!).inSeconds}s';
    return <Widget>[
      KvTile(
        label: '动作',
        value: '${a.shortLabel}（${a.shortName}）',
        valueColor: AppColors.primary,
      ),
      KvTile(label: 'action_id', value: '#${a.actionId}', valueMono: true, dense: true),
      KvTile(label: 'stage', value: a.stage ?? '(空)', dense: true),
      KvTile(label: '状态', value: a.statusLabel, dense: true),
      KvTile(label: '已耗时', value: elapsed, dense: true),
      if (a.isFinished)
        KvTile(
          label: '结果',
          value: a.reasonLabel,
          valueColor: a.outcome == ActionOutcome.success
              ? AppColors.success
              : (a.outcome == ActionOutcome.aborted ? AppColors.neutral : AppColors.error),
          dense: true,
        ),
    ];
  }

  static String _qualityLabel(double? q) {
    if (q == null) return '';
    if (q >= 70) return '优';
    if (q >= 40) return '一般';
    return '差';
  }
}

/// 电量进度环（FR-DASH-01：百分比大号数字 + 进度环；充电中显示闪电）
class _BatteryRing extends StatelessWidget {
  const _BatteryRing({required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).clamp(0, 100).toDouble();
    return SizedBox(
      width: 106,
      height: 106,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: 98,
            height: 98,
            child: CircularProgressIndicator(
              value: v / 100,
              strokeWidth: 8,
              backgroundColor: const Color(0xFFE8EDF3),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                NumFmt.battery(value),
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const Text('电量', style: TextStyle(fontSize: 11, color: AppColors.neutral)),
            ],
          ),
        ],
      ),
    );
  }
}
