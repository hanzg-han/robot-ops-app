import 'package:flutter/material.dart';

import 'app_state/controllers.dart';
import 'app_state/robot_state.dart';
import 'app_state/services.dart';
import 'core/network/api_result.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/num_fmt.dart';
import 'core/utils/time_fmt.dart';
import 'domain/models/event_catalog.dart';
import 'features/connect/connect_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/events/events_page.dart';
import 'features/map/map_page.dart';
import 'features/remote/remote_control_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tasks/tasks_page.dart';
import 'shared/widgets/common.dart';

/// 应用外壳：底部 5 Tab + 顶部状态条 + 全局行为条（PRD §3.1/§3.3）。
class RobotOpsApp extends StatefulWidget {
  const RobotOpsApp({super.key, required this.services});

  final AppServices services;

  @override
  State<RobotOpsApp> createState() => _RobotOpsAppState();
}

class _RobotOpsAppState extends State<RobotOpsApp> {
  late final AppServices s = widget.services;
  late final ActionGate gate = ActionGate(s);
  late final NavigationController navigation = NavigationController(s);
  late final EventsController events = EventsController(s);
  late final PatrolController patrol = PatrolController(s, gate);
  late final RemoteControlController remote = RemoteControlController(s, gate);

  int tabIndex = 0;

  @override
  void initState() {
    super.initState();
    s.state.addListener(_onState);
    events.start();
    // 生命周期（暂停轮询 / 停止遥控）由下方 _PollingLifecycle 统一处理
    // 启动自动连接（FR-CON-06）：有地址则自动检测一次
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }



  /// 启动自动连接 + 连接预检（FR-CON-06/08）
  Future<void> _autoConnect() async {
    s.client.markConnecting();
    final res = await s.client.testConnection();
    if (res.ok) {
      await s.state.runPreflight();
      s.state.start();
    }
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.state.removeListener(_onState);
    events.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = s.state;


    return MaterialApp(
      title: '导诊机器人运维',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Builder(
        builder: (BuildContext ctx) => _Shell(
          services: s,
          gate: gate,
          navigation: navigation,
          events: events,
          patrol: patrol,
          remote: remote,
          tabIndex: tabIndex,
          onTab: (int i) => setState(() => tabIndex = i),

        ),
      ),
      builder: (BuildContext context, Widget? child) {
        // 全局暂停/恢复轮询（页面不可见时暂停，FR-DASH-10）
        return _PollingLifecycle(
          state: state,
          onBackground: () async {
            await remote.onAppBackground();
          },
          onDisconnected: () async {
            await remote.onDisconnected();
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// 首次启动的连接页判定：连接可用则直接进总览（FR-CON-06）
class _Shell extends StatelessWidget {
  const _Shell({
    required this.services,
    required this.gate,
    required this.navigation,
    required this.events,
    required this.patrol,
    required this.remote,
    required this.tabIndex,
    required this.onTab,
  });

  final AppServices services;
  final ActionGate gate;
  final NavigationController navigation;
  final EventsController events;
  final PatrolController patrol;
  final RemoteControlController remote;
  final int tabIndex;
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) {
    final state = services.state;

    final tabs = <Widget>[
      DashboardPage(services: services, gate: gate, navigation: navigation),
      MapPage(
        services: services,
        gate: gate,
        navigation: navigation,
        patrol: patrol,
        remote: remote,
      ),
      TasksPage(
        services: services,
        gate: gate,
        navigation: navigation,
        patrol: patrol,
        onOpenMap: () => onTab(1),
      ),
      EventsPage(services: services, events: events, gate: gate),
      SettingsPage(services: services, remote: remote),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopStatusBar(
              state: state,
              events: events,
              onOpenConnect: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectPage(services: services),
                ),
              ),
              onOpenEvents: () => onTab(3),
            ),
            _NoticeArea(state: state, gate: gate, events: events, onOpenEvents: () => onTab(3)),
            Expanded(
              child: IndexedStack(index: tabIndex, children: tabs),
            ),
            _ActiveActionBar(
              state: state,
              gate: gate,
              patrol: patrol,
              remote: remote,
              onOpenMotion: () => onTab(2),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: onTab,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '总览',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '地图',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle),
            label: '任务',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: '事件',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// 顶部状态条：连接指示灯 + 告警铃铛（PRD §3.3）
class _TopStatusBar extends StatelessWidget {
  const _TopStatusBar({
    required this.state,
    required this.events,
    required this.onOpenConnect,
    required this.onOpenEvents,
  });

  final RobotState state;
  final EventsController events;
  final VoidCallback onOpenConnect;
  final VoidCallback onOpenEvents;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (state.connState) {
      ConnState.connected => AppColors.success,
      ConnState.connecting => AppColors.warning,
      ConnState.slow => AppColors.warning,
      ConnState.disconnected => AppColors.error,
      ConnState.unknown => AppColors.neutral,
    };

    final unread = events.dedupe.unreadCount;
    final badgeLevel = events.dedupe.highestUnreadLevel;
    final badgeColor = badgeLevel == EventLevel.error
        ? AppColors.error
        : badgeLevel == EventLevel.warning
            ? AppColors.warning
            : AppColors.info;

    return Container(
      height: 40,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: onOpenConnect,
            child: Row(
              children: <Widget>[
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  state.connLabel,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Text(
                  state.client.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
                ),
              ],
            ),
          ),
          if (state.connState == ConnState.connecting)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          const Spacer(),
          if (state.strategy != null)
            Text(
              '策略 ${state.strategy}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
            ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onOpenEvents,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                const Icon(Icons.notifications_none, size: 22, color: AppColors.primary),
                if (unread > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 15),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 全局提示区：断连横幅 / 健康告警 / 低电提醒 / 新事件横幅
class _NoticeArea extends StatelessWidget {
  const _NoticeArea({
    required this.state,
    required this.gate,
    required this.events,
    required this.onOpenEvents,
  });

  final RobotState state;
  final ActionGate gate;
  final EventsController events;
  final VoidCallback onOpenEvents;

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[];

    // 断连（FR-CON-07）：红色横幅 + 数据可能过期
    if (state.connState == ConnState.disconnected) {
      banners.add(const NoticeBanner(
        text: '未连接底盘 · 当前显示的数据可能已过期',
        severity: Severity.error,
        actionLabel: '去连接',
      ));
    } else if (state.connState == ConnState.slow) {
      banners.add(const NoticeBanner(
        text: '响应慢：底盘可能正忙或网络不稳定',
        severity: Severity.warning,
        dense: true,
      ));
    }

    // 健康告警（FR-DASH-09）：fatal > error > warning
    final alerts = state.healthAlerts;
    if (alerts.isNotEmpty) {
      final red = alerts.where((a) => a.isRed).toList();
      final first = red.isNotEmpty ? red.first : alerts.first;
      final extra = alerts.length > 1 ? '（共 ${alerts.length} 项）' : '';
      banners.add(NoticeBanner(
        text: '${first.title}$extra · ${first.detail}',
        severity: red.isNotEmpty ? Severity.error : Severity.warning,
        onTap: onOpenEvents,
        actionLabel: '查看',
      ));
    }

    // 低电提醒（FR-DASH-07）：只在跨阈值时出现一次由 Dashboard 负责，这里只做常驻提示
    if (state.isLowBattery) {
      banners.add(NoticeBanner(
        text: '电量 ${NumFmt.battery(state.power?.batteryPercentage)}，'
            '低于 ${state.settings.lowBatteryThreshold}% —— 建议立即回充',
        severity: Severity.warning,
        dense: true,
      ));
    }

    // 新事件横幅（FR-EVT-05）
    final banner = events.bannerText;
    if (banner != null && state.settings.alertBanner) {
      banners.add(NoticeBanner(
        text: banner,
        severity: Severity.warning,
        onTap: () {
          events.dismissBanner();
          onOpenEvents();
        },
        actionLabel: '查看',
        dense: true,
      ));
    }

    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(children: banners.take(3).toList());
  }
}

/// 全局行为条（G02）：动作短名 + 阶段 + 状态 + 已耗时 + 终止（PRD §5.11）
class _ActiveActionBar extends StatelessWidget {
  const _ActiveActionBar({
    required this.state,
    required this.gate,
    required this.patrol,
    required this.remote,
    required this.onOpenMotion,
  });

  final RobotState state;
  final ActionGate gate;
  final PatrolController patrol;
  final RemoteControlController remote;
  final VoidCallback onOpenMotion;

  @override
  Widget build(BuildContext context) {
    // 遥控激活时，行为条切换为红色「遥控中 · 终止」（FR-RC-09）
    if (remote.active) {
      return _bar(
        context,
        background: AppColors.error,
        textColor: Colors.white,
        label: '遥控中',
        detail: '已 ${remote.sessionDurationLabel} · 本次行进 ${remote.travelledMeters.toStringAsFixed(2)} m',
        onAbort: () => remote.stopAll(reason: '行为条终止'),
      );
    }

    final action = state.currentAction;
    final running = action != null && !action.isFinished;

    if (!running) {
      if (state.awaitingActionStatus) {
        return _bar(
          context,
          background: AppColors.neutral,
          textColor: Colors.white,
          label: '已下发，状态获取中…',
          detail: '',
          onAbort: null,
        );
      }
      // 无行为时常驻但置灰；点击给出说明（FR-SAFE-02）
      return _bar(
        context,
        background: const Color(0xFFE2E8F0),
        textColor: AppColors.neutral,
        label: '空闲',
        detail: '当前无正在执行的行为',
        onAbort: null,
      );
    }

    final elapsed = action.createdAt == null
        ? null
        : DateTime.now().difference(action.createdAt!).inSeconds;

    return _bar(
      context,
      background: AppColors.warning,
      textColor: Colors.white,
      label: '${action.shortLabel} · ${action.statusLabel}',
      detail: '${action.shortName} #${action.actionId}'
          '${action.stage == null ? '' : ' · stage ${action.stage}'}'
          '${elapsed == null ? '' : ' · 已 ${elapsed}s'}',
      onAbort: () => gate.abort(),
    );
  }

  Widget _bar(
    BuildContext context, {
    required Color background,
    required Color textColor,
    required String label,
    required String detail,
    required Future<AbortOutcome> Function()? onAbort,
  }) {
    return Material(
      color: background,
      child: InkWell(
        onTap: onOpenMotion,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              if (onAbort != null)
                FilledButton(
                  onPressed: () async {
                    final outcome = await onAbort();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(outcome.message)),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.error,
                    minimumSize: const Size(86, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('■ 终止', style: TextStyle(fontWeight: FontWeight.w700)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '■ 终止',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 生命周期观察：切后台/锁屏时停止遥控并暂停轮询（FR-RC-06 / FR-DASH-10）
class _PollingLifecycle extends StatefulWidget {
  const _PollingLifecycle({
    required this.state,
    required this.onBackground,
    required this.onDisconnected,
    required this.child,
  });

  final RobotState state;
  final Future<void> Function() onBackground;
  final Future<void> Function() onDisconnected;
  final Widget child;

  @override
  State<_PollingLifecycle> createState() => _PollingLifecycleState();
}

class _PollingLifecycleState extends State<_PollingLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addConnListener(_conn);
  }

  @override
  void dispose() {
    widget.state.removeConnListener(_conn);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _conn(ConnState s) {
    if (s == ConnState.disconnected) {
      widget.onDisconnected();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        widget.state.setVisible(true);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.state.setVisible(false);
        widget.onBackground();
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
