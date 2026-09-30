import 'package:flutter/material.dart';

import '../../app_state/services.dart';
import '../../core/network/request_log.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// P09 设置·请求日志（FR-LOG-01~05）。
///
/// 日志页是现场排障与厂商沟通的**唯一证据来源**（开发文档 §8.4）。
class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  String? _methodFilter;
  String? _statusFilter;
  final TextEditingController _path = TextEditingController();
  bool _onlyNonPolling = false;

  @override
  void initState() {
    super.initState();
    widget.services.log.addListener(_onLog);
  }

  @override
  void dispose() {
    widget.services.log.removeListener(_onLog);
    _path.dispose();
    super.dispose();
  }

  void _onLog() {
    if (mounted) setState(() {});
  }

  List<LogEntry> get _filtered {
    final k = _path.text.trim().toLowerCase();
    return widget.services.log.entries.where((LogEntry e) {
      if (_methodFilter != null && e.method != _methodFilter) return false;
      if (_statusFilter != null && e.statusGroup != _statusFilter) return false;
      if (k.isNotEmpty && !e.path.toLowerCase().contains(k)) return false;
      if (_onlyNonPolling && e.polling) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.services.log;
    final list = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text('请求日志（${log.length}/${log.capacity}）'),
        actions: <Widget>[
          IconButton(
            tooltip: '清空',
            onPressed: () {
              log.clear();
              setState(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: '导出文本',
            onPressed: () {
              final text = log.exportText();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已生成导出文本（${text.split('\n').length} 行），可复制给厂商支持。'),
                ),
              );
              debugPrint(text);
            },
            icon: const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _path,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '路径关键字',
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 17),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('仅非轮询', style: TextStyle(fontSize: 11.5)),
                      selected: _onlyNonPolling,
                      onSelected: (bool v) => setState(() => _onlyNonPolling = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _chip('全部方法', _methodFilter == null, () => setState(() => _methodFilter = null)),
                      for (final m in <String>['GET', 'POST', 'PUT', 'DELETE', 'INFO'])
                        _chip(m, _methodFilter == m, () => setState(() => _methodFilter = m)),
                      const SizedBox(width: 10),
                      _chip('全部状态', _statusFilter == null, () => setState(() => _statusFilter = null)),
                      for (final s in <String>['2xx', '4xx', '5xx', '失败'])
                        _chip(s, _statusFilter == s, () => setState(() => _statusFilter = s)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    title: '暂无日志',
                    hint: '每个发出的请求都会在此留痕（时间/方法/路径/状态/耗时）。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                    itemCount: list.length,
                    itemBuilder: (BuildContext ctx, int i) => _row(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: selected ? Colors.white : AppColors.neutral,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _row(LogEntry e) {
    // FR-LOG-05：>2s 标黄，>5s 标红
    final slow = e.slowness;
    final bg = slow == 2
        ? const Color(0xFFFEF2F2)
        : slow == 1
            ? const Color(0xFFFFFBEB)
            : Colors.white;
    final statusColor = e.status == 0
        ? AppColors.error
        : (e.status >= 500
            ? AppColors.error
            : (e.status >= 400 ? AppColors.warning : AppColors.success));

    final t = e.at;
    final timeText =
        '${_2(t.hour)}:${_2(t.minute)}:${_2(t.second)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        title: Row(
          children: <Widget>[
            Text(
              timeText,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.neutral,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF2F7),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                e.method,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Text(
              e.status == 0 ? '失败' : '${e.status}',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: statusColor),
            ),
            const SizedBox(width: 6),
            Text(
              '${e.ms}ms',
              style: TextStyle(
                fontSize: 11,
                color: slow == 0 ? AppColors.neutral : statusColor,
                fontWeight: slow == 0 ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
          ],
        ),
        children: <Widget>[
          if (e.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                e.error!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          if (e.body.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2233),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                e.body,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFDBE9F5),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '${e.polling ? '自动轮询' : '手动触发'} · ${e.statusGroup}',
            style: const TextStyle(fontSize: 11, color: AppColors.neutral),
          ),
        ],
      ),
    );
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';
}
