import 'package:flutter/material.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../widgets/analytics_shared.dart';

class AnalyticsOverviewTab extends StatefulWidget {
  const AnalyticsOverviewTab({
    super.key,
    required this.filters,
    this.activeFiltersBuilder,
  });

  final AnalyticsFilters filters;
  final Widget Function()? activeFiltersBuilder;

  @override
  State<AnalyticsOverviewTab> createState() => _AnalyticsOverviewTabState();
}

class _AnalyticsOverviewTabState extends State<AnalyticsOverviewTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summaryData;
  Map<String, dynamic>? _trendsData;
  List<dynamic> _transactions = const <dynamic>[];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didUpdateWidget(covariant AnalyticsOverviewTab oldWidget) {
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

    try {
      final results = await Future.wait<dynamic>([
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
          groupBy: 'category',
        ),
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
        ApiClient.listTransactions(
          fromDate: fromDate,
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
        _summaryData = results[0] as Map<String, dynamic>;
        _trendsData = results[1] as Map<String, dynamic>;
        _transactions = results[2] as List<dynamic>;
        _isLoading = false;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback:
              'Overview insights are unavailable right now. Please try again.',
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

  double _displayAmountOf(Map<String, dynamic> transaction) {
    final raw =
        transaction['display_amount_total'] ?? transaction['amount_total'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  List<_MerchantInsight> _topMerchants(
    BuildContext context, {
    required double totalAmount,
  }) {
    final totals = <String, _MerchantInsightAccumulator>{};
    for (final raw in _transactions.whereType<Map<String, dynamic>>()) {
      final merchantName =
          raw['merchant_name']?.toString().trim().isNotEmpty == true
          ? raw['merchant_name']!.toString().trim()
          : context.tr('receipts_unknown_store');
      final amount = _displayAmountOf(raw);
      if (amount <= 0) continue;
      final current = totals.putIfAbsent(
        merchantName,
        () => _MerchantInsightAccumulator(name: merchantName),
      );
      current.amount += amount;
      current.count += 1;
    }

    final merchants =
        totals.values
            .map(
              (merchant) => _MerchantInsight(
                name: merchant.name,
                amount: merchant.amount,
                count: merchant.count,
                share: totalAmount > 0 ? merchant.amount / totalAmount : 0,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.amount.compareTo(left.amount));

    return merchants.take(5).toList(growable: false);
  }

  List<_CategoryInsight> _topCategories(
    BuildContext context, {
    required Map<String, dynamic> summary,
    required double totalAmount,
  }) {
    final breakdown =
        summary['breakdown'] as List<dynamic>? ?? const <dynamic>[];
    final categories =
        breakdown
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              final amount = _parseDouble(entry['amount']);
              final percentage = _parseDouble(entry['percentage']);
              return _CategoryInsight(
                name: localizeCategoryByCode(
                  context,
                  code: entry['code']?.toString(),
                  fallbackName: entry['name']?.toString(),
                ),
                amount: amount,
                share: percentage > 0
                    ? percentage / 100
                    : totalAmount > 0
                    ? amount / totalAmount
                    : 0,
              );
            })
            .where((entry) => entry.amount > 0)
            .toList(growable: false)
          ..sort((left, right) => right.amount.compareTo(left.amount));
    return categories.take(4).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final hasData =
        _summaryData != null || _trendsData != null || _transactions.isNotEmpty;
    if (_isLoading && !hasData) {
      return const AnalyticsLoadingState();
    }
    if (_error != null && !hasData) {
      return AnalyticsErrorState(
        message: _error ?? context.tr('common_error'),
        onRetry: _fetchData,
      );
    }

    final summary = _summaryData ?? const <String, dynamic>{};
    final trends = _trendsData ?? const <String, dynamic>{};
    final totalAmount = _parseDouble(summary['total_amount']);
    final totalTransactions =
        (summary['total_transactions'] as num?)?.toInt() ?? 0;
    final discounts =
        summary['discounts'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final totalSavings = _parseDouble(discounts['total_savings']);
    final currency = (summary['currency']?.toString() ?? 'EUR').toUpperCase();
    final previousTotal = trends['previous_total_amount'] != null
        ? _parseDouble(trends['previous_total_amount'])
        : null;
    final changePercentage = trends['change_percentage'] != null
        ? _parseDouble(trends['change_percentage'])
        : null;
    final dailyAverage =
        totalAmount / PeriodFilter.getPeriodDays(widget.filters.period);
    final topMerchants = _topMerchants(context, totalAmount: totalAmount);
    final topCategories = _topCategories(
      context,
      summary: summary,
      totalAmount: totalAmount,
    );
    final isEmptyOverview =
        totalTransactions == 0 &&
        totalAmount <= 0 &&
        topMerchants.isEmpty &&
        topCategories.isEmpty;

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
          if (isEmptyOverview)
            AnalyticsEmptyCard(
              icon: Icons.insights_outlined,
              title: 'No overview yet',
              message:
                  'Scan receipts to track totals, compare periods, and surface your top merchants here.',
            )
          else ...[
            _buildSummaryCard(
              context,
              currency: currency,
              totalAmount: totalAmount,
              totalTransactions: totalTransactions,
              totalSavings: totalSavings,
              dailyAverage: dailyAverage,
              previousTotal: previousTotal,
              changePercentage: changePercentage,
            ),
            const SizedBox(height: 16),
            _buildTopMerchantsCard(
              context,
              currency: currency,
              merchants: topMerchants,
            ),
            const SizedBox(height: 16),
            _buildTopCategoriesCard(
              context,
              currency: currency,
              categories: topCategories,
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

  Widget _buildSummaryCard(
    BuildContext context, {
    required String currency,
    required double totalAmount,
    required int totalTransactions,
    required double totalSavings,
    required double dailyAverage,
    required double? previousTotal,
    required double? changePercentage,
  }) {
    final comparison = _comparisonCopy(
      context,
      previousTotal: previousTotal,
      changePercentage: changePercentage,
    );
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      radius: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('analytics_total_spent').toUpperCase(),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(currency, totalAmount),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
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
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
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
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ShellStyles.surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ShellStyles.border(context)),
                  ),
                  child: Icon(
                    comparison.icon,
                    size: 18,
                    color: comparison.color ?? ShellStyles.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comparison.title,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AnalyticsMiniStatTile(
                  label: context.tr('analytics_total_transactions'),
                  value: '$totalTransactions',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnalyticsMiniStatTile(
                  label: context.tr('analytics_average_per_day'),
                  value: formatMoney(currency, dailyAverage),
                  icon: Icons.calendar_today_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnalyticsMiniStatTile(
                  label: context.tr('analytics_total_savings'),
                  value: formatMoney(currency, totalSavings),
                  icon: Icons.sell_outlined,
                  valueColor: totalSavings > 0 ? ShellColors.softGreen : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopMerchantsCard(
    BuildContext context, {
    required String currency,
    required List<_MerchantInsight> merchants,
  }) {
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AnalyticsSectionHeader(
            title: 'Top Merchants',
            subtitle: 'Where the most spending happened in this period.',
          ),
          const SizedBox(height: 14),
          if (merchants.isEmpty)
            Text(
              'Merchant insights will appear after more receipts are scanned.',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            )
          else
            for (var index = 0; index < merchants.length; index++) ...[
              if (index != 0)
                Divider(height: 22, color: ShellStyles.border(context)),
              _buildMerchantRow(
                context,
                rank: index + 1,
                currency: currency,
                merchant: merchants[index],
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildTopCategoriesCard(
    BuildContext context, {
    required String currency,
    required List<_CategoryInsight> categories,
  }) {
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AnalyticsSectionHeader(
            title: 'Top Categories',
            subtitle: 'The biggest spending groups in this period.',
          ),
          const SizedBox(height: 14),
          if (categories.isEmpty)
            Text(
              'Category highlights will appear after more spending is recorded.',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            )
          else
            for (var index = 0; index < categories.length; index++) ...[
              if (index != 0)
                Divider(height: 22, color: ShellStyles.border(context)),
              _buildCategoryRow(
                context,
                rank: index + 1,
                currency: currency,
                category: categories[index],
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildMerchantRow(
    BuildContext context, {
    required int rank,
    required String currency,
    required _MerchantInsight merchant,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ShellStyles.surfaceAlt(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ShellStyles.border(context)),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                merchant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                merchant.count == 1
                    ? '1 transaction'
                    : '${merchant.count} transactions',
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(currency, merchant.amount),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${(merchant.share * 100).round()}% of spend',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryRow(
    BuildContext context, {
    required int rank,
    required String currency,
    required _CategoryInsight category,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ShellStyles.surfaceAlt(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ShellStyles.border(context)),
          ),
          child: Text(
            '$rank',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(currency, category.amount),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${(category.share * 100).round()}% of spend',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  _OverviewComparisonCopy _comparisonCopy(
    BuildContext context, {
    required double? previousTotal,
    required double? changePercentage,
  }) {
    if (previousTotal == null) {
      return const _OverviewComparisonCopy(
        icon: Icons.timeline_outlined,
        title: 'Previous comparison is unavailable for this range.',
      );
    }
    if (previousTotal <= 0) {
      return const _OverviewComparisonCopy(
        icon: Icons.remove_circle_outline,
        title: 'No spend was recorded in the matching previous period.',
      );
    }
    if (changePercentage == null || changePercentage == 0) {
      return _OverviewComparisonCopy(
        icon: Icons.compare_arrows_outlined,
        title: context.tr('analytics_change_flat'),
      );
    }
    return _OverviewComparisonCopy(
      icon: changePercentage > 0 ? Icons.trending_up : Icons.trending_down,
      title: context.tr(
        changePercentage > 0
            ? 'analytics_change_more'
            : 'analytics_change_less',
        params: {'percent': changePercentage.abs().round().toString()},
      ),
      supporting: 'Compared with the matching previous period.',
      color: changePercentage > 0 ? ShellColors.softRed : ShellColors.softGreen,
    );
  }
}

class _MerchantInsightAccumulator {
  _MerchantInsightAccumulator({required this.name});

  final String name;
  double amount = 0;
  int count = 0;
}

class _MerchantInsight {
  const _MerchantInsight({
    required this.name,
    required this.amount,
    required this.count,
    required this.share,
  });

  final String name;
  final double amount;
  final int count;
  final double share;
}

class _OverviewComparisonCopy {
  const _OverviewComparisonCopy({
    required this.icon,
    required this.title,
    this.supporting,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? supporting;
  final Color? color;
}

class _CategoryInsight {
  const _CategoryInsight({
    required this.name,
    required this.amount,
    required this.share,
  });

  final String name;
  final double amount;
  final double share;
}
