import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 二次确认弹窗的请求内容（G01 统一组件，PRD §5.10）。
class ConfirmRequest {
  const ConfirmRequest({
    required this.title,
    required this.actionName,
    this.targetName,
    this.coordinates,
    this.extraLines = const <String>[],
    this.riskNote,
    this.confirmLabel = '确认并下发',
  });

  final String title;

  /// 动作名（如 MoveToAction / GoHomeAction / 巡逻）
  final String actionName;

  /// 目标名称（必须含，FR-SAFE-01）
  final String? targetName;

  /// 坐标（如 x 11.930, y 0.270）
  final String? coordinates;

  final List<String> extraLines;
  final String? riskNote;
  final String confirmLabel;
}

/// 统一二次确认弹窗（FR-SAFE-01 / FR-SAFE-07）。
///
/// 关键约束：
/// - **唯一例外**是遥控面板的「进入时确认一次」（见 [confirmRemoteEntry]），
///   其余所有移动类操作一律逐次确认；
/// - 未确认时**不发起任何网络请求**；
/// - 弹窗必须包含「动作名 + 目标名称 + 坐标」。
class ConfirmDanger {
  const ConfirmDanger._();

  static Future<bool> show(BuildContext context, ConfirmRequest req) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                req.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _line('动作', req.actionName),
              if (req.targetName != null) _line('目标', req.targetName!),
              if (req.coordinates != null) _line('坐标', req.coordinates!),
              for (final l in req.extraLines) _line('', l),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  req.riskNote ?? '请确认行进区域无人、无障碍物。',
                  style: const TextStyle(fontSize: 13, color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: AppTheme.dangerButton(),
            child: Text(req.confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (label.isNotEmpty)
            SizedBox(
              width: 44,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: AppColors.neutral),
              ),
            ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 遥控「进入时确认」页（FR-RC-02 / FR-SAFE-07 唯一例外）。
  ///
  /// 与逐次确认不同：本确认在**当次连接内有效**；因此必须由全部补偿控制围住。
  static Future<bool> confirmRemoteEntry(
    BuildContext context, {
    required bool lowBattery,
  }) async {
    bool clearArea = false;
    bool spotter = false;
    bool slowGear = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: const Text(
            '进入手动遥控前请确认',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '⚠ 此模式下机器人不会自动避障',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (lowBattery) ...<Widget>[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Text(
                      '电量已低于设定阈值，遥控期间请注意剩余电量。',
                      style: TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const _Bullet('前进 / 后退 / 左转 / 右转 四向控制'),
                const _Bullet('按住行走，松开立即停止'),
                const _Bullet('本次确认在当次连接内有效'),
                const _Bullet('遥控期间无法使用导航 / 巡逻 / 回充'),
                const SizedBox(height: 12),
                const Text(
                  '现场要求：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                _Check(
                  value: clearArea,
                  label: '已清场，行进方向无人、无障碍物',
                  onChanged: (v) => setState(() => clearArea = v),
                ),
                _Check(
                  value: spotter,
                  label: '已有专人守在机器人旁，随时可按本体急停',
                  onChanged: (v) => setState(() => spotter = v),
                ),
                _Check(
                  value: slowGear,
                  label: '已使用最低速度档起步',
                  onChanged: (v) => setState(() => slowGear = v),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消，返回地图'),
            ),
            FilledButton(
              onPressed: (clearArea && spotter && slowGear)
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: AppTheme.dangerButton(),
              child: const Text('我已知晓，进入遥控'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('・', style: TextStyle(fontSize: 13, color: AppColors.neutral)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check({required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: value,
                onChanged: (bool? v) => onChanged(v ?? false),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
      );
}
