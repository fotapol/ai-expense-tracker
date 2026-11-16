import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class ReceiptHistoryControls extends StatelessWidget {
  const ReceiptHistoryControls({
    super.key,
    required this.sort,
    required this.labels,
    required this.reviewOnly,
    required this.onSort,
    required this.onReview,
  });
  final String sort;
  final Map<String, String> labels;
  final bool reviewOnly;
  final ValueChanged<String> onSort;
  final ValueChanged<bool> onReview;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 13);
    Size measure(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final sortLabel = context.tr(labels[sort]!);
    final reviewLabel = context.tr('receipts_filter_needs_review');
    final sortText = measure(sortLabel), reviewText = measure(reviewLabel);
    final height = math.max(
      48.0,
      math.max(sortText.height, reviewText.height) + 20,
    );
    final reviewWidth = reviewText.width + 50;
    final tone = ShellStyles.accentTone(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep both actions on one line. At very narrow/accessibility sizes the
        // review icon retains its selected state, accessible name and tooltip.
        final compactReview = constraints.maxWidth < reviewWidth + 128;
        final sortControl = PopupMenuButton<String>(
          key: const ValueKey('receipt-sort'),
          tooltip: '${context.tr('receipts_sort')}: $sortLabel',
          borderRadius: BorderRadius.circular(12),
          position: PopupMenuPosition.under,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final value in labels.keys)
              CheckedPopupMenuItem(
                value: value,
                checked: sort == value,
                child: Text(context.tr(labels[value]!)),
              ),
          ],
          child: Ink(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShellStyles.cardDecoration(
              context,
              radius: 12,
              withShadow: false,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 18,
                  color: ShellStyles.textMuted(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sortLabel,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        );
        final buttonStyle = OutlinedButton.styleFrom(
          minimumSize: Size(48, height),
          textStyle: style,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          backgroundColor: reviewOnly
              ? tone.container
              : ShellStyles.surface(context),
          foregroundColor: reviewOnly
              ? tone.foreground
              : ShellStyles.textPrimary(context),
          side: BorderSide(
            color: reviewOnly ? tone.border : ShellStyles.border(context),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
        final reviewIcon = Icon(
          reviewOnly ? Icons.fact_check : Icons.fact_check_outlined,
          size: 18,
        );
        final review = Semantics(
          toggled: reviewOnly,
          label: compactReview ? reviewLabel : null,
          child: compactReview
              ? Tooltip(
                  message: reviewLabel,
                  child: OutlinedButton(
                    key: const ValueKey('receipt-review-filter'),
                    onPressed: () => onReview(!reviewOnly),
                    style: buttonStyle,
                    child: reviewIcon,
                  ),
                )
              : OutlinedButton.icon(
                  key: const ValueKey('receipt-review-filter'),
                  onPressed: () => onReview(!reviewOnly),
                  style: buttonStyle,
                  icon: reviewIcon,
                  label: Text(reviewLabel),
                ),
        );
        return Row(
          key: const ValueKey('receipt-controls-inline'),
          children: [
            Expanded(child: sortControl),
            const SizedBox(width: 8),
            review,
          ],
        );
      },
    );
  }
}
