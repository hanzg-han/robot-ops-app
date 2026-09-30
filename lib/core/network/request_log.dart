import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 一条请求流水（FR-LOG-01）。
class LogEntry {
  LogEntry({
    required this.at,
    required this.method,
    required this.path,
    required this.status,
    required this.ms,
    required this.body,
    this.polling = false,
    this.error,
  });

  final DateTime at;
  final String method;
  final String path;

  /// 0 = 网络层失败
  final int status;

  final int ms;

  /// 响应体文本（可折叠展示）
  final String body;

  /// 是否由自动轮询产生（用于筛选，避免轮询淹没排障信息）
  final bool polling;

  final String? error;

  /// 状态码区间（FR-LOG-02）
  String get statusGroup {
    if (status == 0) return '失败';
    if (status >= 500) return '5xx';
    if (status >= 400) return '4xx';
    if (status >= 300) return '3xx';
    if (status >= 200) return '2xx';
    return '其它';
  }

  /// FR-LOG-05：>2s 标黄，>5s 标红
  int get slowness {
    if (ms > 5000) return 2;
    if (ms > 2000) return 1;
    return 0;
  }

  /// 可直接贴给厂商的文本行（FR-LOG-03）
  String toExportLine() {
    final t = '${at.year}-${_2(at.month)}-${_2(at.day)} '
        '${_2(at.hour)}:${_2(at.minute)}:${_2(at.second)}';
    final code = status == 0 ? 'ERR' : '$status';
    final tail = (error != null && error!.isNotEmpty) ? ' $error' : '';
    return '$t $method $path -> $code ${ms}ms$tail';
  }

  static String _2(int v) => v < 10 ? '0$v' : '$v';
}

/// 请求日志缓冲（FR-LOG-01/04）：仅内存，容量受限，滚动丢弃最早条目。
class RequestLogBuffer extends ChangeNotifierBase {
  RequestLogBuffer({this.capacity = 300});

  int capacity;

  final List<LogEntry> _entries = <LogEntry>[];

  /// 时间倒序（最新在前）的快照
  List<LogEntry> get entries => UnmodifiableListView<LogEntry>(_entries);

  int get length => _entries.length;

  void add(LogEntry entry) {
    _entries.insert(0, entry);
    while (_entries.length > capacity) {
      _entries.removeLast();
    }
    notify();
  }

  /// INFO 提示行（非 HTTP 请求，如「已下发 MoveToAction」）
  void note(String text) {
    add(LogEntry(
      at: DateTime.now(),
      method: 'INFO',
      path: text,
      status: 200,
      ms: 0,
      body: '',
    ));
  }

  void clear() {
    _entries.clear();
    notify();
  }

  /// FR-LOG-03：导出为文本
  String exportText() {
    final buf = StringBuffer()
      ..writeln('# 导诊机器人运维 App 请求日志导出')
      ..writeln('# 生成时间：${DateTime.now()}')
      ..writeln('# 条目数：${_entries.length}')
      ..writeln();
    for (final e in _entries.reversed) {
      buf.writeln(e.toExportLine());
    }
    return buf.toString();
  }
}

/// 极简监听基类：在 ChangeNotifier 之上提供 `notify()` 简写，
/// 便于控制器与日志缓冲共用同一套通知机制。
abstract class ChangeNotifierBase extends ChangeNotifier {
  void notify() => notifyListeners();
}
