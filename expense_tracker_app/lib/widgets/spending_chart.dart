import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'compact_text.dart';
import 'text_measurement.dart';

class SpendingSlice {
  const SpendingSlice({
    required this.name,
    required this.value,
    required this.amountLabel,
    required this.percentageLabel,
    required this.color,
  });

  final String name;
  final double value;
  final String amountLabel;
  final String percentageLabel;
  final Color color;
}

class SpendingDonut extends StatelessWidget {
  const SpendingDonut({super.key, required this.slices, required this.total});
  final List<SpendingSlice> slices;
  final String total;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredDiameter = (180 * ShellStyles.textScale(context)).clamp(
          180.0,
          220.0,
        );
        final diameter = math.min(constraints.maxWidth, preferredDiameter);
        final innerRadius = diameter * .37;
        final ringThickness = diameter * .11;
        return Center(
          child: SizedBox.square(
            dimension: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: innerRadius,
                    startDegreeOffset: -90,
                    sections: [
                      if (slices.isEmpty)
                        PieChartSectionData(
                          value: 1,
                          color: ShellStyles.border(context),
                          showTitle: false,
                          radius: ringThickness,
                        )
                      else
                        for (final slice in slices)
                          PieChartSectionData(
                            value: slice.value,
                            color: slice.color,
                            showTitle: false,
                            radius: ringThickness,
                          ),
                    ],
                  ),
                ),
                // The bounding box fits inside the hole even at its corners.
                SizedBox(
                  width: innerRadius * 1.6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: innerRadius * .34,
                        ),
                        child: CompactText(
                          context.tr('analytics_total_spent').toUpperCase(),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: innerRadius * .55,
                        ),
                        child: CompactText(
                          total,
                          key: const ValueKey('spending-chart-total'),
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SpendingLegend extends StatelessWidget {
  const SpendingLegend({super.key, required this.slices});
  final List<SpendingSlice> slices;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      color: ShellStyles.textPrimary(context),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );
    final percentageStyle = TextStyle(
      color: ShellStyles.textMuted(context),
      fontSize: 13,
    );
    final amountStyle = TextStyle(
      color: ShellStyles.textPrimary(context),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final rows = [
      for (final slice in slices)
        (
          slice: slice,
          percentage: slice.percentageLabel,
          amount: slice.amountLabel,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const dotSize = 10.0;
        var nameWordWidth = 0.0;
        var percentageWidth = 0.0;
        var amountWidth = 0.0;
        for (final row in rows) {
          nameWordWidth = math.max(
            nameWordWidth,
            measureTextLayout(context, row.slice.name, nameStyle).minWidth,
          );
          percentageWidth = math.max(
            percentageWidth,
            measureTextLayout(context, row.percentage, percentageStyle).width,
          );
          amountWidth = math.max(
            amountWidth,
            measureTextLayout(context, row.amount, amountStyle).width,
          );
        }
        final inline =
            constraints.maxWidth >=
            dotSize +
                3 * gap +
                nameWordWidth.ceil() +
                percentageWidth.ceil() +
                amountWidth.ceil();
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: row.slice.color,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: dotSize),
                      ),
                    ),
                    const SizedBox(width: gap),
                    if (inline) ...[
                      Expanded(child: Text(row.slice.name, style: nameStyle)),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: percentageWidth.ceilToDouble(),
                        child: Text(
                          row.percentage,
                          style: percentageStyle,
                          textAlign: TextAlign.end,
                          softWrap: false,
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: amountWidth.ceilToDouble(),
                        child: Text(
                          row.amount,
                          style: amountStyle,
                          textAlign: TextAlign.end,
                          softWrap: false,
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.slice.name, style: nameStyle),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(row.percentage, style: percentageStyle),
                                const SizedBox(width: gap),
                                Expanded(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: CompactText(
                                      row.amount,
                                      style: amountStyle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
