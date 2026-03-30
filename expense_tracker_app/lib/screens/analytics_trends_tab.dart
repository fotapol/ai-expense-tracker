import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';

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
  Map<String, dynamic>? _data;

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

    try {
      final data = await ApiClient.getTransactionTrendSummary(
        fromDate: PeriodFilter.getStartDate(widget.filters.period),
        toDate: PeriodFilter.getEndDate(widget.filters.period),
        categoryIds: widget.filters.categoryIds.isNotEmpty
            ? widget.filters.categoryIds
            : null,
        subcategoryIds: widget.filters.subcategoryIds.isNotEmpty
            ? widget.filters.subcategoryIds
            : null,
        labelIds: widget.filters.labelIds.isNotEmpty
            ? widget.filters.labelIds
            : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback:
              'Trend insights are unavailable right now. Please try again.',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _data != null;
    if (_isLoading && !hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && !hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: ShellColors.softRed, size: 42),
              const SizedBox(height: 12),
              Text(
                _error ?? context.tr('common_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: ShellStyles.textMuted(context)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetchData,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data ?? const <String, dynamic>{};
    final currency = (data['currency']?.toString() ?? 'EUR').toUpperCase();
    final currentTotal = _parseDouble(data['current_total_amount']);
    final previousTotal = data['previous_total_amount'] != null
        ? _parseDouble(data['previous_total_amount'])
        : null;
    final changePercentage = data['change_percentage'] != null
        ? _parseDouble(data['change_percentage'])
        : null;
    final bucketUnit = data['bucket_unit']?.toString() ?? 'week';
    final buckets = (data['buckets'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final numericBuckets = buckets
        .map((bucket) => _parseDouble(bucket['amount']))
        .toList(growable: false);
    final hasChartData = numericBuckets.any((value) => value > 0);
    final highestBucketIndex = numericBuckets.isEmpty
        ? -1
        : numericBuckets.indexOf(numericBuckets.reduce(math.max));
    final highestBucket = highestBucketIndex >= 0
        ? buckets[highestBucketIndex]
        : null;
    final averageBucketSpend = buckets.isEmpty
        ? 0.0
        : currentTotal / buckets.length;
    final isEmptyTrends = currentTotal <= 0 && buckets.isEmpty;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (widget.activeFiltersBuilder != null) ...[
            widget.activeFiltersBuilder!(),
            const SizedBox(height: 16),
          ],
          if (isEmptyTrends)
            _buildEmptyStateCard(context)
          else ...[
            _buildSummaryCard(
              context,
              currency: currency,
              currentTotal: currentTotal,
              previousTotal: previousTotal,
              changePercentage: changePercentage,
              bucketUnit: bucketUnit,
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              context,
              currency: currency,
              bucketUnit: bucketUnit,
              buckets: buckets,
              hasChartData: hasChartData,
              averageBucketSpend: averageBucketSpend,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricCard(
                  context,
                  title: 'Peak ${_bucketUnitLabel(bucketUnit)} spend',
                  value: highestBucket == null
                      ? context.tr('analytics_no_data')
                      : formatMoney(
                          currency,
                          _parseDouble(highestBucket['amount']),
                        ),
                  subtitle: highestBucket == null
                      ? 'No bucket data in this period.'
                      : highestBucket['label']?.toString() ??
                            'No bucket data in this period.',
                ),
                _buildMetricCard(
                  context,
                  title: 'Average per ${_bucketUnitLabel(bucketUnit)}',
                  value: formatMoney(currency, averageBucketSpend),
                  subtitle: buckets.isEmpty
                      ? 'No bucket data in this period.'
                      : '${buckets.length} ${_bucketUnitPlural(bucketUnit, buckets.length)} in this period',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyStateCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No trend data yet',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan receipts over time to see spending patterns and compare periods here.',
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

  double _parseDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String currency,
    required double currentTotal,
    required double? previousTotal,
    required double? changePercentage,
    required String bucketUnit,
  }) {
    final comparison = _buildComparisonCopy(
      context,
      previousTotal: previousTotal,
      changePercentage: changePercentage,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('analytics_tab_trends'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: ShellStyles.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ShellStyles.border(context)),
                ),
                child: Text(
                  context
                      .tr(PeriodFilter.localizationKey(widget.filters.period))
                      .toUpperCase(),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Total spend across ${_bucketUnitPlural(bucketUnit, 2)}',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(currency, currentTotal),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ShellStyles.surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ShellStyles.border(context)),
                  ),
                  child: Icon(
                    comparison.icon,
                    color: ShellStyles.textPrimary(context),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comparison.title,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (comparison.supporting != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          comparison.supporting!,
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (previousTotal != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Previous period',
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatMoney(currency, previousTotal),
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
  }) {
    final width = (MediaQuery.of(context).size.width - 64) / 2;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    BuildContext context, {
    required String currency,
    required String bucketUnit,
    required List<Map<String, dynamic>> buckets,
    required bool hasChartData,
    required double averageBucketSpend,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('analytics_trends_chart_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _chartSubtitle(bucketUnit),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          if (!hasChartData)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: ShellStyles.surfaceAlt(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ShellStyles.border(context)),
              ),
              child: Center(
                child: Text(
                  context.tr('analytics_trends_no_data'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 280,
              child: BarChart(
                _buildChartData(
                  context,
                  currency: currency,
                  buckets: buckets,
                  averageBucketSpend: averageBucketSpend,
                ),
              ),
            ),
        ],
      ),
    );
  }

  BarChartData _buildChartData(
    BuildContext context, {
    required String currency,
    required List<Map<String, dynamic>> buckets,
    required double averageBucketSpend,
  }) {
    final values = buckets
        .map((bucket) => _parseDouble(bucket['amount']))
        .toList(growable: false);
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);
    final maxY = math.max(maxValue * 1.25, 1.0);
    final labelStep = values.length <= 4
        ? 1
        : math.max((values.length / 4).ceil(), 1);

    return BarChartData(
      minY: 0,
      maxY: maxY,
      alignment: BarChartAlignment.spaceBetween,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 4,
        getDrawingHorizontalLine: (value) => FlLine(
          color: ShellStyles.border(context),
          strokeWidth: value == averageBucketSpend ? 1.4 : 1,
          dashArray: value == averageBucketSpend ? <int>[6, 4] : null,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: maxY / 4,
            getTitlesWidget: (value, meta) => Text(
              _formatAxisAmount(value),
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
            reservedSize: 38,
            interval: labelStep.toDouble(),
            getTitlesWidget: (value, meta) {
              final index = value.round();
              final shouldShow =
                  index == 0 ||
                  index == buckets.length - 1 ||
                  index % labelStep == 0;
              if (!shouldShow || index < 0 || index >= buckets.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _compactBucketLabel(buckets[index]),
                  textAlign: TextAlign.center,
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
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          if (averageBucketSpend > 0)
            HorizontalLine(
              y: averageBucketSpend,
              color: ShellStyles.textMuted(context).withAlpha(110),
              strokeWidth: 1.4,
              dashArray: <int>[6, 4],
            ),
        ],
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final bucket = buckets[group.x.toInt()];
            return BarTooltipItem(
              '${bucket['label'] ?? ''}\n${formatMoney(currency, rod.toY)}',
              TextStyle(
                color: ShellStyles.surface(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            );
          },
        ),
      ),
      barGroups: [
        for (var index = 0; index < values.length; index++)
          BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: values[index],
                width: _barWidth(values.length),
                color: index == _peakBucketIndex(values)
                    ? ShellStyles.textPrimary(context)
                    : ShellStyles.textPrimary(
                        context,
                      ).withAlpha(ShellStyles.isDark(context) ? 140 : 110),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: ShellStyles.surfaceAlt(context),
                ),
              ),
            ],
          ),
      ],
    );
  }

  double _barWidth(int count) {
    if (count >= 18) return 8;
    if (count >= 12) return 12;
    if (count >= 8) return 16;
    return 22;
  }

  int _peakBucketIndex(List<double> values) {
    if (values.isEmpty) return -1;
    return values.indexOf(values.reduce(math.max));
  }

  String _bucketUnitLabel(String bucketUnit) {
    switch (bucketUnit) {
      case 'day':
        return 'day';
      case 'month':
        return 'month';
      case 'week':
      default:
        return 'week';
    }
  }

  String _bucketUnitPlural(String bucketUnit, int count) {
    final unit = _bucketUnitLabel(bucketUnit);
    if (count == 1) return unit;
    return '${unit}s';
  }

  String _chartSubtitle(String bucketUnit) {
    switch (bucketUnit) {
      case 'day':
        return 'Daily totals for the selected period.';
      case 'month':
        return 'Monthly totals for the selected period.';
      case 'week':
      default:
        return 'Weekly totals for the selected period.';
    }
  }

  String _compactBucketLabel(Map<String, dynamic> bucket) {
    final label = bucket['label']?.toString() ?? '';
    if (label.contains(' - ')) {
      return label.split(' - ').first;
    }
    final parts = label.split(' ');
    if (parts.length >= 2 && parts[1].length == 4) {
      return parts.first;
    }
    return label;
  }

  String _formatAxisAmount(double value) {
    if (value >= 1000) {
      final compact = value >= 10000
          ? (value / 1000).toStringAsFixed(0)
          : (value / 1000).toStringAsFixed(1);
      return '${compact}k';
    }
    if (value >= 100) {
      return value.toStringAsFixed(0);
    }
    if (value >= 10) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  }

  _TrendComparisonCopy _buildComparisonCopy(
    BuildContext context, {
    required double? previousTotal,
    required double? changePercentage,
  }) {
    if (previousTotal == null) {
      return const _TrendComparisonCopy(
        icon: Icons.timeline_outlined,
        title: 'Previous comparison is not available for this range.',
        supporting:
            'Choose a fixed period to compare against the prior window.',
      );
    }
    if (previousTotal <= 0) {
      return const _TrendComparisonCopy(
        icon: Icons.remove_circle_outline,
        title: 'No spending was recorded in the previous period.',
        supporting:
            'A percentage change needs spending in both periods, so it stays hidden here.',
      );
    }
    if (changePercentage == null || changePercentage == 0) {
      return _TrendComparisonCopy(
        icon: Icons.compare_arrows_outlined,
        title: context.tr('analytics_change_flat'),
        supporting: 'You spent almost the same as in the previous period.',
      );
    }
    return _TrendComparisonCopy(
      icon: changePercentage > 0 ? Icons.trending_up : Icons.trending_down,
      title: context.tr(
        changePercentage > 0
            ? 'analytics_change_more'
            : 'analytics_change_less',
        params: {'percent': changePercentage.abs().toStringAsFixed(1)},
      ),
      supporting: 'Compared with the matching previous period.',
    );
  }
}

class _TrendComparisonCopy {
  const _TrendComparisonCopy({
    required this.icon,
    required this.title,
    this.supporting,
  });

  final IconData icon;
  final String title;
  final String? supporting;
}
