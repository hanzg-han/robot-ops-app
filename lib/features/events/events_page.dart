import 'package:flutter/material.dart';

import '../../app_state/controllers.dart';
import '../../app_state/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dto/models.dart';
import '../../domain/models/event_catalog.dart';
import '../../domain/services/event_dedupe.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/confirm_danger.dart';

/// P07 事件（PRD §5.8；FR-EVT-01~09）。
///
/// 健康告警**置顶作为实时卡片**，与事件流并列不混入列表（D7 决策）；
/// 未收录类型按关键词推断级别并显示原文。
class EventsPage extends StatefulWidget {
  const EventsPage({
    super.key,
    required this.services,
    required this.events,
    required this.gate,
  });

  final AppServices services;
  final EventsController events;
  final ActionGate gate;

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  @override
  void initState() {
    super.initState();
    widget.events.addListener(_onState);
    widget.services.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.events.removeListener(_onState);
    widget.services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _abort() async {
    final outcome = await widget.gate.abort();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.message)));
  }

  Future<void> _goHome() async {
    final s = widget.services;
    final ok = await ConfirmDanger.show(
      context,
      const ConfirmRequest(
        title: '确认让机器人回充？',
        actionName: 'GoHomeAction',
        targetName: '充电桩',
        extraLines: <String>['来自事件联动入口。'],
        riskNote: '请确认充电位及行进路径无人、无障碍物。',
        confirmLabel: '确认回充',
      ),
    );
    if (!ok) return;
    final res = await widget.gate.dispatchGoHome(
      flags: 'dock',
      backToLanding: true,
      retryCount: 2,
      mode: 0,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    await s.state.refreshNow();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final events = widget.events;
    final state = s.state;
    final list = events.visibleEvents;

    return Column(
      children: <Widget>[
        // 工具条
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: <Widget>[
              _filterChip('全部', events.levelFilter.isEmpty, () {
                events.setFilter(<EventLevel>{});
              }),
              _filterChip('错误', events.levelFilter.contains(EventLevel.error), () {
                _toggle(EventLevel.error);
              }),
              _filterChip('警告', events.levelFilter.contains(EventLevel.warning), () {
                _toggle(EventLevel.warning);
              }),
              _filterChip('信息', events.levelFilter.contains(EventLevel.info), () {
                _toggle(EventLevel.info);
              }),
              const Spacer(),
              Text(
                '${events.dedupe.length} 条 · 未读 ${events.dedupe.unreadCount}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (String v) {
                  if (v == 'read') events.markAllRead();
                  if (v == 'clear') events.clearRead();
                },
                itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'read', child: Text('全部标记已读')),
                  PopupMenuItem<String>(value: 'clear', child: Text('清空本地已读记录')),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: <Widget>[
              // 健康告警卡（置顶实时，不混入列表）
              SectionCard(
                title: '设备健康告警（实时）',
                child: state.healthAlerts.isEmpty
                    ? const Row(
                        children: <Widget>[
                          Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                          SizedBox(width: 6),
                          Text('无告警', style: TextStyle(fontSize: 13.5)),
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
                                        a.isRed
                                            ? Icons.error_outline
                                            : Icons.warning_amber_outlined,
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

              SectionCard(
                title: '事件流',
                trailing: Text(
                  '仅本机记录，重装即清空',
                  style: const TextStyle(fontSize: 11, color: AppColors.neutral),
                ),
                child: list.isEmpty
                    ? const EmptyState(
                        title: '暂无事件',
                        hint: '底盘无历史事件接口，App 只能记录连接期间收到的事件。',
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: list.map((RobotEvent e) {
                          final color = _levelColor(e.level);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                left: BorderSide(color: color, width: 3),
                                top: const BorderSide(color: AppColors.line),
                                right: const BorderSide(color: AppColors.line),
                                bottom: const BorderSide(color: AppColors.line),
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                              title: Row(
                                children: <Widget>[
                                  Text(
                                    events.timeLabel(e),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                    text: e.level.label,
                                    color: color,
                                    filled: e.level == EventLevel.error,
                                  ),
                                  const Spacer(),
                                  if (!e.read)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: AppColors.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  '${e.type} · ${e.description}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                              onExpansionChanged: (bool open) {
                                if (open) widget.events.dedupe.markRead(e);
                              },
                              children: <Widget>[
                                _detailRow('原始 type', e.type),
                                _detailRow('原始 timestamp（机器毫秒）',
                                    e.timestamp.toStringAsFixed(0)),
                                _detailRow('换算时间', TimeFmtHelper.eventTime(
                                  eventTimestampMs: e.timestamp,
                                  machineTimestampMs: events.machineTimestampMs,
                                  sampledAt: events.machineTimestampAt,
                                )),
                                _detailRow('级别推断',
                                    '${e.level.label}（${EventCatalog.isKnown(e.type) ? '已收录' : '按关键词推断'}）'),
                                _detailRow('去重键', e.dedupeKey),
                                if (EventCatalog.suggestionOf(e.type) != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () {
                                              final sug = EventCatalog.suggestionOf(e.type)!;
                                              switch (sug.kind) {
                                                case SuggestionKind.goHome:
                                                  _goHome();
                                                case SuggestionKind.abort:
                                                  _abort();
                                                case SuggestionKind.openMap:
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('请到「地图」页查看定位质量与位姿。'),
                                                    ),
                                                  );
                                              }
                                            },
                                            child: Text('建议动作：${EventCatalog.suggestionOf(e.type)!.action}'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggle(EventLevel level) {
    final next = <EventLevel>{...widget.events.levelFilter};
    if (next.contains(level)) {
      next.remove(level);
    } else {
      next.add(level);
    }
    widget.events.setFilter(next);
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected ? Colors.white : AppColors.neutral,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static Color _levelColor(EventLevel level) {
    switch (level) {
      case EventLevel.error:
        return AppColors.error;
      case EventLevel.warning:
        return AppColors.warning;
      case EventLevel.info:
        return AppColors.info;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 128,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.neutral)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
