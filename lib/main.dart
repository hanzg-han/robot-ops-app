import 'package:flutter/material.dart';

import 'app_state/services.dart';
import 'app.dart';

/// 入口（开发文档 §5：runApp + 服务初始化）。
///
/// 注意：本项目**不使用 Mock 数据**（FR-CON-10）——地址只允许指向真实底盘，
/// 代码中不存在任何可切换到假数据的入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.init();
  runApp(RobotOpsApp(services: services));
}
