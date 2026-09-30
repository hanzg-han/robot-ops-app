import 'package:flutter/material.dart';

import '../../app_state/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/num_fmt.dart';
import '../../data/dto/models.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';

/// P10 设置·充电桩（FR-MOT-08 / FR-MOT-01）。
class DockPage extends StatefulWidget {
  const DockPage({super.key, required this.services});

  final AppServices services;

  @override
  State<DockPage> createState() => _DockPageState();
}

class _DockPageState extends State<DockPage> {
  @override
  void initState() {
    super.initState();
    widget.services.state.addListener(_onState);
    widget.services.state.refreshSlow();
  }

  @override
  void dispose() {
    widget.services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _register() async {
    final state = widget.services.state;
    final pose = state.pose;
    final ok = await ConfirmDanger.show(
      context,
      ConfirmRequest(
        title: '把当前位置注册为充电桩？',
        actionName: 'POST homedocks/:register',
        targetName: '当前机器人位置',
        coordinates: pose == null
            ? '—'
            : 'x ${NumFmt.coord(pose.x)}, y ${NumFmt.coord(pose.y)}, ${NumFmt.angleDeg(pose.yaw)}',
        extraLines: <String>[
          '当前充电桩：${state.homepose == null ? '未设置' : '已设置'}',
          '已注册桩数量：${state.docks.length}',
        ],
        riskNote: '标定会覆盖现有充电桩位置，影响自动回充。请确认机器人已推到充电位。',
        confirmLabel: '确认注册',
      ),
    );
    if (!ok) return;

    final res = await widget.services.artifact.registerDock();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? '注册成功，回充入口已可用。' : (res.error ?? '注册失败'))),
    );
    await state.refreshSlow();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.services.state;
    final home = state.homepose;

    return Scaffold(
      appBar: AppBar(title: const Text('充电桩')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          SectionCard(
            title: home != null || state.docks.isNotEmpty ? '已设置' : '未设置',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                KvTile(
                  label: '充电桩位姿',
                  value: home == null
                      ? '—'
                      : 'x = ${NumFmt.coord(home.x)}　y = ${NumFmt.coord(home.y)}\n'
                          'yaw = ${NumFmt.angleDeg(home.yaw)}',
                  valueMono: true,
                ),
                KvTile(
                  label: '来源',
                  value: home != null
                      ? 'homepose'
                      : (state.docks.isNotEmpty ? 'homedocks（已注册）' : '未设置'),
                  dense: true,
                ),
                const SizedBox(height: 6),
                if (state.docks.isNotEmpty) ...<Widget>[
                  const Text(
                    '已注册桩列表',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  ...state.docks.map((Dock d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.home_outlined, size: 15, color: AppColors.dock),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${d.displayName} · (${NumFmt.coord(d.pose.x)}, '
                                '${NumFmt.coord(d.pose.y)})',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      )),
                ] else
                  const Text(
                    '未检测到已注册的 homedock。',
                    style: TextStyle(fontSize: 12.5, color: AppColors.neutral),
                  ),
                const SizedBox(height: 8),
                Text(
                  '机器人当前位姿：${state.pose == null ? '—' : '${NumFmt.coord(state.pose!.x)}, ${NumFmt.coord(state.pose!.y)}'}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.neutral),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _register,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('⌖ 把当前位置注册为充电桩'),
          ),
          const SizedBox(height: 10),
          const NoticeBanner(
            text: '标定会覆盖现有充电桩位置，影响自动回充。请确认机器人已推到充电位。',
            severity: Severity.warning,
            dense: true,
          ),
          const SizedBox(height: 10),
          const NoticeBanner(
            text: 'homepose 未设置时回充会直接失败，因此 App 在 UI 层提前拦截并置灰回充入口。',
            severity: Severity.info,
            dense: true,
          ),
        ],
      ),
    );
  }
}
