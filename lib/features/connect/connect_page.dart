import 'package:flutter/material.dart';

import '../../app_state/services.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/dto/models.dart';
import '../../shared/widgets/common.dart';

/// P00 启动 / 连接页（PRD §5.1；FR-CON-01~10）。
///
/// 关键点：
/// - 地址支持 `IP:端口` 与 `http://IP:端口` 两种写法，自动补协议、去尾斜杠；
/// - 「测试连接」调 capabilities，展示成功/失败与耗时，错误三分类；
/// - 无 Mock 入口（FR-CON-10）：地址只允许指向真实底盘。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.services});

  final AppServices services;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final TextEditingController _addr =
      TextEditingController(text: widget.services.settings.baseUrl);
  bool _testing = false;
  bool _success = false;
  String? _message;
  int? _ms;

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final raw = _addr.text;
    // FR-CON-01：空地址回落到默认地址
    final normalized = ApiClientNormalizer.normalize(raw);
    _addr.text = normalized;

    setState(() {
      _testing = true;
      _success = false;
      _message = null;
      _ms = null;
    });

    widget.services.client.markConnecting();
    widget.services.client.configure(
      baseUrl: normalized,
      timeoutMs: widget.services.settings.timeoutMs,
      longTimeoutMs: widget.services.settings.longTimeoutMs,
    );

    final res = await widget.services.client.testConnection();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _success = res.ok;
      _ms = res.ms;
      _message = res.ok
          ? '连接成功 · 耗时 ${res.ms} ms'
          : (res.error ?? '连接失败（HTTP ${res.status}）');
    });

    if (res.ok) {
      await widget.services.settings.setBaseUrl(normalized);
      await widget.services.state.runPreflight();
      widget.services.state.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final caps = services.state.capabilities;

    return Scaffold(
      appBar: AppBar(title: const Text('连接机器人底盘')),
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
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: '192.168.0.16:1448 或 http://192.168.0.16:1448',
                    prefixIcon: Icon(Icons.lan_outlined),
                    labelText: 'IP:端口',
                  ),
                  onSubmitted: (_) => _test(),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  '规范化后：${ApiClientNormalizer.normalize(_addr.text)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.neutral),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Text('超时', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: AppConfig.timeoutOptions.contains(services.settings.timeoutMs)
                          ? services.settings.timeoutMs
                          : AppConfig.defaultTimeoutMs,
                      items: AppConfig.timeoutOptions
                          .map((int v) => DropdownMenuItem<int>(
                                value: v,
                                child: Text('${v ~/ 1000} s'),
                              ))
                          .toList(),
                      onChanged: (int? v) async {
                        if (v == null) return;
                        await services.settings.setTimeoutMs(v);
                        services.applySettingsToClient();
                        setState(() {});
                      },
                    ),
                    const Spacer(),
                    const Text('自动轮询', style: TextStyle(fontSize: 13)),
                    Switch(
                      value: services.settings.autoPoll,
                      onChanged: (bool v) async {
                        await services.settings.setAutoPoll(v);
                        services.applySettingsToClient();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.wifi_find),
              label: Text(_success ? '重新测试连接' : '测试连接'),
            ),
          ),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 12),
            SectionCard(
              child: Row(
                children: <Widget>[
                  Icon(
                    _success ? Icons.check_circle : Icons.error_outline,
                    color: _success ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _success ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
                  if (_ms != null && _success)
                    Text(
                      '$_ms ms',
                      style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                    ),
                ],
              ),
            ),
          ],
          if (_success) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.dashboard),
                label: const Text('进入总览'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: '能力清单（连对了哪台机器）',
            child: caps.isEmpty
                ? const Text(
                    '连接成功后自动获取。',
                    style: TextStyle(fontSize: 12.5, color: AppColors.neutral),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: caps
                        .map((Capability c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.extension_outlined,
                                      size: 15, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(c.label, style: const TextStyle(fontSize: 13)),
                                  ),
                                  if (c.enabled != null)
                                    Text(
                                      c.enabled! ? '已启用' : '未启用',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: c.enabled!
                                            ? AppColors.success
                                            : AppColors.neutral,
                                      ),
                                    ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
          if (services.settings.recentBaseUrls.length > 1)
            SectionCard(
              title: '历史地址（最近 3 个）',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: services.settings.recentBaseUrls
                    .map((String u) => InkWell(
                          onTap: () {
                            _addr.text = u;
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: <Widget>[
                                const Icon(Icons.history, size: 15, color: AppColors.neutral),
                                const SizedBox(width: 6),
                                Expanded(child: Text(u, style: const TextStyle(fontSize: 13))),
                                const Icon(Icons.chevron_right,
                                    size: 16, color: AppColors.neutral),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          SectionCard(
            title: '动作工厂预检',
            child: Text(
              services.resolver.isLoaded
                  ? '已解析 ${services.resolver.factories.length} 种动作（末段精确匹配下发）：\n'
                      '${services.resolver.factories.take(6).join('\n')}'
                      '${services.resolver.factories.length > 6 ? '\n…' : ''}'
                  : '连接成功后自动拉取，用于按末段精确匹配动作名（避免下发静默失败）。',
              style: const TextStyle(fontSize: 12, color: AppColors.neutral, height: 1.5),
            ),
          ),
          const NoticeBanner(
            text: '需与底盘处于同一局域网。App 不做云转发，仅支持局域网直连。',
            severity: Severity.info,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// 地址规范化入口（与 ApiClient.normalizeBase 同一实现，避免页面直接依赖 core 细节）
class ApiClientNormalizer {
  const ApiClientNormalizer._();

  static String normalize(String raw) => normalizeBase(raw);

  static String normalizeBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return AppConfig.defaultBaseUrl;
    if (!RegExp(r'^https?://').hasMatch(s)) s = 'http://$s';
    return s.replaceAll(RegExp(r'/+$'), '');
  }
}
