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
import '../widgets/analytics_shared.dart';
import 'analytics_category_detail_screen.dart';
import 'analytics_subcategory_items_screen.dart';
import 'subscription_screen.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({
    super.key,
    required this.filters,
    required this.featureCodes,
    this.onPremiumStatusChanged,
    this.activeFiltersBuilder,
  });

  final AnalyticsFilters filters;
  final Set<String> featureCodes;
  final Future<void> Function()? onPremiumStatusChanged;
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

  Future<void> _fetchSummary({
    bool showLoader = true,
    String? breakdownModeOverride,
  }) async {
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

    final effectiveBreakdownMode =
        breakdownModeOverride ??
        (_hasAdvancedAnalytics ? _breakdownMode : _modeCategory);
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
      final upgraded = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      if (widget.onPremiumStatusChanged != null) {
        await widget.onPremiumStatusChanged!();
      }
      if (!mounted || upgraded != true) return;
      setState(() => _breakdownMode = mode);
      await _saveBreakdownMode();
      await _fetchSummary(breakdownModeOverride: mode);
      return;
    }

    setState(() => _breakdownMode = mode);
    await _saveBreakdownMode();
    _fetchSummary();
  }

  Color _categoryColor(Map<String, dynamic> category) {
    return ShellStyles.categoryTone(
      context,
      code: category['code']?.toString(),
      parentCode: category['parent_category_code']?.toString(),
      name: category['name']?.toString(),
    ).base;
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
      return const AnalyticsLoadingState();
    }
    if (_error != null && !hasData) {
      return AnalyticsErrorState(
        message: _error ?? context.tr('common_error'),
        onRetry: _fetchSummary,
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
          if (isEmptyAnalytics)
            AnalyticsEmptyCard(
              icon: Icons.pie_chart_outline,
              title: 'No category insights yet',
              message:
                  'Scan receipts to see your spending share by category and drill into the biggest areas.',
            )
          else ...[
            _buildDonutCard(
              context,
              breakdown,
              totalAmount,
              currency,
              isSubcategoryMode: isSubcategoryMode,
            ),
            const SizedBox(height: 16),
            _buildBreakdownListCard(
              context,
              breakdown,
              currency,
              isSubcategoryMode: isSubcategoryMode,
            ),
            if (_shouldShowDiscountSection()) ...[
              const SizedBox(height: 16),
              _buildDiscountSection(currency),
            ],
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

  Widget _buildDonutCard(
    BuildContext context,
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
            final tone = ShellStyles.categoryTone(
              context,
              code: category['code']?.toString(),
              parentCode: category['parent_category_code']?.toString(),
              name: category['name']?.toString(),
            );
            return PieChartSectionData(
              color: tone.base,
              value: amount,
              title: percentage >= 9 ? '${percentage.toStringAsFixed(0)}%' : '',
              radius: 58,
              titleStyle: TextStyle(
                color: tone.onSolid,
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
              radius: 58,
            ),
          ];

    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsSectionHeader(
            title: isSubcategoryMode
                ? context.tr('analytics_expense_subcategories')
                : context.tr('analytics_expense_categories'),
            subtitle: 'The donut shows each group’s share of total spend.',
            trailing: _buildBreakdownToggle(),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 236,
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
                        context.tr('analytics_total_spent').toUpperCase(),
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasData
                            ? formatMoney(currency, totalAmount)
                            : context.tr('analytics_no_data'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: hasData ? 18 : 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          if (!hasData)
            Text(
              context.tr(
                isSubcategoryMode
                    ? 'analytics_no_subcategory_data'
                    : 'analytics_no_category_data',
              ),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            )
          else
            Column(
              children: categories.map((category) {
                final amount = (category['amount'] as num?)?.toDouble() ?? 0;
                final percentage =
                    (category['percentage'] as num?)?.toDouble() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _categoryColor(category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _breakdownName(category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: Text(
                          formatMoney(currency, amount),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildBreakdownToggle() {
    Widget option({
      required String mode,
      required String label,
      bool locked = false,
    }) {
      final isSelected = _breakdownMode == mode;
      final background = isSelected
          ? ShellStyles.textPrimary(context)
          : ShellStyles.surfaceAlt(context);
      final foreground = isSelected
          ? ShellStyles.surface(context)
          : ShellStyles.textPrimary(context);
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _setBreakdownMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: background,
            border: Border.all(
              color: isSelected
                  ? ShellStyles.textPrimary(context)
                  : ShellStyles.border(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                CrownIcon(
                  size: 14,
                  color: isSelected ? foreground : ShellColors.gold,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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

  Widget _buildBreakdownListCard(
    BuildContext context,
    List<dynamic> breakdown,
    String currency, {
    required bool isSubcategoryMode,
  }) {
    final categories = breakdown.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsSectionHeader(
            title: isSubcategoryMode
                ? 'Subcategory details'
                : 'Category details',
            subtitle: isSubcategoryMode
                ? 'Open a subcategory to review the matching items.'
                : 'Open a category to see the underlying subcategories.',
          ),
          const SizedBox(height: 14),
          if (categories.isEmpty)
            Text(
              context.tr(
                isSubcategoryMode
                    ? 'analytics_no_subcategory_data'
                    : 'analytics_no_category_data',
              ),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            )
          else
            for (var index = 0; index < categories.length; index++) ...[
              if (index != 0) const AnalyticsFullBleedDivider(),
              _buildBreakdownRow(
                context,
                category: categories[index],
                currency: currency,
                isSubcategoryMode: isSubcategoryMode,
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(
    BuildContext context, {
    required Map<String, dynamic> category,
    required String currency,
    required bool isSubcategoryMode,
  }) {
    final code = category['code']?.toString() ?? '';
    final amount = (category['amount'] as num?)?.toDouble() ?? 0;
    final itemCount = (category['item_count'] as num?)?.toInt() ?? 0;
    final percentage = (category['percentage'] as num?)?.toDouble() ?? 0;
    final tone = ShellStyles.categoryTone(
      context,
      code: code,
      parentCode: category['parent_category_code']?.toString(),
      name: category['name']?.toString(),
    );
    final icon = CategoryStyle.iconForCode(code);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => isSubcategoryMode
          ? _openSubcategoryDetails(category)
          : _openCategoryDetails(category),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: ShellStyles.semanticBadgeDecoration(
                context,
                tone: tone,
                radius: 14,
              ),
              child: Icon(icon, color: tone.foreground, size: 19),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'analytics_purchases_count',
                      params: {'count': itemCount.toString()},
                    ),
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
                  formatMoney(currency, amount),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      color: ShellStyles.textMuted(context),
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowDiscountSection() {
    final discounts = _summaryData?['discounts'];
    if (discounts is! Map<String, dynamic>) return false;

    final totalSavings = (discounts['total_savings'] as num?)?.toDouble() ?? 0;
    final itemsWithDiscount =
        (discounts['items_with_discount'] as num?)?.toInt() ?? 0;
    final biggestDiscount =
        discounts['biggest_discount'] as Map<String, dynamic>?;
    return totalSavings > 0 || itemsWithDiscount > 0 || biggestDiscount != null;
  }

  Widget _buildDiscountSection(String currency) {
    final discounts = _summaryData?['discounts'] as Map<String, dynamic>;
    final totalSavings = (discounts['total_savings'] as num?)?.toDouble() ?? 0;
    final itemsWithDiscount =
        (discounts['items_with_discount'] as num?)?.toInt() ?? 0;
    final biggestDiscount =
        discounts['biggest_discount'] as Map<String, dynamic>?;

    return AnalyticsSurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsSectionHeader(
            title: 'Discounts',
            subtitle: 'Helpful savings spotted in the current results.',
            trailing: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: ShellStyles.iconBadgeDecoration(
                context,
                color: ShellStyles.surfaceAlt(context),
                radius: 14,
              ),
              child: const Icon(
                Icons.sell_outlined,
                size: 18,
                color: ShellColors.softGreen,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AnalyticsMiniStatTile(
                  label: context.tr('analytics_total_savings'),
                  value: formatMoney(currency, totalSavings),
                  icon: Icons.sell_outlined,
                  valueColor: ShellColors.softGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnalyticsMiniStatTile(
                  label: context.tr('analytics_items_with_discount'),
                  value: '$itemsWithDiscount',
                  icon: Icons.local_offer_outlined,
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
                border: Border.all(color: ShellStyles.border(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ShellStyles.surface(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ShellStyles.border(context)),
                    ),
                    child: const Icon(
                      Icons.local_offer_outlined,
                      size: 18,
                      color: ShellColors.softGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('analytics_biggest_discount'),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
                            (biggestDiscount['amount'] as num?)?.toDouble() ??
                                0,
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
              ),
            ),
          ],
        ],
      ),
    );
  }
}
