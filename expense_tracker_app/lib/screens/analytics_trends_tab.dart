import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class AnalyticsTrendsTab extends StatefulWidget {
  const AnalyticsTrendsTab({
    super.key,
    required this.filters,
  });

  final AnalyticsFilters filters;

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
      if (!mounted) return;
      setState(() {
        _error = error.toString();
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
              Icon(
                Icons.error_outline,
                color: ShellColors.softRed,
                size: 42,
              ),
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
    final previousTotal = data['previous_total_amount'] != null ? _parseDouble(data['previous_total_amount']) : null;
    final changePercentage = data['change_percentage'] != null ? _parseDouble(data['change_percentage']) : null;
    final buckets = data['buckets'] as List<dynamic>? ?? const <dynamic>[];
    final numericBuckets = buckets
        .whereType<Map<String, dynamic>>()
        .map((bucket) => _parseDouble(bucket['amount']))
        .toList();
    final hasChartData = numericBuckets.any((value) => value > 0);
    final highestBucketIndex = numericBuckets.isEmpty
        ? 0
        : numericBuckets.indexOf(
            numericBuckets.reduce(math.max),
          );
    final highestBucket = buckets.isEmpty
        ? null
        : buckets[highestBucketIndex] as Map<String, dynamic>;
    final averageBucketSpend = buckets.isEmpty
        ? 0
        : currentTotal / buckets.length;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildSummaryCard(
            context,
            currency: currency,
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            changePercentage: changePercentage,
          ),
          const SizedBox(height: 16),
          Container(
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
                  context.tr('analytics_trends_chart_subtitle'),
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
                    height: 250,
                    child: LineChart(
                      _buildChartData(
                        context,
                        buckets: buckets.whereType<Map<String, dynamic>>().toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                context,
                title: context.tr('analytics_trends_highest_bucket'),
                value: highestBucket == null
                    ? context.tr('analytics_no_data')
                    : formatMoney(
                        currency,
                        _parseDouble(highestBucket['amount']),
                      ),
                subtitle:
                    highestBucket?['label']?.toString() ??
                    context.tr('analytics_change_unavailable'),
              ),
              _buildMetricCard(
                context,
                title: context.tr('analytics_trends_average_bucket'),
                value: formatMoney(currency, averageBucketSpend),
                subtitle: context
                    .tr(PeriodFilter.localizationKey(widget.filters.period)),
              ),
            ],
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
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('analytics_tab_trends'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('analytics_trends_period_label'),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            formatMoney(currency, currentTotal),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                  changePercentage == null
                      ? Icons.timeline_outlined
                      : changePercentage >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                  color: ShellColors.softBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    changePercentage == null
                        ? context.tr('analytics_change_unavailable')
                        : context.tr(
                            changePercentage > 0
                                ? 'analytics_change_more'
                                : 'analytics_change_less',
                            params: {
                              'percent': changePercentage.abs().toStringAsFixed(1),
                            },
                          ),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (previousTotal != null)
                  Text(
                    formatMoney(currency, previousTotal),
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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

  LineChartData _buildChartData(
    BuildContext context, {
    required List<Map<String, dynamic>> buckets,
  }) {
    final values = buckets
        .map((bucket) => _parseDouble(bucket['amount']))
        .toList();
    final hasSinglePoint = values.length == 1;
    final chartValues = hasSinglePoint ? <double>[values.first, values.first] : values;
    final maxY = chartValues.isEmpty
        ? 1.0
        : math.max(chartValues.reduce(math.max) * 1.2, 1.0);

    return LineChartData(
      minX: 0,
      maxX: math.max(chartValues.length - 1, 1).toDouble(),
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 4,
        getDrawingHorizontalLine: (value) => FlLine(
          color: ShellStyles.border(context),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            interval: maxY / 4,
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(0),
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
            interval: chartValues.length > 3
                ? math.max((chartValues.length / 3).ceilToDouble(), 1)
                : 1,
            getTitlesWidget: (value, meta) {
              final index = value.round();
              if (index < 0 || index >= buckets.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  buckets[index]['label']?.toString() ?? '',
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
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          fitInsideHorizontally: true,
          fitInsideVertically: true,
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          preventCurveOverShooting: true,
          color: ShellColors.softBlue,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3.5,
              color: ShellStyles.surface(context),
              strokeWidth: 2,
              strokeColor: ShellColors.softBlue,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ShellColors.softBlue.withAlpha(80),
                ShellColors.softBlue.withAlpha(8),
              ],
            ),
          ),
          spots: [
            for (var index = 0; index < chartValues.length; index++)
              FlSpot(index.toDouble(), chartValues[index]),
          ],
        ),
      ],
    );
  }
}
