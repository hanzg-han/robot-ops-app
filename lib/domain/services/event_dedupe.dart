import '../models/event_catalog.dart';

/// 一条事件（本地模型）。
///
/// [timestamp] 为**机器运行毫秒**（不是墙钟时间），显示时需经基准换算（FR-EVT-02）。
class RobotEvent {
  RobotEvent({
    required this.type,
    required this.timestamp,
    this.firstSeenAt,
    this.read = false,
  });

  final String type;
  final double timestamp;

  /// 本地首次见到该事件的时刻（用于换算基准缺失时的退化显示）
  final DateTime? firstSeenAt;

  /// 是否已读（FR-EVT-07：清空/已读只影响本地记录）
  bool read;

  EventLevel get level => EventCatalog.levelOf(type);

  String get description => EventCatalog.describe(type);

  /// 去重键（开发文档 §15.2）：type#timestamp
  String get dedupeKey => dedupeKeyOf(type, timestamp);

  static String dedupeKeyOf(String type, double? timestamp) {
    if (timestamp == null || timestamp.isNaN) return type;
    return '$type#${timestamp.toStringAsFixed(3)}';
  }
}

/// 事件去重与本地留存（FR-EVT-03 / FR-EVT-09 / 开发文档 §15.2）。
///
/// 事件会**长期驻留**在底盘返回列表中；若不去重，列表会不断膨胀、横幅会反复弹。
/// 因此必须按 `type#timestamp` 去重，并限制本地留存条数（默认 500）。
class EventDedupe {
  EventDedupe({this.capacity = 500});

  /// 本地留存上限（FR-EVT-09）
  final int capacity;

  final List<RobotEvent> _events = <RobotEvent>[];
  final Set<String> _keys = <String>{};

  /// 时间倒序（最新在前）
  List<RobotEvent> get events => List<RobotEvent>.unmodifiable(_events);

  int get length => _events.length;

  /// 已读状态：未读条数
  int get unreadCount => _events.where((e) => !e.read).length;

  /// 未读中的最高级别（用于铃铛徽标着色，PRD §3.3）
  EventLevel? get highestUnreadLevel {
    EventLevel? best;
    for (final e in _events) {
      if (e.read) continue;
      if (best == null || e.level.weight > best.weight) best = e.level;
    }
    return best;
  }

  /// 合并一批事件（兼容数组 / {events:[…]} / 单对象三种结构）。
  ///
  /// 返回**本次真正新增**的事件（用于弹横幅；FR-EVT-05 同类重复不重复弹）。
  List<RobotEvent> merge(dynamic raw, {DateTime? now}) {
    final parsed = parseEvents(raw);
    final fresh = <RobotEvent>[];
    final stamp = now ?? DateTime.now();

    for (final e in parsed) {
      final key = e.dedupeKey;
      if (_keys.contains(key)) continue;
      _keys.add(key);
      final event = RobotEvent(
        type: e.type,
        timestamp: e.timestamp,
        firstSeenAt: stamp,
      );
      _events.insert(0, event);
      fresh.add(event);
    }

    // 容量控制：滚动丢弃最早条目
    while (_events.length > capacity) {
      final removed = _events.removeLast();
      _keys.remove(removed.dedupeKey);
    }

    // 时间倒序（同 timestamp 保持稳定）
    _events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return fresh;
  }

  /// 兼容三种响应结构（FR-EVT-01）
  static List<RobotEvent> parseEvents(dynamic raw) {
    final list = <RobotEvent>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final e = _fromMap(Map<String, dynamic>.from(item));
        if (e != null) list.add(e);
      }
      return list;
    }

    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      final nested = json['events'];
      if (nested is List) {
        for (final item in nested) {
          if (item is! Map) continue;
          final e = _fromMap(Map<String, dynamic>.from(item));
          if (e != null) list.add(e);
        }
        return list;
      }
      // 单对象形态
      final single = _fromMap(json);
      if (single != null) list.add(single);
    }

    return list;
  }

  static RobotEvent? _fromMap(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) return null;
    final ts = json['timestamp'];
    double? timestamp;
    if (ts is num) {
      timestamp = ts.toDouble();
    } else if (ts is String) {
      timestamp = double.tryParse(ts.trim());
    }
    if (timestamp == null) return null;
    return RobotEvent(type: type, timestamp: timestamp);
  }

  /// FR-EVT-07：按级别筛选（可多选）
  List<RobotEvent> filterByLevels(Set<EventLevel> levels) {
    if (levels.isEmpty) return events;
    return _events.where((e) => levels.contains(e.level)).toList();
  }

  /// FR-EVT-07：清空本地已读记录（不影响底盘侧数据）
  void clearRead() {
    _events.removeWhere((e) => e.read);
    _keys.clear();
    for (final e in _events) {
      _keys.add(e.dedupeKey);
    }
  }

  void clearAll() {
    _events.clear();
    _keys.clear();
  }

  void markAllRead() {
    for (final e in _events) {
      e.read = true;
    }
  }

  void markRead(RobotEvent event) => event.read = true;

  bool contains(String type, double timestamp) =>
      _keys.contains(RobotEvent.dedupeKeyOf(type, timestamp));
}
