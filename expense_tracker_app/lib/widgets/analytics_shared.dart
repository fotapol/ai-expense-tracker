import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class AnalyticsSurfaceCard extends StatelessWidget {
  const AnalyticsSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.color,
    this.withShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool withShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShellStyles.cardDecoration(
        context,
        radius: radius,
        color: color,
        withShadow: withShadow,
      ),
      child: child,
    );
  }
}

class AnalyticsLoadingState extends StatelessWidget {
  const AnalyticsLoadingState({super.key, this.label = 'Loading analytics...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              label,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsErrorState extends StatelessWidget {
  const AnalyticsErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: ShellColors.softRed,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsEmptyCard extends StatelessWidget {
  const AnalyticsEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: ShellStyles.iconBadgeDecoration(
              context,
              color: ShellStyles.surfaceAlt(context),
              radius: 14,
            ),
            child: Icon(
              icon,
              color: ShellStyles.textPrimary(context),
              size: 20,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class AnalyticsSectionHeader extends StatelessWidget {
  const AnalyticsSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ],
    );

    if (trailing == null) {
      return content;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [content, const SizedBox(height: 12), trailing!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            const SizedBox(width: 12),
            trailing!,
          ],
        );
      },
    );
  }
}

class AnalyticsFullBleedDivider extends StatelessWidget {
  const AnalyticsFullBleedDivider({
    super.key,
    this.bleed = 20,
    this.topSpacing = 10,
    this.bottomSpacing = 10,
  });

  final double bleed;
  final double topSpacing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth + (bleed * 2);
          return SizedBox(
            width: double.infinity,
            height: 1,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: fullWidth,
              maxWidth: fullWidth,
              child: Transform.translate(
                offset: Offset(-bleed, 0),
                child: SizedBox(
                  width: fullWidth,
                  height: 1,
                  child: ColoredBox(color: ShellStyles.border(context)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class AnalyticsMiniStatTile extends StatelessWidget {
  const AnalyticsMiniStatTile({
    super.key,
    required this.label,
    required this.value,
    this.supporting,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? supporting;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: ShellStyles.surfaceAlt(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShellStyles.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: ShellStyles.textMuted(context)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? ShellStyles.textPrimary(context),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (supporting != null) ...[
            const SizedBox(height: 4),
            Text(
              supporting!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
