import 'dart:typed_data';

/// 统一返回包装（开发文档 §8.2）。
///
/// [status] 为 0 表示网络/连接层失败（未拿到 HTTP 状态码）。
class ApiResult<T> {
  const ApiResult({
    required this.ok,
    required this.status,
    required this.ms,
    this.data,
    this.error,
    this.raw,
  });

  /// HTTP 2xx
  final bool ok;

  /// HTTP 状态码；0 = 网络层失败
  final int status;

  /// 耗时（ms）
  final int ms;

  final T? data;

  /// 中文错误说明（连接失败 / 超时 / HTTP 4xx-5xx），可直接展示
  final String? error;

  /// 原始响应文本（JSON 解析失败时保留，供「响应格式异常」查看原文）
  final String? raw;

  /// 无行为 / 未设置 homepose 等语义上属正常状态的 404（开发文档 §17 坑 8、12）
  bool get isNotFound => status == 404;

  /// 搜路失败：目标不可达或被占据（开发文档 §17 坑 9）
  bool get isSearchPathUnreachable => status == 500;

  /// 仅凭状态码无法判定「是否真的终止了什么」（PRD §14.2 Q4 / F7）
  bool get isTransportFailure => status == 0;

  ApiResult<R> cast<R>(R? Function(T? value) map) => ApiResult<R>(
        ok: ok,
        status: status,
        ms: ms,
        data: map(data),
        error: error,
        raw: raw,
      );

  static ApiResult<Uint8List> bytes({
    required bool ok,
    required int status,
    required int ms,
    Uint8List? data,
    String? error,
  }) =>
      ApiResult<Uint8List>(
        ok: ok,
        status: status,
        ms: ms,
        data: data,
        error: error,
      );
}

/// 连接状态（PRD §3.4）
enum ConnState {
  /// 尚未检测
  unknown,

  /// 正在检测 / 测试连接中
  connecting,

  /// 已连接
  connected,

  /// 超时或弱网（连续 1 次超时）
  slow,

  /// 未连接（连续 ≥2 次失败，或地址为空）
  disconnected,
}

extension ConnStateLabel on ConnState {
  String get label {
    switch (this) {
      case ConnState.connected:
        return '已连接';
      case ConnState.connecting:
        return '连接中';
      case ConnState.slow:
        return '响应慢';
      case ConnState.disconnected:
        return '未连接';
      case ConnState.unknown:
        return '未连接';
    }
  }
}
