import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 键值卡（KV 行）。数值缺省显示「—」，不显示 0（PRD §9.1）。
class KvTile extends StatelessWidget {
  const KvTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.sub,
    this.dense = false,
    this.valueMono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? sub;
  final bool dense;

  /// 数值使用等宽/表格数字，避免刷新时跳动（PRD §7.2）
  final bool valueMono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.neutral),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: TextStyle(
                    fontSize: dense ? 13.5 : 14.5,
                    color: valueColor ?? const Color(0xFF1F2937),
                    fontWeight: FontWeight.w600,
                    fontFeatures: valueMono
                        ? const <FontFeature>[FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      sub!,
                      style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片容器（白底 + 1px 边框 + 8px 圆角，PRD §7.2）
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// 状态徽标
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    this.color = AppColors.neutral,
    this.icon,
    this.filled = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(filled ? 1 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部提示横幅（断连、健康告警、低电等）
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    required this.severity,
    this.onTap,
    this.actionLabel,
    this.dense = false,
  });

  final String text;
  final Severity severity;
  final VoidCallback? onTap;
  final String? actionLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: severity.color,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 6 : 9),
        child: Row(
          children: <Widget>[
            Icon(severity.icon, size: dense ? 15 : 17, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dense ? 12.5 : 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (actionLabel != null)
              Text(
                actionLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 空状态（说明原因 + 指引，PRD §7.3）
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.action,
  });

  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      child: Column(
        children: <Widget>[
          const Icon(Icons.inbox_outlined, size: 34, color: AppColors.neutral),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.neutral),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 危险按钮 + 不可用原因（原因不可省，FR-SAFE-06）
class GuardedButton extends StatelessWidget {
  const GuardedButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.blockReason,
    this.danger = false,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 非 null 表示不可用，并展示该原因
  final String? blockReason;
  final bool danger;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final blocked = blockReason != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 52,
          child: FilledButton(
            key: ValueKey<String>('guarded-$label'),
            onPressed: blocked ? null : onPressed,
            style: danger && !blocked
                ? AppTheme.dangerButton()
                : FilledButton.styleFrom(
                    backgroundColor: danger ? AppColors.error : AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        Icon(icon, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
          ),
        ),
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: <Widget>[
                const Icon(Icons.info_outline, size: 14, color: AppColors.neutral),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '$blockReason，暂不可用',
                    style: const TextStyle(fontSize: 12, color: AppColors.neutral),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
