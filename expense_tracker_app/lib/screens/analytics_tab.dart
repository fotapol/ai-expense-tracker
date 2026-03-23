import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/auto_refresh_state_mixin.dart';
import '../core/category_style.dart';
import '../core/period_filter.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'analytics_category_detail_screen.dart';
import 'analytics_subcategory_items_screen.dart';
import 'subscription_screen.dart';

class AnalyticsTab extends StatefulWidget {
  final bool showTopBar;

  const AnalyticsTab({super.key, this.showTopBar = true});

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
  String _selectedPeriod = PeriodFilter.last3Months;
  String _breakdownMode = _modeCategory;
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];
  List<String> _selectedLabelIds = [];
  Map<String, String> _categoryNamesById = {};
  Map<String, String> _labelNamesById = {};
  Set<String> _featureCodes = <String>{};
  bool _isRefreshingAnalytics = false;

  @override
  Duration get autoRefreshInterval => const Duration(seconds: 10);

  @override
  Future<void> performAutoRefresh() => _refreshAnalytics(showLoader: false);

  String _currencySymbol(String code) {
    final normalized = code.toUpperCase();
    if (normalized == 'EUR') return '\u20AC';
    if (normalized == 'USD') return '\$';
    if (normalized == 'GBP') return '\u00A3';
    if (normalized == 'AUD') return 'A\$';
    if (normalized == 'CAD') return 'C\$';
    if (normalized == 'RSD') return 'RSD ';
    switch (code.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      case 'RSD':
        return 'RSD ';
      default:
        return '${code.toUpperCase()} ';
    }
  }

  String _formatMoney(String currency, double amount) {
    final symbol = _currencySymbol(currency);
    if (symbol != '${currency.toUpperCase()} ') {
      final sign = amount < 0 ? '-' : '';
      return '$sign$symbol${amount.abs().toStringAsFixed(2)}';
    }
    return '${currency.toUpperCase()} ${amount.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();
    _loadFiltersAndFetch();
  }

  Future<void> _loadFiltersAndFetch() async {
    final prefsFuture = SharedPreferences.getInstance();
    final categoriesFuture = ApiClient.listCategories();
    final labelsFuture = ApiClient.listLabels();
    final entitlementsFuture = ApiClient.getMeEntitlements();

    final prefs = await prefsFuture;
    final savedPeriod = prefs.getString('analytics_period');
    final savedMode = prefs.getString('analytics_breakdown_mode');
    final savedCats = prefs.getStringList('analytics_category_ids');
    final savedSubcats = prefs.getStringList('analytics_subcategory_ids');
    final savedLabels = prefs.getStringList('analytics_label_ids');
    Map<String, String> categoryNames = {};
    Map<String, String> labelNames = {};
    Set<String> featureCodes = <String>{};
    try {
      final categories = await categoriesFuture;
      if (!mounted) return;
      categoryNames = {
        for (final cat in categories)
          if (cat['id'] != null)
            cat['id'].toString(): localizeCategoryByCode(
              context,
              code: cat['code']?.toString(),
              fallbackName: cat['name']?.toString(),
            ),
      };
    } catch (_) {}
    try {
      final labels = await labelsFuture;
      labelNames = {
        for (final label in labels)
          if (label['id'] != null && label['name'] != null)
            label['id'].toString(): label['name'].toString(),
      };
    } catch (_) {}
    try {
      final entitlements = await entitlementsFuture;
      featureCodes =
          (entitlements['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
              .map((code) => code.toString())
              .toSet();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      if (savedPeriod != null) _selectedPeriod = savedPeriod;
      if (savedMode != null &&
          <String>{_modeCategory, _modeSubcategory}.contains(savedMode)) {
        _breakdownMode = savedMode;
      }
      if (savedCats != null) _selectedCategoryIds = savedCats;
      if (savedSubcats != null) _selectedSubcategoryIds = savedSubcats;
      if (savedLabels != null) _selectedLabelIds = savedLabels;
      _categoryNamesById = categoryNames;
      _labelNamesById = labelNames;
      _featureCodes = featureCodes;
      if (!_hasAdvancedAnalytics && _breakdownMode == _modeSubcategory) {
        _breakdownMode = _modeCategory;
      }
    });
    _fetchSummary();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_period', _selectedPeriod);
    await prefs.setString('analytics_breakdown_mode', _breakdownMode);
    await prefs.setStringList('analytics_category_ids', _selectedCategoryIds);
    await prefs.setStringList(
      'analytics_subcategory_ids',
      _selectedSubcategoryIds,
    );
    await prefs.setStringList('analytics_label_ids', _selectedLabelIds);
  }

  Future<void> _fetchSummary() async {
    await _refreshAnalytics(showLoader: true);
  }

  Future<void> _refreshAnalytics({bool showLoader = true}) async {
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

    try {
      final entitlements = await ApiClient.getMeEntitlements();
      final featureCodes =
          (entitlements['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
              .map((code) => code.toString())
              .toSet();
      final effectiveBreakdownMode =
          featureCodes.contains(_advancedAnalyticsCode)
          ? _breakdownMode
          : _modeCategory;
      final startDate = PeriodFilter.getStartDate(_selectedPeriod);
      final data = await ApiClient.getTransactionsSummary(
        fromDate: startDate,
        categoryIds: _selectedCategoryIds.isNotEmpty
            ? _selectedCategoryIds
            : null,
        subcategoryIds: _selectedSubcategoryIds.isNotEmpty
            ? _selectedSubcategoryIds
            : null,
        labelIds: _selectedLabelIds.isNotEmpty ? _selectedLabelIds : null,
        groupBy: effectiveBreakdownMode,
      );
      if (!mounted) return;
      setState(() {
        _featureCodes = featureCodes;
        _breakdownMode = effectiveBreakdownMode;
        _summaryData = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (showLoader || _summaryData == null) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshingAnalytics = false;
    }
  }

  bool get _hasAdvancedAnalytics =>
      _featureCodes.contains(_advancedAnalyticsCode);

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _selectedPeriod,
      selectedCategoryIds: _selectedCategoryIds,
      selectedSubcategoryIds: _selectedSubcategoryIds,
      selectedLabelIds: _selectedLabelIds,
    );
    if (result == null) return;

    setState(() {
      _selectedPeriod = result['period'] as String;
      _selectedCategoryIds = List<String>.from(result['category_ids'] ?? []);
      _selectedSubcategoryIds = List<String>.from(
        result['subcategory_ids'] ?? [],
      );
      _selectedLabelIds = List<String>.from(result['label_ids'] ?? []);
    });
    await _saveFilters();
    _fetchSummary();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _selectedCategoryIds.clear();
      _selectedSubcategoryIds.clear();
      _selectedLabelIds.clear();
    });
    await _saveFilters();
    _fetchSummary();
  }

  Widget _buildFilterChip(String label, {IconData? icon, Color? color}) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: chipColor),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    final hasFilters =
        _selectedCategoryIds.isNotEmpty ||
        _selectedSubcategoryIds.isNotEmpty ||
        _selectedLabelIds.isNotEmpty;
    if (!hasFilters) return const SizedBox.shrink();

    final categoryLabels = _selectedCategoryIds
        .map((id) => _categoryNamesById[id] ?? context.tr('filters_category'))
        .toList();
    final subcategoryLabels = _selectedSubcategoryIds
        .map(
          (id) => _categoryNamesById[id] ?? context.tr('filters_subcategory'),
        )
        .toList();
    final labelLabels = _selectedLabelIds
        .map((id) => _labelNamesById[id] ?? context.tr('filters_labels'))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...categoryLabels.map(
                    (label) => _buildFilterChip(
                      label,
                      icon: Icons.category,
                      color: const Color(0xFFAB47BC),
                    ),
                  ),
                  ...subcategoryLabels.map(
                    (label) => _buildFilterChip(
                      label,
                      icon: Icons.account_tree,
                      color: const Color(0xFF29B6F6),
                    ),
                  ),
                  ...labelLabels.map(
                    (label) => _buildFilterChip(
                      label,
                      icon: Icons.label,
                      color: const Color(0xFF66BB6A),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _clearFilters,
            icon: const Icon(Icons.cancel),
            color: Colors.grey.shade400,
            tooltip: context.tr('filters_clear_all'),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(Map<String, dynamic> cat) {
    final code = cat['code']?.toString() ?? '';
    final name = cat['name']?.toString() ?? '';
    final parentCode = cat['parent_category_code']?.toString() ?? '';
    return CategoryStyle.colorForSeed('$code|$name|$parentCode');
  }

  String _breakdownName(Map<String, dynamic> breakdown) {
    return localizeCategoryByCode(
      context,
      code: breakdown['code']?.toString(),
      fallbackName: breakdown['name']?.toString(),
    );
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
    await _saveFilters();
    _fetchSummary();
  }

  void _openCategoryDetails(Map<String, dynamic> category) {
    final categoryId = category['category_id']?.toString();
    if (categoryId == null || categoryId.isEmpty) return;

    final name = localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
    final code = category['code']?.toString() ?? '';
    final fromDate = PeriodFilter.getStartDate(_selectedPeriod);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsCategoryDetailScreen(
          categoryId: categoryId,
          categoryName: name,
          categoryCode: code,
          fromDate: fromDate,
          selectedCategoryIds: _selectedCategoryIds,
          selectedSubcategoryIds: _selectedSubcategoryIds,
          selectedLabelIds: _selectedLabelIds,
        ),
      ),
    );
  }

  void _openSubcategoryDetails(Map<String, dynamic> subcategory) {
    final subcategoryId = subcategory['subcategory_id']?.toString();
    if (subcategoryId == null || subcategoryId.isEmpty) return;

    final fromDate = PeriodFilter.getStartDate(_selectedPeriod);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsSubcategoryItemsScreen(
          subcategoryId: subcategoryId,
          subcategoryName: _breakdownName(subcategory),
          subcategoryCode: subcategory['code']?.toString() ?? '',
          fromDate: fromDate,
          selectedCategoryIds: _selectedCategoryIds,
          selectedSubcategoryIds: _selectedSubcategoryIds,
          selectedLabelIds: _selectedLabelIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTopBar) _buildTopBar(),
          _buildActiveFiltersBar(),
          const SizedBox(height: 8),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.tr('nav_analytics'),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            color: Theme.of(context).colorScheme.primary,
            onPressed: _openFilters,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error ?? context.tr('common_error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchSummary,
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      );
    }

    final totalAmount =
        (_summaryData?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalTransactions =
        (_summaryData?['total_transactions'] as num?)?.toInt() ?? 0;
    final breakdown = _summaryData?['breakdown'] as List<dynamic>? ?? [];
    final currency = (_summaryData?['currency']?.toString() ?? 'EUR')
        .toUpperCase();
    final isSubcategoryMode = _breakdownMode == _modeSubcategory;

    final bottomPadding = MediaQuery.of(context).padding.bottom + 32;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(totalAmount, totalTransactions, currency),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(
                    isSubcategoryMode
                        ? 'analytics_expense_subcategories'
                        : 'analytics_expense_categories',
                  ),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              _buildBreakdownToggle(),
            ],
          ),
          const SizedBox(height: 24),
          _buildPieChart(
            breakdown,
            totalAmount,
            currency,
            isSubcategoryMode: isSubcategoryMode,
          ),
          const SizedBox(height: 20),
          _buildBreakdownList(
            breakdown,
            currency,
            isSubcategoryMode: isSubcategoryMode,
          ),
          const SizedBox(height: 24),
          _buildDiscountSection(currency),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTotalCard(
    double totalAmount,
    int totalTransactions,
    String currency,
  ) {
    int periodDays = 30;
    if (_selectedPeriod == PeriodFilter.last3Months) periodDays = 90;
    if (_selectedPeriod == PeriodFilter.thisYear) {
      periodDays = DateTime.now()
          .difference(DateTime(DateTime.now().year, 1, 1))
          .inDays
          .clamp(1, 366);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6A1B9A), Color(0xFF4527A0)],
        ),
      ),
      child: Column(
        children: [
          Text(
            context
                .tr(PeriodFilter.localizationKey(_selectedPeriod))
                .toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _formatMoney(currency, totalAmount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(
                    context.tr('analytics_average_per_day'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatMoney(currency, totalAmount / periodDays),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Column(
                children: [
                  Text(
                    context.tr('analytics_total_transactions'),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalTransactions',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ],
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
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _setBreakdownMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: isSelected
                ? const Color(0xFF5B2E88).withAlpha(210)
                : Colors.black.withAlpha(25),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFF7D74B)
                  : Colors.white.withAlpha(70),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked) ...[
                const Icon(Icons.lock_outline, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
    List<dynamic> categories,
    double totalAmount,
    String currency, {
    required bool isSubcategoryMode,
  }) {
    final hasData = categories.isNotEmpty && totalAmount > 0;

    final sections = <PieChartSectionData>[];
    if (hasData) {
      for (final raw in categories) {
        final cat = raw as Map<String, dynamic>;
        final amount = (cat['amount'] as num?)?.toDouble() ?? 0.0;
        final percentage = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
        sections.add(
          PieChartSectionData(
            color: _categoryColor(cat),
            value: amount,
            title: percentage >= 5 ? '${percentage.toStringAsFixed(1)}%' : '',
            radius: 54,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      }
    } else {
      sections.addAll([
        PieChartSectionData(
          color: Color(0xFF2D2D37),
          value: 34,
          title: '',
          radius: 54,
        ),
        PieChartSectionData(
          color: Color(0xFF24242D),
          value: 33,
          title: '',
          radius: 54,
        ),
        PieChartSectionData(
          color: Color(0xFF1E1E26),
          value: 33,
          title: '',
          radius: 54,
        ),
      ]);
    }

    return Column(
      children: [
        SizedBox(
          height: 236,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 68,
                  sections: sections,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasData) ...[
                    Text(
                      _formatMoney(currency, totalAmount),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      context.tr('analytics_total_spent'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ] else
                    Text(
                      context.tr('analytics_no_data'),
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (hasData) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: categories.map((raw) {
                final cat = raw as Map<String, dynamic>;
                final name = _breakdownName(cat);
                final color = _categoryColor(cat);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(name, style: TextStyle(color: Colors.grey.shade300)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBreakdownList(
    List<dynamic> categories,
    String currency, {
    required bool isSubcategoryMode,
  }) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          context.tr(
            isSubcategoryMode
                ? 'analytics_no_subcategory_data'
                : 'analytics_no_category_data',
          ),
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }

    return Column(
      children: categories.asMap().entries.map((entry) {
        final index = entry.key;
        final cat = entry.value as Map<String, dynamic>;
        final name = _breakdownName(cat);
        final code = cat['code']?.toString() ?? '';
        final amount = (cat['amount'] as num?)?.toDouble() ?? 0.0;
        final itemCount = (cat['item_count'] as num?)?.toInt() ?? 0;
        final percentage = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
        final color = _categoryColor(cat);
        final icon = CategoryStyle.iconForCode(code);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(180),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => isSubcategoryMode
                ? _openSubcategoryDetails(cat)
                : _openCategoryDetails(cat),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withAlpha(35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr(
                            'analytics_money_and_purchases',
                            params: {
                              'amount': _formatMoney(currency, amount),
                              'count': itemCount.toString(),
                            },
                          ),
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        color: index.isEven
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
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
    final discountsRaw = _summaryData?['discounts'];
    if (discountsRaw is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    final totalSavings =
        (discountsRaw['total_savings'] as num?)?.toDouble() ?? 0.0;
    final itemsWithDiscount =
        (discountsRaw['items_with_discount'] as num?)?.toInt() ?? 0;
    final biggestDiscountRaw = discountsRaw['biggest_discount'];
    final biggestDiscount = biggestDiscountRaw is Map<String, dynamic>
        ? biggestDiscountRaw
        : null;

    if (totalSavings <= 0 &&
        itemsWithDiscount <= 0 &&
        biggestDiscount == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('analytics_discounts_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withAlpha(200),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                context.tr('analytics_no_discounts'),
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final accent = const Color(0xFFF7D74B);
    final biggestDescription =
        biggestDiscount?['description']?.toString().trim() ?? '';
    final biggestAmount =
        (biggestDiscount?['amount'] as num?)?.toDouble() ?? 0.0;
    final biggestPercentage = (biggestDiscount?['percentage'] as num?)
        ?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('analytics_discounts_title'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(200),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatMoney(currency, totalSavings),
                          style: TextStyle(
                            color: accent,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('analytics_total_savings'),
                          style: TextStyle(
                            color: accent.withAlpha(230),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$itemsWithDiscount',
                          style: TextStyle(
                            color: accent,
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('analytics_items_with_discount'),
                          style: TextStyle(
                            color: accent.withAlpha(230),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (biggestDescription.isNotEmpty && biggestAmount > 0) ...[
                const SizedBox(height: 16),
                Divider(color: Colors.grey.shade800),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.sell_outlined, color: accent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      context.tr('analytics_biggest_discount'),
                      style: TextStyle(
                        color: accent.withAlpha(230),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  biggestDescription,
                  style: TextStyle(
                    color: accent.withAlpha(240),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  biggestPercentage != null
                      ? '${_formatMoney(currency, biggestAmount)} (${biggestPercentage.toStringAsFixed(1)}%)'
                      : _formatMoney(currency, biggestAmount),
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
