import 'package:flutter/material.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'household_screen.dart';

class AnalyticsOverviewTab extends StatefulWidget {
  const AnalyticsOverviewTab({
    super.key,
    required this.filters,
    required this.currentHousehold,
    required this.onHouseholdUpdated,
  });

  final AnalyticsFilters filters;
  final Map<String, dynamic>? currentHousehold;
  final Future<void> Function() onHouseholdUpdated;

  @override
  State<AnalyticsOverviewTab> createState() => _AnalyticsOverviewTabState();
}

class _AnalyticsOverviewTabState extends State<AnalyticsOverviewTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summaryData;
  Map<String, dynamic>? _trendsData;
  Map<String, dynamic>? _householdData;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didUpdateWidget(covariant AnalyticsOverviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters ||
        oldWidget.currentHousehold?['id']?.toString() !=
            widget.currentHousehold?['id']?.toString()) {
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
      final requests = <Future<Map<String, dynamic>>>[
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
      ];
      final shouldLoadHousehold = widget.currentHousehold != null;
      if (shouldLoadHousehold) {
        requests.add(
          ApiClient.getHouseholdAnalyticsSummary(
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
        );
      }

      final results = await Future.wait(requests);
      if (!mounted) return;
      setState(() {
        _summaryData = results[0];
        _trendsData = results[1];
        _householdData = shouldLoadHousehold && results.length > 2
            ? results[2]
            : null;
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
    final hasData = _summaryData != null || _trendsData != null;
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

    final summary = _summaryData ?? const <String, dynamic>{};
    final trends = _trendsData ?? const <String, dynamic>{};
    final totalAmount = (summary['total_amount'] as num?)?.toDouble() ?? 0;
    final totalTransactions =
        (summary['total_transactions'] as num?)?.toInt() ?? 0;
    final discounts = summary['discounts'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final totalSavings =
        (discounts['total_savings'] as num?)?.toDouble() ?? 0;
    final currency = (summary['currency']?.toString() ?? 'EUR').toUpperCase();
    final breakdown = summary['breakdown'] as List<dynamic>? ?? const [];
    final previousTotal =
        (trends['previous_total_amount'] as num?)?.toDouble();
    final changePercentage =
        (trends['change_percentage'] as num?)?.toDouble();

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildHeroCard(
            context,
            currency: currency,
            totalAmount: totalAmount,
            previousTotal: previousTotal,
            changePercentage: changePercentage,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                context,
                icon: Icons.calendar_today_outlined,
                title: context.tr('analytics_average_per_day'),
                value: formatMoney(
                  currency,
                  totalAmount / PeriodFilter.getPeriodDays(widget.filters.period),
                ),
              ),
              _buildMetricCard(
                context,
                icon: Icons.receipt_long_outlined,
                title: context.tr('analytics_total_transactions'),
                value: '$totalTransactions',
              ),
              _buildMetricCard(
                context,
                icon: Icons.sell_outlined,
                title: context.tr('analytics_total_savings'),
                value: formatMoney(currency, totalSavings),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTopCategoriesCard(
            context,
            currency: currency,
            breakdown: breakdown,
            totalAmount: totalAmount,
          ),
          if (widget.currentHousehold != null) ...[
            const SizedBox(height: 16),
            _buildHouseholdPreviewCard(
              context,
              currency: currency,
              householdData: _householdData,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required String currency,
    required double totalAmount,
    required double? previousTotal,
    required double? changePercentage,
  }) {
    final changeLabel = changePercentage == null
        ? context.tr('analytics_change_unavailable')
        : changePercentage == 0
            ? context.tr('analytics_change_flat')
            : context.tr(
                changePercentage > 0
                    ? 'analytics_change_more'
                    : 'analytics_change_less',
                params: {
                  'percent': changePercentage.abs().toStringAsFixed(1),
                },
              );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShellStyles.textPrimary(context),
            ShellStyles.textPrimary(context).withAlpha(220),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context
                      .tr(PeriodFilter.localizationKey(widget.filters.period))
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.insights_outlined, color: Colors.white.withAlpha(220)),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            context.tr('analytics_total_spent'),
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(currency, totalAmount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(16),
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
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('analytics_compared_with_previous'),
                        style: TextStyle(
                          color: Colors.white.withAlpha(170),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        changeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (previousTotal != null)
                  Text(
                    formatMoney(currency, previousTotal),
                    style: TextStyle(
                      color: Colors.white.withAlpha(170),
                      fontSize: 13,
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
    required IconData icon,
    required String title,
    required String value,
  }) {
    final width = (MediaQuery.of(context).size.width - 64) / 2;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ShellStyles.textMuted(context), size: 20),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategoriesCard(
    BuildContext context, {
    required String currency,
    required List<dynamic> breakdown,
    required double totalAmount,
  }) {
    final topCategories = breakdown
        .whereType<Map<String, dynamic>>()
        .take(4)
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr('analytics_tab_categories'),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                context.tr('analytics_overview_top_categories'),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (topCategories.isEmpty)
            Text(
              context.tr('analytics_no_category_data'),
              style: TextStyle(color: ShellStyles.textMuted(context)),
            )
          else
            for (final category in topCategories) ...[
              Builder(
                builder: (context) {
                  final name = localizeCategoryByCode(
                    context,
                    code: category['code']?.toString(),
                    fallbackName: category['name']?.toString(),
                  );
                  final amount =
                      (category['amount'] as num?)?.toDouble() ?? 0;
                  final percentage =
                      (category['percentage'] as num?)?.toDouble() ?? 0;
                  final normalizedProgress = totalAmount > 0
                      ? (amount / totalAmount).clamp(0.0, 1.0)
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatMoney(currency, amount),
                              style: TextStyle(
                                color: ShellStyles.textPrimary(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            value: normalizedProgress,
                            backgroundColor: ShellStyles.surfaceAlt(context),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              ShellColors.softBlue,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildHouseholdPreviewCard(
    BuildContext context, {
    required String currency,
    required Map<String, dynamic>? householdData,
  }) {
    final householdName =
        householdData?['household']?['name']?.toString() ??
        widget.currentHousehold?['name']?.toString() ??
        context.tr('analytics_tab_households');
    final totalAmount =
        (householdData?['total_amount'] as num?)?.toDouble() ?? 0;
    final members =
        householdData?['members'] as List<dynamic>? ?? const <dynamic>[];

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HouseholdScreen()),
        );
        await widget.onHouseholdUpdated();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: ShellStyles.cardDecoration(context, radius: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_outlined, color: ShellColors.softGreen),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    householdName,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: ShellStyles.textMuted(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatMoney(currency, totalAmount),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('analytics_household_preview_subtitle'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            if (members.isEmpty)
              Text(
                context.tr('analytics_household_no_data'),
                style: TextStyle(color: ShellStyles.textMuted(context)),
              )
            else
              for (final rawMember in members.take(3)) ...[
                Builder(
                  builder: (context) {
                    final member = rawMember as Map<String, dynamic>;
                    final name =
                        member['user']?['display_name']?.toString().trim();
                    final email = member['user']?['email']?.toString().trim();
                    final label = (name != null && name.isNotEmpty)
                        ? name
                        : (email != null && email.isNotEmpty)
                              ? email
                              : context.tr('home_default_user');
                    final amount =
                        (member['total_amount'] as num?)?.toDouble() ?? 0;
                    final percentage =
                        (member['percentage'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: ShellStyles.textPrimary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            formatMoney(currency, amount),
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }
}
