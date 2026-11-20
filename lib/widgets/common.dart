import 'package:flutter/material.dart';

import '../models/audit.dart';
import '../theme/app_theme.dart';

/// 风险等级对应的颜色。
class RiskStyle {
  const RiskStyle({required this.color, required this.container});

  final Color color;
  final Color container;

  static RiskStyle of(BuildContext context, Grade grade) {
    final colors = context.appColors;
    switch (grade) {
      case Grade.high:
        return RiskStyle(
          color: colors.danger,
          container: colors.dangerContainer,
        );
      case Grade.suspect:
        return RiskStyle(
          color: colors.warning,
          container: colors.warningContainer,
        );
      case Grade.watch:
        return RiskStyle(color: colors.watch, container: colors.watchContainer);
      case Grade.normal:
        return RiskStyle(color: colors.safe, container: colors.safeContainer);
    }
  }
}

/// 等级徽章。
class GradeBadge extends StatelessWidget {
  const GradeBadge({super.key, required this.grade, this.compact = false});

  final Grade grade;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = RiskStyle.of(context, grade);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: style.container,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        grade.label,
        style: TextStyle(
          color: style.color,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 偷跑指数条。
class ScoreBar extends StatelessWidget {
  const ScoreBar({
    super.key,
    required this.score,
    this.height = 8,
    this.showValue = true,
  });

  final int score;
  final double height;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final style = RiskStyle.of(context, Grade.of(score));
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height),
            child: LinearProgressIndicator(
              value: (score / 100).clamp(0.0, 1.0),
              minHeight: height,
              backgroundColor: context.appColors.neutralContainer,
              valueColor: AlwaysStoppedAnimation<Color>(style.color),
            ),
          ),
        ),
        if (showValue) ...[
          const SizedBox(width: 10),
          Text(
            '$score',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: style.color,
            ),
          ),
        ],
      ],
    );
  }
}

/// 带标题的分区卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: context.scheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// 证据等级的小标签。
class EvidenceLevelTag extends StatelessWidget {
  const EvidenceLevelTag({super.key, required this.level});

  final EvidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (color, container) = switch (level) {
      EvidenceLevel.hard => (colors.danger, colors.dangerContainer),
      EvidenceLevel.lead => (colors.warning, colors.warningContainer),
      EvidenceLevel.userMarked => (colors.watch, colors.watchContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 空态提示。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: context.scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
