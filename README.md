# 导诊机器人运维 App（FlutterDemo）

面向医院现场运维人员与医院管理员的 **Android 手机端运维 App**：直连思岚 Slamtec
**Athena2.0 PRO MAX** 移动底盘的局域网 HTTP API，查看电源、位姿、地图、任务与告警，
并下发导航、回充、巡逻、终止等指令。

- 需求依据：`机器人底盘/doc/导诊机器人运维App_PRD_v1.0.html`（PRD v1.2，101 条 FR + 7 条安全门禁）
- 接口事实来源：`机器人底盘/doc/Flutter运维App开发文档_v1.0.html`（§10 API 对照表，实机验证）
- 字段冲突时**以开发文档（实机）为准**

---

## 1. 运行方式

### 1.1 环境基线

| 项 | 版本 |
| --- | --- |
| Flutter | **3.24.5**（stable，CI 固定此版本） |
| Dart SDK | `>=3.5.0 <4.0.0` |
| Java（Android 构建） | 17 |
| 交付平台 | Android 8.0+（v1.0 **仅交付 Android**，见 PRD §8.3 / Q10） |

> 本机（开发环境）**未安装 Flutter SDK**，因此编译与测试统一在 GitHub Actions 上完成，
> 见 §3。本地若已装 Flutter，按下述步骤可直接运行。

### 1.2 本地构建（已安装 Flutter 时）

```bash
flutter pub get

# Android 平台工程不入库，需先生成（见 .gitignore）
flutter create --platforms=android --org com.wizrole .

# 注入明文流量例外 / INTERNET 权限 / 中文 App 名（开发文档 §8.3）
python tool/prepare_android.py

flutter analyze
flutter test
flutter run          # 需与底盘同网段
flutter build apk --release
```

### 1.3 底盘地址

- 默认地址：`http://192.168.0.16:1448`
- 连接页支持 `192.168.0.16:1448` 与 `http://192.168.0.16:1448/` 两种写法，自动补协议、去尾斜杠
- **仅局域网直连**：无云转发、无账号体系、无 Mock 数据源（FR-CON-10 / FR-SAFE-05）
- 底盘内置 Swagger：`http://192.168.0.16:1448/index.html`（spec 落后于固件处一律以实机为准）

---

## 2. 依赖版本

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| `flutter_riverpod` | 见 pubspec | 声明于 pubspec（本工程实际用等价显式容器 + `ChangeNotifier`，见下） |
| `dio` | ^5.7.0 | HTTP 客户端（地址规范化、超时、日志钩子） |
| `shared_preferences` | ^2.3.3 | 本地持久化（地址、超时、开关、巡逻草稿） |
| `collection` | ^1.18.0 | 集合工具 |
| `flutter_lints` | ^5.0.0 | 静态检查规则（dev） |

**关于状态管理**：开发文档 §4.2 建议 Riverpod，同时明确允许「不引入代码生成」。
本工程依赖关系单一（1 个全局状态 + 5 个控制器），因此采用
`lib/app_state/services.dart` 的显式依赖容器 + `ChangeNotifier`，
达到同样的「单一入口 + 可测」效果，并避免为 12 个 DTO 引入 build_runner。

---

## 3. 通过 GitHub Actions 编译

工作流：`.github/workflows/flutter-ci.yml`

```bash
# 首次推送到 GitHub（凭据使用本机已配置的 git credential）
git init
git add .
git commit -m "feat: 导诊机器人运维 App Demo（依据 PRD v1.2 + 开发文档 v1.0）"
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

流水线步骤：

1. `flutter pub get`
2. `flutter analyze --no-fatal-infos --no-fatal-warnings`（验收要求：无 error）
3. `flutter test`（栅格解析 / 巡逻状态机 / 动作名解析 / 事件去重 / 安全红线）
4. `flutter create --platforms=android --org com.wizrole .`（生成平台工程）
5. `python3 tool/prepare_android.py`（明文流量、权限、App 名）
6. `flutter build apk --debug` 与 `flutter build apk --release`
7. 上传 APK 与 Android 平台工程产物（Artifacts）

> **安全说明（FR-SAFE-05）**：CI **只做** 静态分析、纯逻辑单测与编译。
> 所有涉及机器人移动的验证必须在真机上由**人工现场触发并全程目视**，
> 代码库中不存在自动化下发移动指令的脚本。

---

## 4. 工程结构

```
FlutterDemo/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ .github/workflows/flutter-ci.yml
├─ tool/prepare_android.py           # Android 平台加固（CI 内执行）
├─ lib/
│  ├─ main.dart                      # 入口：AppServices.init() + runApp
│  ├─ app.dart                       # 外壳：5 Tab + 顶部状态条 + 全局行为条
│  ├─ core/
│  │  ├─ config/app_config.dart      # 默认地址、超时、轮询、阈值、遥控节奏
│  │  ├─ network/
│  │  │  ├─ api_endpoints.dart       # 全部路径常量（= 开发文档 §10）
│  │  │  ├─ api_client.dart          # Dio 封装 · 地址规范化 · 超时 · 日志 · 中文错误
│  │  │  ├─ api_result.dart          # {ok,status,data,ms,error} 统一包装
│  │  │  └─ request_log.dart         # 请求日志缓冲（容量受限，滚动丢弃）
│  │  ├─ utils/                      # 数值/角度、时间（机器毫秒→本地时间）
│  │  └─ theme/app_theme.dart        # 主色 #1F4E79 + 语义色 + 地图配色
│  ├─ data/
│  │  ├─ dto/models.dart             # 与接口字段完全一致的 DTO
│  │  ├─ map/grid_codec.dart         # 栅格二进制解析（§13.1）
│  │  └─ repositories/repositories.dart
│  ├─ domain/
│  │  ├─ models/event_catalog.dart   # 事件类型→级别/中文说明/联动建议
│  │  └─ services/
│  │     ├─ action_name_resolver.dart # §9 末段精确匹配（必须做）
│  │     ├─ patrol_engine.dart        # 巡逻状态机（§14.2，纯逻辑可测）
│  │     └─ event_dedupe.dart         # type#timestamp 去重（§15.2）
│  ├─ app_state/                      # services / robot_state / settings / controllers
│  ├─ features/                       # connect / dashboard / map / tasks / remote / events / settings
│  └─ shared/widgets/                 # 通用卡片 · 统一二次确认（G01）·遥控进入确认
└─ test/                             # grid_codec · patrol_engine · action_name_resolver
                                     # event_dedupe · safety_policy
```

---

## 5. 页面与需求映射

| Tab / 页面 | 代码 | 需求 |
| --- | --- | --- |
| ① 总览 | `features/dashboard/dashboard_page.dart` | FR-DASH-01~12 |
| ② 地图 + 选点面板 + 遥控入口 | `features/map/map_page.dart`、`map_canvas.dart` | FR-MAP-01~15、FR-NAV-04~07、FR-RC-01 |
| ③ 任务（导航 / 巡逻 / 运动） | `features/tasks/tasks_page.dart` | FR-NAV-01~09、FR-PAT-01~09、FR-MOT-01~09 |
| ④ 事件 | `features/events/events_page.dart` | FR-EVT-01~09 |
| ⑤ 设置（连接 / 日志 / 充电桩 / 关于） | `features/settings/*.dart` | FR-SET-01~06、FR-LOG-01~05、FR-MOT-08 |
| P00 连接页 | `features/connect/connect_page.dart` | FR-CON-01~10 |
| P02a 手动遥控 | `features/remote/remote_control_page.dart` | FR-RC-01~15 |
| G01 二次确认弹窗 | `shared/widgets/confirm_danger.dart` | FR-SAFE-01/07 |
| G02 全局行为条 | `app.dart`（`_ActiveActionBar`） | FR-SAFE-02/03 |

---

## 6. 实现要点（易踩坑，全部已落实）

| # | 事实 / 坑 | 本工程处理 |
| --- | --- | --- |
| 1 | 动作名：Swagger 写 `slamtec.agent.actions.*`，**实机只认 `agent.actions.*`** | 启动拉取 `action-factories`，**末段精确匹配**，兜底 `agent.actions.$suffix`；`safety_policy_test` 禁止硬编码官方前缀 |
| 2 | 地图上下颠倒：数据 row 0 = **最小 Y** | 绘制前 `srcRow = height - 1 - row` 垂直翻转一次（`map_canvas.dart :: buildGridImage`） |
| 3 | 地址只填 `IP:端口` | `ApiClient.normalizeBase()` 自动补 `http://` 并去尾斜杠 |
| 4 | 「点了导航地图没反应」 | 所有目标入口统一走 `NavigationController.showRouteTo()`，先画线再下发 |
| 5 | 巡逻期间 UI 冻结 | 巡逻/遥控期间总览轮询**继续**（2s）；等待/停留循环内不终止轮询 |
| 6 | 目标被挤出视野 | 有导航/巡逻目标时用 `fitPoints`（机器人 + 目标 + 路径点）取景 |
| 7 | 事件重复膨胀、横幅反复弹 | 去重键 `type#timestamp`，本地留存上限 500 条 |
| 8 | 无行为时 `actions/:current` 返回 **404** | 404 = 空闲，不是错误；不弹提示、不计入断连判定 |
| 9 | 搜路失败返回 **500** | 按「不可达」处理，**保留终点标记**并提示；不崩溃 |
| 10 | 地图 320KB 放进 2s 轮询会卡 | 按需加载 + 手动刷新；激光限流 4s；遥控/建图期 3s 自动刷新 |
| 11 | 明文 HTTP 被系统拦截 | `android:usesCleartextTraffic="true"`（由 `tool/prepare_android.py` 注入） |
| 12 | `homepose` 未设置回充直接失败 | UI 层提前拦截：`homepose` 404 且无已注册 homedock → 回充置灰 + 「去标定」 |
| 13 | `localization/:enable` 语义 | `true` = 定位生效，`false` = 已暂停（纯里程）；**导航与回充都必须同时检查本项** |
| 14 | 终止返回 200 但响应体为空 | 「是否真的终止了什么」依据终止前后 `:current` 是否 404 判定，不看状态码 |
| 15 | `parameter` 可写范围 | 仅 3 项白名单（最大线速度 / 最大角速度 / 充电桩注册策略），受控控件 + 枚举，不做自由文本 |
| 16 | 遥控不会避障 | 顶部红色风险条常驻不可关闭；单次 `duration ≤500ms`、下发间隔 `≤300ms`；六路立即停止 |

---

## 7. 安全设计（发布门禁，FR-SAFE-01~07）

- **所有移动类操作 100% 二次确认**（导航 / 旋转 / 回充 / 巡逻下发点），弹窗必含
  「动作名 + 目标名称 + 坐标」；未确认不发起任何网络请求。
- **终止类操作 0 摩擦**：全局行为条在所有 Tab 可见，一次点击直达，无二次确认；
  无行为时置灰并给出说明而非报错。
- **下发后立即前台化**：不等下一轮 2s 轮询；拉不到状态时显示「已下发，状态获取中…」。
- **不可用必须解释**：断连 / 定位未开启 / 无充电桩 / 无 POI 四类前置条件
  全部「置灰 + 原因」，禁止先报错后解释。
- **唯一例外：手动遥控**（`FR-SAFE-07`）。采用「进入时确认一次、当次连接内有效」，
  必须配套全部补偿控制：顶部风险条、方向键 ≥64dp、六路立即停止（抬指 / 滑出 /
  切后台 / 锁屏 / 断连 / 关面板）、遥控期间禁止其他移动指令（双向互斥）、
  全局终止始终可达、全部下发写日志、退出后重新确认。该例外**不得被复用**
  （`test/safety_policy_test.dart` 强制校验）。

---

## 8. 单元测试清单

| 文件 | 覆盖 |
| --- | --- |
| `test/grid_codec_test.dart` | 二进制头解析、尺寸/长度校验、栅格语义四类、颜色映射、row0=最小Y 与垂直翻转关系 |
| `test/patrol_engine_test.dart` | 多点顺序、圈数（含 0 无限 + 护栏）、进度与剩余点、参数默认值、停止/超时/异常中断、批量文本解析行号 |
| `test/action_name_resolver_test.dart` | 末段精确匹配（不误中 `Schedulable*`）、兜底前缀、工厂清单两种形态、遥控节奏护栏 |
| `test/event_dedupe_test.dart` | 三种响应结构兼容、`type#timestamp` 去重、容量上限、时间倒序、级别推断、中文说明、联动建议 |
| `test/safety_policy_test.dart` | 地址规范化、路径常量与开发文档 §10 一致、**无 Mock 数据源**、遥控例外不被复用、统一确认组件 |

本地/CI 运行：`flutter test`

---

## 9. 交付状态与遗留

- ✅ 101 条 FR 的页面与逻辑骨架、7 条安全门禁、5 组单元测试、CI 编译流水线
- ✅ 按 PRD 要求：仅 Android、无 Mock、无账号体系
- ⏳ **真机验证未完成**（FR-SAFE-05：必须在真机上由人工触发并目视）
  - 地图方向/位置逐格比对（FR-MAP-01/04）
  - 移动类整链路：导航 → 到达提示 → 路线清理（FR-NAV-05/09）
  - 巡逻 2 点 × 2 圈 + 中途停止（FR-PAT-04~07）
  - 遥控六路立即停止 + 抓包确认无残留下发（FR-RC-06）
- ⏳ 待底盘侧书面澄清（PRD §14.5）：WiFi 模块、IP 防护、认证、精准对接摄像头是否随机含
- ⏳ P2 项按反馈排期：PID 锁、深色模式、巡逻方案命名保存、电量趋势图

---

## 10. 免责与合规

- 仅限**院内局域网**使用；接口无鉴权、无 HTTPS，接入医院网络前需经信息科许可并书面报备。
- 遥控模式**不会自动避障**，安全性由现场人员目视与松手动作保证；建议两人作业、最低档起步。
- App 不采集患者信息，不涉及人脸/语音；地图与 POI 属院内环境信息，仅在本地处理。
- 底盘手册未标注 IP 防护等级、认证仅写 "CR"、精准对接摄像头为选配；
  本 App 不做任何假设，整机认证由项目 D 包负责。
