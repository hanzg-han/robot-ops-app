import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'api_endpoints.dart';
import 'api_result.dart';
import 'request_log.dart';

/// 底盘 HTTP 客户端（开发文档 §8 网络层设计）。
///
/// 职责：
/// - 地址规范化（[normalizeBase]），自动补 `http://`、去首尾空白与结尾斜杠；
/// - 统一超时（常规 8s / 地图与搜路 15s，均可配）；
/// - JSON 自动解析，失败时保留原始字符串（FR：响应格式异常可查看原文）；
/// - 写入请求日志缓冲（日志页数据源）；
/// - 错误信息中文化（连接失败 / 超时 / HTTP 状态码）。
class ApiClient {
  ApiClient({required this.log});

  final RequestLogBuffer log;

  Dio? _dio;
  String _baseUrl = AppConfig.defaultBaseUrl;
  int _timeoutMs = AppConfig.defaultTimeoutMs;
  int _longTimeoutMs = AppConfig.defaultLongTimeoutMs;

  String get baseUrl => _baseUrl;
  int get timeoutMs => _timeoutMs;
  int get longTimeoutMs => _longTimeoutMs;

  // ------------------------------------------------------------- 连接状态
  ConnState _connState = ConnState.unknown;
  ConnState get connState => _connState;

  DateTime? _lastSuccessAt;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// 连续失败次数（判定「未连接」：连续 ≥2 次失败，PRD §3.4）
  int _consecutiveFailures = 0;

  /// 连续超时次数（判定「响应慢」：连续 1 次超时，PRD §3.4）
  int _consecutiveTimeouts = 0;

  final List<void Function(ConnState)> _connListeners = <void Function(ConnState)>[];
  void addConnListener(void Function(ConnState) l) => _connListeners.add(l);
  void removeConnListener(void Function(ConnState) l) => _connListeners.remove(l);

  void _setConnState(ConnState s) {
    if (_connState == s) return;
    _connState = s;
    for (final l in List<void Function(ConnState)>.from(_connListeners)) {
      l(s);
    }
  }

  /// 外部（如连接页）标记「正在连接」
  void markConnecting() => _setConnState(ConnState.connecting);

  /// 数据是否可能过期（>10s 无成功响应，PRD §3.4「数据过期」）
  bool get isStale {
    final t = _lastSuccessAt;
    if (t == null) return true;
    return DateTime.now().difference(t).inSeconds > 10;
  }

  /// 数据已过期秒数；无成功记录时返回 null
  int? get staleSeconds {
    final t = _lastSuccessAt;
    if (t == null) return null;
    return DateTime.now().difference(t).inSeconds;
  }

  // ------------------------------------------------------------ 配置更新
  void configure({String? baseUrl, int? timeoutMs, int? longTimeoutMs}) {
    if (baseUrl != null) {
      _baseUrl = normalizeBase(baseUrl);
      _dio = null; // 重建以避免缓存旧 baseUrl
    }
    if (timeoutMs != null) _timeoutMs = timeoutMs;
    if (longTimeoutMs != null) _longTimeoutMs = longTimeoutMs;
  }

  /// 地址规范化（开发文档 §8.1，已验证规则原样搬用）
  static String normalizeBase(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return AppConfig.defaultBaseUrl;
    if (!RegExp(r'^https?://').hasMatch(s)) s = 'http://$s';
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  Dio get _client {
    final existing = _dio;
    if (existing != null) return existing;
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: Duration(milliseconds: _timeoutMs),
      receiveTimeout: Duration(milliseconds: _timeoutMs),
      // 404 / 500 / 4xx-5xx 都交给业务判定，不抛异常
      validateStatus: (int? code) => code != null && code >= 200 && code < 600,
      responseType: ResponseType.plain,
      headers: <String, dynamic>{'Accept': 'application/json'},
    ));
    _dio = dio;
    return dio;
  }

  // ---------------------------------------------------------------- 请求
  /// 发起请求。[polling] 标记该请求来自自动轮询。
  Future<ApiResult<dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool longTimeout = false,
    bool polling = false,
    bool binary = false,
  }) async {
    final ms = longTimeout ? _longTimeoutMs : _timeoutMs;
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: binary ? ResponseType.bytes : ResponseType.plain,
          sendTimeout: Duration(milliseconds: ms),
          receiveTimeout: Duration(milliseconds: ms),
        ),
      );

      stopwatch.stop();
      final status = response.statusCode ?? 0;
      final elapsed = stopwatch.elapsedMilliseconds;

      if (binary) {
        final rawData = response.data;
        final Uint8List? bytes = rawData is Uint8List
            ? rawData
            : rawData is List<int>
                ? Uint8List.fromList(rawData)
                : null;
        _afterRequest(status: status, path: path, method: method, ms: elapsed, polling: polling, bodyText: bytes == null ? '' : '<二进制 ${bytes.length} 字节>');
        return ApiResult<Uint8List>(
          ok: status >= 200 && status < 300,
          status: status,
          ms: elapsed,
          data: bytes,
          error: status >= 400 ? _httpErrorMessage(status) : null,
        );
      }

      final text = _asText(response.data);
      dynamic parsed;
      var parseFailed = false;
      if (text.isEmpty) {
        parsed = null;
      } else {
        try {
          parsed = jsonDecode(text);
        } catch (_) {
          parsed = text; // FR：解析失败保留原始字符串
          parseFailed = true;
        }
      }

      _afterRequest(
        status: status,
        path: path,
        method: method,
        ms: elapsed,
        polling: polling,
        bodyText: text.length > 4000 ? '${text.substring(0, 4000)}…（已截断）' : text,
      );

      return ApiResult<dynamic>(
        ok: status >= 200 && status < 300,
        status: status,
        ms: elapsed,
        data: parsed,
        error: status >= 400
            ? _httpErrorMessage(status)
            : (parseFailed ? '响应格式异常' : null),
        raw: parseFailed ? text : null,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final message = _dioErrorMessage(e, path, ms);
      final isTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;

      _afterRequest(
        status: 0,
        path: path,
        method: method,
        ms: elapsed,
        polling: polling,
        bodyText: message,
        error: message,
        isTimeout: isTimeout,
      );

      return ApiResult<dynamic>(
        ok: false,
        status: 0,
        ms: elapsed,
        error: message,
      );
    } catch (e) {
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;
      final message = '请求异常：$e';
      _afterRequest(
        status: 0,
        path: path,
        method: method,
        ms: elapsed,
        polling: polling,
        bodyText: message,
        error: message,
      );
      return ApiResult<dynamic>(ok: false, status: 0, ms: elapsed, error: message);
    }
  }

  Future<ApiResult<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool longTimeout = false,
    bool polling = false,
  }) =>
      request('GET', path, query: query, longTimeout: longTimeout, polling: polling);

  Future<ApiResult<dynamic>> post(
    String path, {
    Object? body,
    bool longTimeout = false,
    bool polling = false,
  }) =>
      request('POST', path, body: body, longTimeout: longTimeout, polling: polling);

  Future<ApiResult<dynamic>> put(
    String path, {
    Object? body,
    bool longTimeout = false,
    bool polling = false,
  }) =>
      request('PUT', path, body: body, longTimeout: longTimeout, polling: polling);

  Future<ApiResult<dynamic>> delete(
    String path, {
    bool longTimeout = false,
    bool polling = false,
  }) =>
      request('DELETE', path, longTimeout: longTimeout, polling: polling);

  Future<ApiResult<Uint8List>> getBytes(
    String path, {
    bool longTimeout = true,
    bool polling = false,
  }) async {
    final r = await request('GET', path,
        longTimeout: longTimeout, polling: polling, binary: true);
    return ApiResult<Uint8List>(
      ok: r.ok,
      status: r.status,
      ms: r.ms,
      data: r.data is Uint8List ? r.data as Uint8List : null,
      error: r.error,
    );
  }

  // ------------------------------------------------------------ 连接检测
  /// 连接预检（FR-CON-03/06/08）：GET capabilities
  Future<ApiResult<dynamic>> testConnection() =>
      get(ApiEndpoints.capabilities);

  // ---------------------------------------------------------------- 内部
  void _afterRequest({
    required int status,
    required String path,
    required String method,
    required int ms,
    required bool polling,
    required String bodyText,
    String? error,
    bool isTimeout = false,
  }) {
    final ok = status >= 200 && status < 300;
    final now = DateTime.now();

    log.add(LogEntry(
      at: now,
      method: method,
      path: path,
      status: status,
      ms: ms,
      body: bodyText,
      polling: polling,
      error: error,
    ));

    if (isTimeout) {
      _consecutiveTimeouts++;
    } else if (ok) {
      _consecutiveTimeouts = 0;
    }

    if (ok) {
      _lastSuccessAt = now;
      _consecutiveFailures = 0;
      _setConnState(ConnState.connected);
      return;
    }

    // 404 属正常业务状态（无行为 / 未设置 homepose / 无 POI）：
    // 说明链路是通的，不应计入断连判定（开发文档 §17 坑 8、12）。
    if (status == 404) {
      _lastSuccessAt = now;
      _consecutiveFailures = 0;
      _setConnState(ConnState.connected);
      return;
    }

    // 4xx 也说明网络可达（服务已就绪，只是请求有问题）
    if (status >= 400 && status < 500) {
      _lastSuccessAt = now;
      _consecutiveFailures = 0;
      _setConnState(ConnState.connected);
      return;
    }

    // status == 0（网络层失败）或 5xx
    if (isTimeout && _consecutiveFailures < 1) {
      _setConnState(ConnState.slow);
      return;
    }

    _consecutiveFailures++;
    if (_consecutiveFailures >= 2 || status == 0) {
      _setConnState(ConnState.disconnected);
    } else {
      _setConnState(ConnState.slow);
    }
  }

  static String _asText(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is Uint8List) return '<二进制 ${data.length} 字节>';
    if (data is List<int>) return '<二进制 ${data.length} 字节>';
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  /// 错误文案三分类（FR-CON-03：连接失败 / 超时 / HTTP 4xx-5xx）
  String _dioErrorMessage(DioException e, String path, int ms) {
    final url = '$_baseUrl$path';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '请求超时（${(ms / 1000).toStringAsFixed(0)} 秒）。'
            '底盘可能正忙或网络较慢，可在设置中加大超时后重试。';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return '连接失败：无法访问 $url。'
            '请确认手机与底盘处于同一 WiFi，或检查地址是否正确。';
      case DioExceptionType.badCertificate:
        return '连接失败：证书校验不通过（本 App 仅使用局域网明文 HTTP）。';
      case DioExceptionType.cancel:
        return '请求已取消：$url';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return _httpErrorMessage(code ?? 0);
    }
  }

  String _httpErrorMessage(int status) {
    if (status >= 500) {
      return '底盘服务返回 HTTP $status（服务未就绪或内部错误）。请稍后重试，并在日志页查看完整请求。';
    }
    if (status == 404) {
      return '底盘返回 HTTP 404（该项当前不存在，属正常状态）。';
    }
    if (status >= 400) {
      return '底盘返回 HTTP $status（请求被拒绝）。请检查参数与底盘状态。';
    }
    return '底盘返回 HTTP $status。';
  }
}
