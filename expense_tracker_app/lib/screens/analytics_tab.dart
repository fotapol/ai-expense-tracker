import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/auto_refresh_state_mixin.dart';
import '../core/category_style.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'analytics_category_detail_screen.dart';
import 'analytics_subcategory_items_screen.dart';
import 'subscription_screen.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({
    super.key,
    required this.filters,
    required this.featureCodes,
    this.activeFiltersBuilder,
  });

  final AnalyticsFilters filters;
  final Set<String> featureCodes;
  final Widget Function()? activeFiltersBuilder;

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab>
    with WidgetsBindingObserver, AutoRefreshStateMixin<AnalyticsTab> {
  static const String _modeCategory = 'category';
  static const String _modeSubcategory = 'subcategory';
  static const String _advancedAnalyticsCode = 'premium.analytics.advanced';

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summaryData;
  String _breakdownMode = _modeCategory;
  bool _isRefreshingAnalytics = false;

  @override
  Duration get autoRefreshInterval => const Duration(minutes: 1);

  @override
  Future<void> performAutoRefresh() => _fetchSummary(showLoader: false);

  bool get _hasAdvancedAnalytics =>
      widget.featureCodes.contains(_advancedAnalyticsCode);

  @override
  void initState() {
    super.initState();
    _loadBreakdownMode();
  }

  @override
  void didUpdateWidget(covariant AnalyticsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final featureCodesChanged = !setEquals(
      oldWidget.featureCodes,
      widget.featureCodes,
    );
    if (!_hasAdvancedAnalytics && _breakdownMode == _modeSubcategory) {
      _breakdownMode = _modeCategory;
      _saveBreakdownMode();
    }
    if (oldWidget.filters != widget.filters || featureCodesChanged) {
      _fetchSummary();
    }
  }

  Future<void> _loadBreakdownMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('analytics_breakdown_mode');
    if (!mounted) return;
    setState(() {
      if (savedMode != null &&
          <String>{_modeCategory, _modeSubcategory}.contains(savedMode)) {
        _breakdownMode = savedMode;
      }
      if (!_hasAdvancedAnalytics && _breakdownMode == _modeSubcategory) {
        _breakdownMode = _modeCategory;
      }
    });
    _fetchSummary();
  }

  Future<void> _saveBreakdownMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_breakdown_mode', _breakdownMode);
  }

  Future<void> _fetchSummary({bool showLoader = true}) async {
    if (_isRefreshingAnalytics) return;
    _isRefreshingAnalytics = true;
    if (!mounted) {
      _isRefreshingAnalytics = false;
      return;
    }
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final effectiveBreakdownMode = _hasAdvancedAnalytics
        ? _breakdownMode
        : _modeCategory;
    try {
      final data = await ApiClient.getTransactionsSummary(
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
        groupBy: effectiveBreakdownMode,
      );
      if (!mounted) return;
      setState(() {
        _breakdownMode = effectiveBreakdownMode;
        _summaryData = data;
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      if (showLoader || _summaryData == null) {
        setState(() {
          _error = friendlyLaunchErrorMessage(
            error,
            fallback:
                'Analytics could not refresh right now. Please try again.',
          );
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshingAnalytics = false;
    }
  }

  Future<void> _setBreakdownMode(String mode) async {
    if (mode == _breakdownMode) return;
    if (mode == _modeSubcategory && !_hasAdvancedAnalytics) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      return;
    }

    setState(() => _breakdownMode = mode);
    await _saveBreakdownMode();
    _fetchSummary();
  }

  Color _categoryColor(Map<String, dynamic> category) {
    final code = category['code']?.toString() ?? '';
    final name = category['name']?.toString() ?? '';
    final parentCode = category['parent_category_code']?.toString() ?? '';
    final palette = ShellStyles.isDark(context)
        ? const <Color>[
            Color(0xFFF5F1EA),
            Color(0xFFDAD3C8),
            Color(0xFFC1BAAF),
            Color(0xFFA79F96),
            Color(0xFF8C857D),
            Color(0xFF716A64),
          ]
        : const <Color>[
            Color(0xFF1A1817),
            Color(0xFF34312F),
            Color(0xFF4C4946),
            Color(0xFF64615D),
            Color(0xFF7C7873),
            Color(0xFF95918B),
          ];
    final seed = '$code|$name|$parentCode'.trim().toUpperCase();
    if (seed.isEmpty) return palette.first;

    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  String _breakdownName(Map<String, dynamic> breakdown) {
    return localizeCategoryByCode(
      context,
      code: breakdown['code']?.toString(),
      fallbackName: breakdown['name']?.toString(),
    );
  }

  void _openCategoryDetails(Map<String, dynamic> category) {
    final categoryId = category['category_id']?.toString();
    if (categoryId == null || categoryId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsCategoryDetailScreen(
          categoryId: categoryId,
          categoryName: _breakdownName(category),
          categoryCode: category['code']?.toString() ?? '',
          fromDate: PeriodFilter.getStartDate(widget.filters.period),
          selectedCategoryIds: widget.filters.categoryIds,
          selectedSubcategoryIds: widget.filters.subcategoryIds,
          selectedLabelIds: widget.filters.labelIds,
        ),
      ),
    );
  }

  void _openSubcategoryDetails(Map<String, dynamic> subcategory) {
    final subcategoryId = subcategory['subcategory_id']?.toString();
    if (subcategoryId == null || subcategoryId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsSubcategoryItemsScreen(
          subcategoryId: subcategoryId,
          subcategoryName: _breakdownName(subcategory),
          subcategoryCode: subcategory['code']?.toString() ?? '',
          fromDate: PeriodFilter.getStartDate(widget.filters.period),
          selectedCategoryIds: widget.filters.categoryIds,
          selectedSubcategoryIds: widget.filters.subcategoryIds,
          selectedLabelIds: widget.filters.labelIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _summaryData != null;
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
                onPressed: _fetchSummary,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final summaryData = _summaryData ?? const <String, dynamic>{};
    final totalAmount = (summaryData['total_amount'] as num?)?.toDouble() ?? 0;
    final totalTransactions =
        (summaryData['total_transactions'] as num?)?.toInt() ?? 0;
    final breakdown = summaryData['breakdown'] as List<dynamic>? ?? const [];
    final currency = (summaryData['currency']?.toString() ?? 'EUR')
        .toUpperCase();
    final isSubcategoryMode = _breakdownMode == _modeSubcategory;
    final isEmptyAnalytics =
        totalTransactions == 0 && breakdown.isEmpty && totalAmount <= 0;

    return RefreshIndicator(
      onRefresh: _fetchSummary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (widget.activeFiltersBuilder != null) ...[
            widget.activeFiltersBuilder!(),
            const SizedBox(height: 16),
          ],
          if (isEmptyAnalytics)
            _buildEmptyStateCard()
          else ...[
            _buildTotalCard(
              totalAmount: totalAmount,
              totalTransactions: totalTransactions,
              currency: currency,
            ),
            const SizedBox(height: 16),
            _buildBreakdownHeader(isSubcategoryMode: isSubcategoryMode),
            const SizedBox(height: 16),
            _buildPieChart(
              breakdown,
              totalAmount,
              currency,
              isSubcategoryMode: isSubcategoryMode,
            ),
            const SizedBox(height: 16),
            _buildBreakdownList(
              breakdown,
              currency,
              isSubcategoryMode: isSubcategoryMode,
            ),
            const SizedBox(height: 16),
            _buildDiscountSection(currency),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyStateCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No insights yet',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan receipts to see spending by category, totals, and savings here.',
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

  Widget _buildTotalCard({
    required double totalAmount,
    required int totalTransactions,
    required String currency,
  }) {
    final averagePerDay =
        totalAmount / PeriodFilter.getPeriodDays(widget.filters.period);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShellStyles.cardDecoration(context, radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
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
          const SizedBox(height: 14),
          Text(
            formatMoney(currency, totalAmount),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSnapshotMetric(
                  label: context.tr('analytics_average_per_day'),
                  value: formatMoney(currency, averagePerDay),
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: ShellStyles.border(context),
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              Expanded(
                child: _buildSnapshotMetric(
                  label: context.tr('analytics_total_transactions'),
                  value: '$totalTransactions',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotMetric({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: ShellStyles.textMuted(context), fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownHeader({required bool isSubcategoryMode}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                  isSubcategoryMode
                      ? 'analytics_expense_subcategories'
                      : 'analytics_expense_categories',
                ),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('analytics_categories_subtitle'),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _buildBreakdownToggle(),
      ],
    );
  }

  Widget _buildBreakdownToggle() {
    Widget option({
      required String mode,
      required String label,
      bool locked = false,
    }) {
      final isSelected = _breakdownMode == mode;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _setBreakdownMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: isSelected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.surfaceAlt(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: isSelected
                      ? ShellStyles.surface(context)
                      : ShellStyles.textMuted(context),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? ShellStyles.surface(context)
                      : ShellStyles.textPrimary(context),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        option(
          mode: _modeCategory,
          label: context.tr('analytics_breakdown_categories'),
        ),
        const SizedBox(width: 8),
        option(
          mode: _modeSubcategory,
          label: context.tr('analytics_breakdown_subcategories'),
          locked: !_hasAdvancedAnalytics,
        ),
      ],
    );
  }

  Widget _buildPieChart(
    List<dynamic> breakdown,
    double totalAmount,
    String currency, {
    required bool isSubcategoryMode,
  }) {
    final categories = breakdown.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
    final hasData = categories.isNotEmpty && totalAmount > 0;
    final sections = hasData
        ? categories.map((category) {
            final amount = (category['amount'] as num?)?.toDouble() ?? 0;
            final percentage =
                (category['percentage'] as num?)?.toDouble() ?? 0;
            final sectionColor = _categoryColor(category);
            final titleColor =
                ThemeData.estimateBrightnessForColor(sectionColor) ==
                    Brightness.dark
                ? Colors.white
                : ShellColors.lightText;
            return PieChartSectionData(
              color: sectionColor,
              value: amount,
              title: percentage >= 7 ? '${percentage.toStringAsFixed(0)}%' : '',
              radius: 56,
              titleStyle: TextStyle(
                color: titleColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            );
          }).toList()
        : [
            PieChartSectionData(
              color: ShellStyles.surfaceAlt(context),
              value: 1,
              title: '',
              radius: 56,
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 70,
                    sections: sections,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasData
                          ? formatMoney(currency, totalAmount)
                          : context.tr('analytics_no_data'),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: hasData ? 18 : 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                        hasData
                            ? 'analytics_total_spent'
                            : isSubcategoryMode
                            ? 'analytics_no_subcategory_data'
                            : 'analytics_no_category_data',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasData) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: categories.map((category) {
                final color = _categoryColor(category);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _breakdownName(category),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownList(
    List<dynamic> breakdown,
    String currency, {
    required bool isSubcategoryMode,
  }) {
    final categories = breakdown.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: ShellStyles.cardDecoration(context, radius: 24),
        child: Text(
          context.tr(
            isSubcategoryMode
                ? 'analytics_no_subcategory_data'
                : 'analytics_no_category_data',
          ),
          style: TextStyle(color: ShellStyles.textMuted(context)),
        ),
      );
    }

    return Column(
      children: categories.map((category) {
        final code = category['code']?.toString() ?? '';
        final amount = (category['amount'] as num?)?.toDouble() ?? 0;
        final itemCount = (category['item_count'] as num?)?.toInt() ?? 0;
        final percentage = (category['percentage'] as num?)?.toDouble() ?? 0;
        final color = _categoryColor(category);
        final icon = CategoryStyle.iconForCode(code);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => isSubcategoryMode
                ? _openSubcategoryDetails(category)
                : _openCategoryDetails(category),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: ShellStyles.cardDecoration(context, radius: 20),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _breakdownName(category),
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            'analytics_money_and_purchases',
                            params: {
                              'amount': formatMoney(currency, amount),
                              'count': itemCount.toString(),
                            },
                          ),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Icon(
                        Icons.chevron_right,
                        color: ShellStyles.textMuted(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDiscountSection(String currency) {
    final discounts = _summaryData?['discounts'];
    if (discounts is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    final totalSavings = (discounts['total_savings'] as num?)?.toDouble() ?? 0;
    final itemsWithDiscount =
        (discounts['items_with_discount'] as num?)?.toInt() ?? 0;
    final biggestDiscount =
        discounts['biggest_discount'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('analytics_discounts_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (totalSavings <= 0 &&
              itemsWithDiscount <= 0 &&
              biggestDiscount == null)
            Text(
              context.tr('analytics_no_discounts'),
              style: TextStyle(color: ShellStyles.textMuted(context)),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _buildDiscountMetric(
                    label: context.tr('analytics_total_savings'),
                    value: formatMoney(currency, totalSavings),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDiscountMetric(
                    label: context.tr('analytics_items_with_discount'),
                    value: '$itemsWithDiscount',
                  ),
                ),
              ],
            ),
            if (biggestDiscount != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ShellStyles.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('analytics_biggest_discount'),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      biggestDiscount['description']?.toString() ??
                          context.tr('analytics_unknown_item'),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(
                        currency,
                        (biggestDiscount['amount'] as num?)?.toDouble() ?? 0,
                      ),
                      style: const TextStyle(
                        color: ShellColors.softGreen,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountMetric({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShellStyles.surfaceAlt(context),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
