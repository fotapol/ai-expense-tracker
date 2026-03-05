import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/period_filter.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'analytics_category_detail_screen.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summaryData;
  String _selectedPeriod = PeriodFilter.last3Months;
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];
  Map<String, String> _categoryNamesById = {};

  @override
  void initState() {
    super.initState();
    _loadFiltersAndFetch();
  }

  Future<void> _loadFiltersAndFetch() async {
    final prefsFuture = SharedPreferences.getInstance();
    final categoriesFuture = ApiClient.listCategories();

    final prefs = await prefsFuture;
    final savedPeriod = prefs.getString('analytics_period');
    final savedCats = prefs.getStringList('analytics_category_ids');
    final savedSubcats = prefs.getStringList('analytics_subcategory_ids');
    Map<String, String> categoryNames = {};
    try {
      final categories = await categoriesFuture;
      categoryNames = {
        for (final cat in categories)
          if (cat['id'] != null && cat['name'] != null)
            cat['id'].toString(): cat['name'].toString(),
      };
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      if (savedPeriod != null) _selectedPeriod = savedPeriod;
      if (savedCats != null) _selectedCategoryIds = savedCats;
      if (savedSubcats != null) _selectedSubcategoryIds = savedSubcats;
      _categoryNamesById = categoryNames;
    });
    _fetchSummary();
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_period', _selectedPeriod);
    await prefs.setStringList('analytics_category_ids', _selectedCategoryIds);
    await prefs.setStringList(
      'analytics_subcategory_ids',
      _selectedSubcategoryIds,
    );
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startDate = PeriodFilter.getStartDate(_selectedPeriod);
      final data = await ApiClient.getTransactionsSummary(
        fromDate: startDate,
        categoryIds: _selectedCategoryIds.isNotEmpty
            ? _selectedCategoryIds
            : null,
        subcategoryIds: _selectedSubcategoryIds.isNotEmpty
            ? _selectedSubcategoryIds
            : null,
      );
      if (!mounted) return;
      setState(() {
        _summaryData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _selectedPeriod,
      selectedCategoryIds: _selectedCategoryIds,
      selectedSubcategoryIds: _selectedSubcategoryIds,
    );
    if (result == null) return;

    setState(() {
      _selectedPeriod = result['period'] as String;
      _selectedCategoryIds = List<String>.from(result['category_ids'] ?? []);
      _selectedSubcategoryIds = List<String>.from(
        result['subcategory_ids'] ?? [],
      );
    });
    await _saveFilters();
    _fetchSummary();
  }

  Future<void> _clearCategoryFilters() async {
    setState(() {
      _selectedCategoryIds.clear();
      _selectedSubcategoryIds.clear();
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
    final hasCategoryFilters =
        _selectedCategoryIds.isNotEmpty || _selectedSubcategoryIds.isNotEmpty;
    if (!hasCategoryFilters) return const SizedBox.shrink();

    final categoryLabels = _selectedCategoryIds
        .map((id) => _categoryNamesById[id] ?? 'Category')
        .toList();
    final subcategoryLabels = _selectedSubcategoryIds
        .map((id) => _categoryNamesById[id] ?? 'Subcategory')
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _clearCategoryFilters,
            icon: const Icon(Icons.cancel),
            color: Colors.grey.shade400,
            tooltip: 'Clear category filters',
          ),
        ],
      ),
    );
  }

  Color _categoryColor(Map<String, dynamic> cat) {
    return CategoryStyle.colorForCode(cat['code']?.toString());
  }

  void _openCategoryDetails(Map<String, dynamic> category) {
    final categoryId = category['category_id']?.toString();
    if (categoryId == null || categoryId.isEmpty) return;

    final name = category['name']?.toString() ?? 'Category';
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
          _buildTopBar(),
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
          const Text(
            'Analytics',
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
            Text('Error: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchSummary,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final totalAmount =
        (_summaryData?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalTransactions =
        (_summaryData?['total_transactions'] as num?)?.toInt() ?? 0;
    final categories = _summaryData?['categories'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(totalAmount, totalTransactions),
          const SizedBox(height: 28),
          const Text(
            'Expense Categories',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildPieChart(categories, totalAmount),
          const SizedBox(height: 20),
          _buildCategoryBreakdown(categories),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTotalCard(double totalAmount, int totalTransactions) {
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
            _selectedPeriod.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'RSD ${totalAmount.toStringAsFixed(2)}',
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
                  const Text(
                    'Average per day',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RSD ${(totalAmount / periodDays).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Column(
                children: [
                  const Text(
                    'Total Transactions',
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

  Widget _buildPieChart(List<dynamic> categories, double totalAmount) {
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

    return SizedBox(
      height: 280,
      child: Column(
        children: [
          SizedBox(
            height: 230,
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
                        'RSD ${totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total Spent',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ] else
                      Text(
                        'No Data',
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
          if (hasData)
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: categories.map((raw) {
                final cat = raw as Map<String, dynamic>;
                final name = cat['name']?.toString() ?? 'Unknown';
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
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<dynamic> categories) {
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No category data for selected filters.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }

    return Column(
      children: categories.asMap().entries.map((entry) {
        final index = entry.key;
        final cat = entry.value as Map<String, dynamic>;
        final name = cat['name']?.toString() ?? 'Category';
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
            onTap: () => _openCategoryDetails(cat),
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
                          'RSD ${amount.toStringAsFixed(2)} • $itemCount purchases',
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
}
