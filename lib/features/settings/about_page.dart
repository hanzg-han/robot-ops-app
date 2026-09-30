import 'package:flutter/material.dart';

import '../../app_state/services.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/common.dart';

/// P11 设置·关于（PRD §5.9）。
///
/// 免责与安全说明：仅限院内局域网使用；接口无鉴权；不做合规宣称。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final s = services;
    final info = s.state.robotInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          SectionCard(
            title: 'App',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                KvTile(label: '版本', value: 'v${AppConfig.appVersion}', dense: true),
                const KvTile(
                  label: '平台',
                  value: 'Android 8.0+（v1.0 仅交付 Android，Flutter 跨平台结构保留）',
                  dense: true,
                ),
                KvTile(label: '底盘地址', value: s.client.baseUrl, dense: true),
                const KvTile(
                  label: '交付范围',
                  value: '仅院内局域网直连；无云转发、无账号体系',
                  dense: true,
                ),
              ],
            ),
          ),
          SectionCard(
            title: '底盘',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                KvTile(label: '型号', value: info?.modelLabel ?? '—', dense: true),
                KvTile(label: '固件', value: info?.softwareVersion ?? '—', dense: true),
                KvTile(label: 'core', value: 'slamware.agent.core', dense: true),
                KvTile(
                  label: '能力',
                  value: s.state.capabilities.isEmpty
                      ? '—'
                      : s.state.capabilities.map((c) => c.label).join('\n'),
                  dense: true,
                ),
                KvTile(
                  label: '接口地址',
                  value: '${s.client.baseUrl}/index.html（底盘内置 Swagger）',
                  dense: true,
                ),
              ],
            ),
          ),
          SectionCard(
            title: '免责与安全说明',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                Text(
                  '1. 本 App 仅限院内局域网使用，禁止在公网环境使用；'
                  '接口无鉴权、无 HTTPS，接入医院网络前需经信息科许可并书面报备。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                SizedBox(height: 6),
                Text(
                  '2. 所有移动类操作均需二次确认；唯一例外是手动遥控面板，'
                  '采用「进入时确认一次、当次连接内有效」，并配套六路立即停止等补偿控制。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                SizedBox(height: 6),
                Text(
                  '3. 遥控模式不会自动避障，安全性完全由现场人员的目视与松手动作保证；'
                  '建议两人作业、最低速度档起步。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                SizedBox(height: 6),
                Text(
                  '4. 底盘手册未标注 IP 防护等级、认证仅写 "CR"、精准对接摄像头为选配；'
                  '本 App 不做任何假设，整机认证由项目 D 包负责。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                SizedBox(height: 6),
                Text(
                  '5. App 不采集患者信息，不涉及人脸/语音；'
                  '地图与 POI 属院内环境信息，仅在本地处理。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ],
            ),
          ),
          SectionCard(
            title: '不要做什么（实现红线）',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                Text(
                  '・不得把遥控包装成「长按自动持续」而忽略下发失败：每次下发失败都必须立即停止。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                Text(
                  '・不得在遥控期间允许任何其他移动类指令下发，必须全局互斥。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                Text(
                  '・不得依赖底盘自动避障来保证安全；文案中不得出现「会自动避障」之类的暗示。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
                Text(
                  '・不得把遥控会话状态持久化到下次启动（每次进入都必须重新确认）。',
                  style: TextStyle(fontSize: 12.5, height: 1.6),
                ),
              ],
            ),
          ),
          const NoticeBanner(
            text: '本项目不使用 Mock 数据：地址只允许指向真实底盘，代码中不存在可切换到假数据的入口。',
            severity: Severity.info,
            dense: true,
          ),
        ],
      ),
    );
  }
}
