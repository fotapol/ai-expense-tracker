import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/money_format_preferences.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';
import '../widgets/analytics_shared.dart';

class AnalyticsTrendsTab extends StatefulWidget {
  const AnalyticsTrendsTab({
    super.key,
    required this.filters,
    this.activeFiltersBuilder,
  });

  final AnalyticsFilters filters;
  final Widget Function()? activeFiltersBuilder;

  @override
  State<AnalyticsTrendsTab> createState() => _AnalyticsTrendsTabState();
}

class _AnalyticsTrendsTabState extends State<AnalyticsTrendsTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _trendData;
  Map<String, dynamic>? _summaryData;
  Map<String, dynamic>? _previousSummaryData;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didUpdateWidget(covariant AnalyticsTrendsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final fromDate = PeriodFilter.getStartDate(widget.filters.period);
    final toDate = PeriodFilter.getEndDate(widget.filters.period);
    final previousRange = PeriodFilter.getPreviousMatchedRange(
      widget.filters.period,
    );

    try {
      final results = await Future.wait<dynamic>([
        ApiClient.getTransactionTrendSummary(
          fromDate: fromDate,
          toDate: toDate,
          categoryIds: widget.filters.categoryIds.isNotEmpty
              ? widget.filters.categoryIds
              : null,
          subcategoryIds: widget.filters.subcategoryIds.isNotEmpty
              ? widget.filters.subcategoryIds
              : null,
          labelIds: widget.filters.labelIds.isNotEmpty
              ? widget.filters.labelIds
              : null,
        ),
        ApiClient.getTransactionsSummary(
          fromDate: fromDate,
          toDate: toDate,
          categoryIds: widget.filters.categoryIds.isNotEmpty
              ? widget.filters.categoryIds
              : null,
          subcategoryIds: widget.filters.subcategoryIds.isNotEmpty
              ? widget.filters.subcategoryIds
              : null,
          labelIds: widget.filters.labelIds.isNotEmpty
              ? widget.filters.labelIds
              : null,
        ),
        previousRange == null
            ? Future<Map<String, dynamic>?>.value(null)
            : ApiClient.getTransactionsSummary(
                fromDate: previousRange.start,
                toDate: previousRange.end,
                categoryIds: widget.filters.categoryIds.isNotEmpty
                    ? widget.filters.categoryIds
                    : null,
                subcategoryIds: widget.filters.subcategoryIds.isNotEmpty
                    ? widget.filters.subcategoryIds
                    : null,
                labelIds: widget.filters.labelIds.isNotEmpty
                    ? widget.filters.labelIds
                    : null,
              ),
      ]);

      if (!mounted) return;
      setState(() {
        _trendData = results[0] as Map<String, dynamic>;
        _summaryData = results[1] as Map<String, dynamic>;
        _previousSummaryData = results[2] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback:
              context.tr('analytics_trends_load_error'),
        );
        _isLoading = false;
      });
    }
  }

  double _parseDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  int _parseInt(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _trendData != null || _summaryData != null;
    if (_isLoading && !hasData) {
      return const AnalyticsLoadingState();
    }
    if (_error != null && !hasData) {
      return AnalyticsErrorState(
        message: _error ?? context.tr('common_error'),
        onRetry: _fetchData,
      );
    }

    final trend = _trendData ?? const <String, dynamic>{};
    final summary = _summaryData ?? const <String, dynamic>{};
    final previousSummary = _previousSummaryData;
    final bucketUnit = trend['bucket_unit']?.toString() ?? 'week';
    final rawBuckets = (trend['buckets'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final rawValues = rawBuckets
        .map((bucket) => _parseDouble(bucket['amount']))
        .toList(growable: false);
    final currency =
        (summary['currency']?.toString() ??
                trend['currency']?.toString() ??
                'EUR')
            .toUpperCase();
    final totalSpent = _parseDouble(
      summary['total_amount'] ?? trend['current_total_amount'],
    );
    final previousTotalSpent = previousSummary == null
        ? (trend['previous_total_amount'] != null
              ? _parseDouble(trend['previous_total_amount'])
              : null)
        : _parseDouble(previousSummary['total_amount']);
    final totalTransactions = _parseInt(summary['total_transactions']);
    final previousTransactions = previousSummary == null
        ? null
        : _parseInt(previousSummary['total_transactions']);
    final dailyAverage =
        totalSpent / PeriodFilter.getPeriodDays(widget.filters.period);
    final previousDailyAverage = previousSummary == null
        ? null
        : _parseDouble(previousSummary['total_amount']) /
              PeriodFilter.getPeriodDays(widget.filters.period);

    final trendSeries = _buildTrendSeries(
      bucketUnit: bucketUnit,
      rawBuckets: rawBuckets,
      rawValues: rawValues,
    );
    final breakdownSeries = _buildBreakdownSeries(
      context,
      trendSeries: trendSeries,
    );
    final hasTrendData =
        trendSeries.length >= 2 && trendSeries.any((point) => point.amount > 0);
    final isEmptyTrends = totalSpent <= 0 && trendSeries.isEmpty;
    final lowestPoint = trendSeries.isEmpty
        ? null
        : trendSeries.reduce((a, b) => a.amount <= b.amount ? a : b);
    final highestPoint = trendSeries.isEmpty
        ? null
        : trendSeries.reduce((a, b) => a.amount >= b.amount ? a : b);

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.of(context).padding.bottom + 32,
        ),
        children: [
          if (widget.activeFiltersBuilder != null) ...[
            widget.activeFiltersBuilder!(),
            const SizedBox(height: 16),
          ],
          if (isEmptyTrends)
            AnalyticsEmptyCard(
              icon: Icons.show_chart,
              title: context.tr('no_trend_data_yet'),
              message:
                  context.tr('analytics_trends_empty_subtitle'),
            )
          else ...[
            _buildMetricsRow(
              context,
              currency: currency,
              totalSpent: totalSpent,
              totalTransactions: totalTransactions,
              dailyAverage: dailyAverage,
              previousTotalSpent: previousTotalSpent,
              previousTransactions: previousTransactions,
              previousDailyAverage: previousDailyAverage,
            ),
            const SizedBox(height: 16),
            _buildTrendCard(
              context,
              currency: currency,
              trendSeries: trendSeries,
              hasTrendData: hasTrendData,
              lowestPoint: lowestPoint,
              highestPoint: highestPoint,
            ),
            const SizedBox(height: 16),
            _buildBreakdownCard(
              context,
              currency: currency,
              bars: breakdownSeries,
            ),
          ],
          if (_error != null && hasData) ...[
            const SizedBox(height: 16),
            AnalyticsSurfaceCard(
              color: ShellColors.softRed.withAlpha(16),
              withShadow: false,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: ShellColors.softRed,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsRow(
    BuildContext context, {
    required String currency,
    required double totalSpent,
    required int totalTransactions,
    required double dailyAverage,
    required double? previousTotalSpent,
    required int? previousTransactions,
    required double? previousDailyAverage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth < 320;
        final tileWidth = useTwoColumns
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 20) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: tileWidth,
              child: _TrendMetricCard(
                label: context.tr('total_spent'),
                value: formatMoney(currency, totalSpent),
                change: _buildMetricChange(
                  current: totalSpent,
                  previous: previousTotalSpent,
                  lowerIsBetter: true,
                ),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _TrendMetricCard(
                label: 'Transactions',
                value: '$totalTransactions',
                change: _buildMetricChange(
                  current: totalTransactions.toDouble(),
                  previous: previousTransactions?.toDouble(),
                  lowerIsBetter: true,
                ),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _TrendMetricCard(
                label: context.tr('daily_avg'),
                value: formatMoney(currency, dailyAverage),
                change: _buildMetricChange(
                  current: dailyAverage,
                  previous: previousDailyAverage,
                  lowerIsBetter: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrendCard(
    BuildContext context, {
    required String currency,
    required List<_TrendPoint> trendSeries,
    required bool hasTrendData,
    required _TrendPoint? lowestPoint,
    required _TrendPoint? highestPoint,
  }) {
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('analytics_trends_title'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildCardPeriodPill(context),
            ],
          ),
          const SizedBox(height: 18),
          if (!hasTrendData)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 18),
              decoration: BoxDecoration(
                color: ShellStyles.surfaceAlt(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ShellStyles.border(context)),
              ),
              child: Text(
                context.tr('analytics_trends_empty_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            )
          else
            SizedBox(
              height: 236,
              child: LineChart(
                _buildLineChartData(
                  context,
                  currency: currency,
                  trendSeries: trendSeries,
                ),
              ),
            ),
          const AnalyticsFullBleedDivider(topSpacing: 16, bottomSpacing: 16),
          Row(
            children: [
              Expanded(
                child: _RangeInsightTile(
                  label: 'Lowest',
                  value: lowestPoint == null
                      ? context.tr('analytics_no_data')
                      : '${formatMoney(currency, lowestPoint.amount)} - ${lowestPoint.label}',
                  icon: Icons.south_east,
                  tint: ShellStyles.success(context).withAlpha(20),
                  iconColor: ShellStyles.success(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RangeInsightTile(
                  label: 'Highest',
                  value: highestPoint == null
                      ? context.tr('analytics_no_data')
                      : '${formatMoney(currency, highestPoint.amount)} - ${highestPoint.label}',
                  icon: Icons.north_east,
                  tint: ShellStyles.error(context).withAlpha(20),
                  iconColor: ShellStyles.error(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(
    BuildContext context, {
    required String currency,
    required List<_TrendPoint> bars,
  }) {
    final hasBars = bars.any((bar) => bar.amount > 0);
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.filters.period == PeriodFilter.last7Days
                ? context.tr('analytics_trends_daily_breakdown')
                : context.tr('analytics_trends_period_breakdown'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          if (!hasBars)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
              decoration: BoxDecoration(
                color: ShellStyles.surfaceAlt(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ShellStyles.border(context)),
              ),
              child: Text(
                context.tr('analytics_trends_no_breakdown'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            )
          else
            SizedBox(
              height: 236,
              child: BarChart(
                _buildBarChartData(context, currency: currency, bars: bars),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardPeriodPill(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ShellStyles.surfaceAlt(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ShellStyles.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 13,
            color: ShellStyles.textMuted(context),
          ),
          const SizedBox(width: 6),
          Text(
            _trendCardPeriodLabel(context),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildLineChartData(
    BuildContext context, {
    required String currency,
    required List<_TrendPoint> trendSeries,
  }) {
    final values = trendSeries
        .map((point) => point.amount)
        .toList(growable: false);
    final maxValue = values.reduce(math.max);
    final maxY = math.max(maxValue * 1.12, 1).toDouble();
    final interval = math.max(maxY / 4, 1).toDouble();

    return LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (value) => FlLine(
          color: ShellStyles.chartGrid(context),
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchSpotThreshold: 24,
        getTouchedSpotIndicator: (barData, spotIndexes) {
          return spotIndexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(
                    color: ShellStyles.chartGrid(context),
                    strokeWidth: 1,
                    dashArray: const [4, 4],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, dotIndex) =>
                        FlDotCirclePainter(
                          radius: 5,
                          color: ShellStyles.trendPalette(context).first,
                          strokeWidth: 2,
                          strokeColor: ShellStyles.surface(context),
                        ),
                  ),
                ),
              )
              .toList();
        },
        touchTooltipData: LineTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipColor: (_) => ShellStyles.tooltipSurface(context),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          getTooltipItems: (spots) => spots.map((spot) {
            final index = spot.x.round();
            final point = trendSeries[index];
            return LineTooltipItem(
              '${point.tooltipLabel}\nSpent: ${formatMoney(currency, point.amount)}',
              TextStyle(
                color: ShellStyles.tooltipText(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.35,
              ),
            );
          }).toList(),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: interval,
            getTitlesWidget: (value, meta) => Text(
              _formatAxisAmount(currency, value),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 11,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 || index >= trendSeries.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  trendSeries[index].label,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          curveSmoothness: 0.22,
          preventCurveOverShooting: true,
          barWidth: 3,
          color: ShellStyles.trendPalette(context).first,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 4,
              color: ShellStyles.trendPalette(context).first,
              strokeWidth: 2,
              strokeColor: ShellStyles.surface(context),
            ),
          ),
          belowBarData: BarAreaData(show: false),
          spots: [
            for (var index = 0; index < values.length; index++)
              FlSpot(index.toDouble(), values[index]),
          ],
        ),
      ],
    );
  }

  BarChartData _buildBarChartData(
    BuildContext context, {
    required String currency,
    required List<_TrendPoint> bars,
  }) {
    final values = bars.map((bar) => bar.amount).toList(growable: false);
    final maxValue = values.reduce(math.max);
    final maxY = math.max(maxValue * 1.12, 1).toDouble();
    final interval = math.max(maxY / 4, 1).toDouble();

    return BarChartData(
      minY: 0,
      maxY: maxY,
      alignment: values.length == 1
          ? BarChartAlignment.center
          : BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (value) => FlLine(
          color: ShellStyles.chartGrid(context),
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipColor: (_) => ShellStyles.tooltipSurface(context),
          tooltipPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final point = bars[groupIndex];
            return BarTooltipItem(
              '${point.tooltipLabel}\nSpent: ${formatMoney(currency, point.amount)}',
              TextStyle(
                color: ShellStyles.tooltipText(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.35,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: interval,
            getTitlesWidget: (value, meta) => Text(
              _formatAxisAmount(currency, value),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 11,
              ),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 || index >= bars.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  bars[index].label,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (var index = 0; index < values.length; index++)
          BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: values[index],
                width: values.length == 1
                    ? 156
                    : values.length >= 12
                    ? 16
                    : values.length >= 8
                    ? 24
                    : 42,
                color: ShellStyles.trendPalette(context).first,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
            ],
          ),
      ],
    );
  }

  _MetricChange? _buildMetricChange({
    required double current,
    required double? previous,
    required bool lowerIsBetter,
  }) {
    if (previous == null || previous <= 0) {
      return null;
    }
    final deltaPercent = ((current - previous) / previous) * 100;
    final isPositive = lowerIsBetter ? deltaPercent <= 0 : deltaPercent >= 0;
    return _MetricChange(
      percent: deltaPercent.abs(),
      isPositive: isPositive,
      isDownward: deltaPercent <= 0,
    );
  }

  List<_TrendPoint> _buildTrendSeries({
    required String bucketUnit,
    required List<Map<String, dynamic>> rawBuckets,
    required List<double> rawValues,
  }) {
    switch (widget.filters.period) {
      case PeriodFilter.last7Days:
        return _buildDaySeries(rawValues);
      case PeriodFilter.thisMonth:
      case PeriodFilter.last30Days:
        return _buildFixedChunkSeries(rawValues, bucketCount: 4);
      case PeriodFilter.last3Months:
      case PeriodFilter.last6Months:
      case PeriodFilter.last12Months:
      case PeriodFilter.thisYear:
        return _buildMonthlySeries(
          bucketUnit: bucketUnit,
          rawBuckets: rawBuckets,
          rawValues: rawValues,
        );
      case PeriodFilter.allTime:
        return _condenseSeries(
          _buildMonthlySeries(
            bucketUnit: bucketUnit,
            rawBuckets: rawBuckets,
            rawValues: rawValues,
          ),
          maxGroups: 6,
        );
      default:
        return _buildFixedChunkSeries(rawValues, bucketCount: 4);
    }
  }

  List<_TrendPoint> _buildBreakdownSeries(
    BuildContext context, {
    required List<_TrendPoint> trendSeries,
  }) {
    return trendSeries;
  }

  List<_TrendPoint> _buildDaySeries(List<double> rawValues) {
    final start = PeriodFilter.getStartDate(widget.filters.period);
    return [
      for (var index = 0; index < rawValues.length; index++)
        _TrendPoint(
          label: start == null
              ? 'Day ${index + 1}'
              : DateFormat('EEE').format(start.add(Duration(days: index))),
          tooltipLabel: start == null
              ? 'Day ${index + 1}'
              : DateFormat('EEE').format(start.add(Duration(days: index))),
          amount: rawValues[index],
        ),
    ];
  }

  List<_TrendPoint> _buildFixedChunkSeries(
    List<double> rawValues, {
    required int bucketCount,
  }) {
    final series = <_TrendPoint>[];
    if (rawValues.isEmpty) return series;

    final effectiveBucketCount = math.min(bucketCount, rawValues.length);
    for (
      var bucketIndex = 0;
      bucketIndex < effectiveBucketCount;
      bucketIndex++
    ) {
      final start = (bucketIndex * rawValues.length / effectiveBucketCount)
          .floor();
      final end =
          (((bucketIndex + 1) * rawValues.length) / effectiveBucketCount)
              .floor();
      if (start >= end) continue;
      final total = rawValues
          .sublist(start, end)
          .fold<double>(0, (sum, value) => sum + value);
      final label = 'Week ${bucketIndex + 1}';
      series.add(_TrendPoint(label: label, tooltipLabel: label, amount: total));
    }
    return series;
  }

  List<_TrendPoint> _buildMonthlySeries({
    required String bucketUnit,
    required List<Map<String, dynamic>> rawBuckets,
    required List<double> rawValues,
  }) {
    final rangeStart = PeriodFilter.getStartDate(widget.filters.period);
    final grouped = <String, _TrendPointAccumulator>{};

    for (var index = 0; index < rawBuckets.length; index++) {
      final bucketDate = _bucketStartDate(
        bucketUnit: bucketUnit,
        index: index,
        rangeStart: rangeStart,
        rawLabel: rawBuckets[index]['label']?.toString() ?? '',
      );
      final key = bucketDate == null
          ? rawBuckets[index]['label']?.toString() ?? 'Period ${index + 1}'
          : '${bucketDate.year}-${bucketDate.month}';
      final label = bucketDate == null
          ? rawBuckets[index]['label']?.toString() ?? 'Period ${index + 1}'
          : DateFormat('MMM').format(bucketDate);
      final point = grouped.putIfAbsent(
        key,
        () => _TrendPointAccumulator(label: label),
      );
      point.amount += rawValues[index];
    }

    return grouped.values
        .map(
          (point) => _TrendPoint(
            label: point.label,
            tooltipLabel: point.label,
            amount: point.amount,
          ),
        )
        .toList(growable: false);
  }

  DateTime? _bucketStartDate({
    required String bucketUnit,
    required int index,
    required DateTime? rangeStart,
    required String rawLabel,
  }) {
    if (rangeStart != null) {
      switch (bucketUnit) {
        case 'day':
          return rangeStart.add(Duration(days: index));
        case 'week':
          return rangeStart.add(Duration(days: index * 7));
        case 'month':
          return DateTime(rangeStart.year, rangeStart.month + index, 1);
      }
    }

    try {
      if (bucketUnit == 'month') {
        return DateFormat('MMM yyyy').parse(rawLabel);
      }
    } catch (_) {}
    return null;
  }

  List<_TrendPoint> _condenseSeries(
    List<_TrendPoint> series, {
    required int maxGroups,
  }) {
    if (series.length <= maxGroups) return series;

    final chunkSize = (series.length / maxGroups).ceil();
    final condensed = <_TrendPoint>[];
    for (var start = 0; start < series.length; start += chunkSize) {
      final end = math.min(start + chunkSize, series.length);
      final chunk = series.sublist(start, end);
      final total = chunk.fold<double>(0, (sum, point) => sum + point.amount);
      final label = chunk.length == 1
          ? chunk.first.label
          : '${chunk.first.label}-${chunk.last.label}';
      condensed.add(
        _TrendPoint(label: label, tooltipLabel: label, amount: total),
      );
    }
    return condensed;
  }

  String _trendCardPeriodLabel(BuildContext context) {
    if (widget.filters.period == PeriodFilter.last7Days) {
      return context.tr('analytics_trends_this_week');
    }
    return context.tr(PeriodFilter.localizationKey(widget.filters.period));
  }

  String _formatAxisAmount(String currency, double value) {
    final normalizedCurrency = currency.trim().toUpperCase();
    final symbol = CurrencyDisplay.symbolForCode(normalizedCurrency);
    final usesCurrencyCode = symbol == normalizedCurrency;
    final compactValue = value >= 1000
        ? '${value >= 10000 ? (value / 1000).toStringAsFixed(0) : (value / 1000).toStringAsFixed(1)}k'
        : value.toStringAsFixed(0);

    if (moneyFormatSettings.symbolPosition == 'after') {
      final suffix = usesCurrencyCode ? normalizedCurrency : symbol;
      return '$compactValue $suffix';
    }

    if (usesCurrencyCode) {
      return '$normalizedCurrency $compactValue';
    }

    return '$symbol$compactValue';
  }
}

class _TrendMetricCard extends StatelessWidget {
  const _TrendMetricCard({
    required this.label,
    required this.value,
    required this.change,
  });

  final String label;
  final String value;
  final _MetricChange? change;

  @override
  Widget build(BuildContext context) {
    final changeColor = change == null
        ? ShellStyles.textMuted(context)
        : change!.isPositive
        ? ShellColors.softGreen
        : ShellColors.softRed;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 18,
        color: ShellStyles.surface(context),
        withShadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (change == null)
            Text(
              'No prior',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              children: [
                Icon(
                  change!.isDownward ? Icons.south_east : Icons.north_east,
                  size: 13,
                  color: changeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${change!.percent.round()}%',
                  style: TextStyle(
                    color: changeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RangeInsightTile extends StatelessWidget {
  const _RangeInsightTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShellStyles.surfaceAlt(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShellStyles.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
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

class _MetricChange {
  const _MetricChange({
    required this.percent,
    required this.isPositive,
    required this.isDownward,
  });

  final double percent;
  final bool isPositive;
  final bool isDownward;
}

class _TrendPoint {
  const _TrendPoint({
    required this.label,
    required this.tooltipLabel,
    required this.amount,
  });

  final String label;
  final String tooltipLabel;
  final double amount;
}

class _TrendPointAccumulator {
  _TrendPointAccumulator({required this.label});

  final String label;
  double amount = 0;
}
