import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import 'about_page.dart';
import 'dock_page.dart';
import 'log_page.dart';

/// P08 设置（PRD §5.9；FR-SET-01~06）。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services, required this.remote});

  final AppServices services;
  final RemoteControlController remote;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    widget.services.settings.addListener(_onState);
    widget.services.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.services.settings.removeListener(_onState);
    widget.services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final settings = s.settings;
    final state = s.state;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: <Widget>[
        SectionCard(
          title: '连接设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              KvTile(label: '底盘地址', value: settings.baseUrl, dense: true),
              KvTile(
                label: '连接状态',
                value: '${state.connLabel} · ${TimeFmtAgo.of(s.client.lastSuccessAt)}',
                valueColor: state.isConnected ? AppColors.success : AppColors.error,
                dense: true,
              ),
              KvTile(
                label: '超时',
                value: '${settings.timeoutMs ~/ 1000} s（地图/搜路 '
                    '${settings.longTimeoutMs ~/ 1000} s）',
                dense: true,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConnSettingsPage(services: s),
                  ),
                ),
                icon: const Icon(Icons.lan_outlined, size: 18),
                label: const Text('地址 / 超时 / 自动轮询'),
              ),
            ],
          ),
        ),

        SectionCard(
          title: '充电桩',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KvTile(
                label: '状态',
                value: state.hasDock ? '已设置' : '未设置',
                valueColor: state.hasDock ? AppColors.success : AppColors.warning,
                dense: true,
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => DockPage(services: s)),
                ),
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: const Text('充电桩标定'),
              ),
            ],
          ),
        ),

        SectionCard(
          title: '告警设置',
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('低电阈值', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.lowBatteryThreshold.toDouble(),
                      min: 5,
                      max: 80,
                      divisions: 15,
                      label: '${settings.lowBatteryThreshold}%',
                      onChanged: (double v) => settings.setLowBatteryThreshold(v.round()),
                    ),
                  ),
                  Text('${settings.lowBatteryThreshold}%', style: const TextStyle(fontSize: 13)),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('告警横幅', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  '关闭后事件页仍记录（仅不弹横幅）',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: settings.alertBanner,
                onChanged: settings.setAlertBanner,
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('提示音', style: TextStyle(fontSize: 13.5)),
                value: settings.alertSound,
                onChanged: settings.setAlertSound,
              ),
            ],
          ),
        ),

        SectionCard(
          title: '显示与单位',
          child: Column(
            children: <Widget>[
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('角度以「度」显示', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text(
                  '内部一律按弧度下发（D6 决策）',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: settings.angleInDegrees,
                onChanged: settings.setAngleInDegrees,
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('坐标小数位', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 2, label: Text('2 位')),
                        ButtonSegment<int>(value: 3, label: Text('3 位')),
                      ],
                      selected: <int>{settings.coordDecimals == 2 ? 2 : 3},
                      onSelectionChanged: (Set<int> v) => settings.setCoordDecimals(v.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('地图默认取景', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(value: 'all', label: Text('整图')),
                        ButtonSegment<String>(value: 'robot', label: Text('居中机器人')),
                      ],
                      selected: <String>{settings.mapDefaultFit},
                      onSelectionChanged: (Set<String> v) => settings.setMapDefaultFit(v.first),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SectionCard(
          title: '遥控节奏（建图用）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('下发间隔', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.rcIntervalMs.toDouble(),
                      min: 50,
                      max: 300,
                      divisions: 10,
                      label: '${settings.rcIntervalMs} ms',
                      onChanged: (double v) => settings.setRcTuning(intervalMs: v.round()),
                    ),
                  ),
                  Text('${settings.rcIntervalMs} ms', style: const TextStyle(fontSize: 12)),
                ],
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('单次 duration', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.rcDurationMs.toDouble(),
                      min: 100,
                      max: 500,
                      divisions: 8,
                      label: '${settings.rcDurationMs} ms',
                      onChanged: (double v) => settings.setRcTuning(durationMs: v.round()),
                    ),
                  ),
                  Text('${settings.rcDurationMs} ms', style: const TextStyle(fontSize: 12)),
                ],
              ),
              const NoticeBanner(
                text: 'FR-RC-04 要求：下发间隔 ≤300 ms、单次 duration ≤500 ms。'
                    '单次取短值可让丢包时的最坏停止延迟有界。',
                severity: Severity.info,
                dense: true,
              ),
            ],
          ),
        ),

        SectionCard(
          title: '日志与诊断',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KvTile(
                label: '请求日志',
                value: '最近 ${settings.logCapacity} 条'
                    '（当前 ${s.log.length} 条）',
                dense: true,
              ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 92,
                    child: Text('日志容量', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                  ),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 100, label: Text('100')),
                        ButtonSegment<int>(value: 300, label: Text('300')),
                        ButtonSegment<int>(value: 1000, label: Text('1000')),
                      ],
                      selected: <int>{
                        AppConfig.defaultLogCapacity,
                      }.contains(settings.logCapacity)
                          ? <int>{AppConfig.defaultLogCapacity}
                          : <int>{settings.logCapacity},
                      onSelectionChanged: (Set<int> v) => settings.setLogCapacity(v.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => LogPage(services: s)),
                ),
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('请求日志'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final header = settings.diagnosticHeader(
                    model: state.robotInfo?.modelLabel ?? '—',
                    firmware: state.robotInfo?.softwareVersion ?? '—',
                  );
                  final tail = s.log.exportText().split('\n').take(24).join('\n');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('诊断信息已生成（可复制）：\n$header'),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                  // 保持 tail 引用，便于后续接入系统剪贴板
                  debugPrint('$header\n$tail');
                },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('诊断信息一键复制（地址/机型/固件/日志）'),
              ),
            ],
          ),
        ),

        SectionCard(
          title: '其他',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('关于', style: TextStyle(fontSize: 13.5)),
                trailing: Text(
                  'v${AppConfig.appVersion}',
                  style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => AboutPage(services: s)),
                ),
              ),
              const Divider(),
              const Text(
                '本地 PIN 锁（FR-SET-04）默认关闭，列为 P2：'
                '底盘接口无鉴权，v1.0 以「二次确认 + 日志可追溯」控制风险；'
                'Q8 已确认单人不公用，PIN 仅作可选加层。',
                style: TextStyle(fontSize: 12, color: AppColors.neutral, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 连接子页（FR-SET-01：与连接页配置同源）
class ConnSettingsPage extends StatefulWidget {
  const ConnSettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ConnSettingsPage> createState() => _ConnSettingsPageState();
}

class _ConnSettingsPageState extends State<ConnSettingsPage> {
  late final TextEditingController _addr =
      TextEditingController(text: widget.services.settings.baseUrl);
  String? _result;

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final s = widget.services;
    await s.settings.setBaseUrl(_addr.text);
    _addr.text = s.settings.baseUrl;
    s.applySettingsToClient();
    s.client.markConnecting();
    final res = await s.client.testConnection();
    if (!mounted) return;
    setState(() {
      _result = res.ok
          ? '连接成功 · 耗时 ${res.ms} ms'
          : (res.error ?? '连接失败（HTTP ${res.status}）');
    });
    if (res.ok) {
      await s.state.runPreflight();
      s.state.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('连接设置')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          SectionCard(
            title: '底盘地址',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _addr,
                  decoration: const InputDecoration(
                    hintText: '192.168.0.16:1448',
                    labelText: 'IP:端口 或 http://IP:端口',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存并测试连接'),
                ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _result!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _result!.startsWith('连接成功')
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: '超时与轮询',
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 92,
                      child: Text('超时', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
                    ),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: AppConfig.timeoutOptions.contains(settings.timeoutMs)
                            ? settings.timeoutMs
                            : AppConfig.defaultTimeoutMs,
                        items: AppConfig.timeoutOptions
                            .map((int v) => DropdownMenuItem<int>(
                                  value: v,
                                  child: Text('${v ~/ 1000} s'),
                                ))
                            .toList(),
                        onChanged: (int? v) async {
                          if (v == null) return;
                          await settings.setTimeoutMs(v);
                          widget.services.applySettingsToClient();
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动轮询', style: TextStyle(fontSize: 13.5)),
                  subtitle: const Text(
                    '关闭后所有轮询停止；下拉刷新仍可手动刷新',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: settings.autoPoll,
                  onChanged: (bool v) async {
                    await settings.setAutoPoll(v);
                    widget.services.applySettingsToClient();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const NoticeBanner(
            text: '本 App 仅支持同网段局域网直连，不做云转发，无 Mock 数据源。',
            severity: Severity.info,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// 相对时间（避免设置页直接依赖 core/utils）
class TimeFmtAgo {
  const TimeFmtAgo._();

  static String of(DateTime? t) {
    if (t == null) return '从未更新';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 1) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${diff.inHours} 小时前';
  }
}
