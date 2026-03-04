import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/api_client.dart';
import '../core/period_filter.dart';
import '../widgets/filter_bottom_sheet.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summaryData;
  String _selectedFilter = PeriodFilter.last3Months;

  // Consistent color palette for categories
  static const List<Color> _categoryColors = [
    Color(0xFFFF7043), // Deep Orange
    Color(0xFFAB47BC), // Purple
    Color(0xFF29B6F6), // Light Blue
    Color(0xFFFFCA28), // Amber
    Color(0xFF66BB6A), // Green
    Color(0xFFEC407A), // Pink
    Color(0xFF8D6E63), // Brown
    Color(0xFF26A69A), // Teal
    Color(0xFF5C6BC0), // Indigo
    Color(0xFFEF5350), // Red
    Color(0xFF42A5F5), // Blue
    Color(0xFFFFA726), // Orange
  ];

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startDate = PeriodFilter.getStartDate(_selectedFilter);
      final data = await ApiClient.getTransactionsSummary(fromDate: startDate);
      setState(() {
        _summaryData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _getColor(int index) {
    return _categoryColors[index % _categoryColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          _buildFilterPill(),
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Text(
        'Analytics',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFilterPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(_selectedFilter, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _openFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('Filters', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _selectedFilter,
    );
    if (result != null) {
      setState(() => _selectedFilter = result['period'] as String);
      _fetchSummary();
    }
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
            )
          ],
        ),
      );
    }

    final totalAmount = (_summaryData?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalTransactions = (_summaryData?['total_transactions'] as num?)?.toInt() ?? 0;
    final categories = _summaryData?['categories'] as List<dynamic>? ?? [];

    if (totalAmount == 0 && categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text('No expenses data found',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalCard(totalAmount, totalTransactions),
          const SizedBox(height: 32),
          const Text(
            'Expense Categories',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          _buildPieChart(categories, totalAmount),
          const SizedBox(height: 32),
          _buildCategoryLegend(categories),
        ],
      ),
    );
  }

  Widget _buildTotalCard(double totalAmount, int totalTransactions) {
    // Calculate days in the selected period for the average
    int periodDays = 30;
    if (_selectedFilter == PeriodFilter.last3Months) periodDays = 90;
    if (_selectedFilter == PeriodFilter.thisYear) periodDays = DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays.clamp(1, 366);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4A148C),
            Color(0xFF311B92),
          ],
        ),
      ),
      child: Column(
        children: [
          Text(
            _selectedFilter.toUpperCase(),
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
          )
        ],
      ),
    );
  }

  Widget _buildPieChart(List<dynamic> categories, double totalAmount) {
    if (categories.isEmpty) return const SizedBox.shrink();

    List<PieChartSectionData> sections = [];
    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final amount = (cat['amount'] as num?)?.toDouble() ?? 0.0;
      final percentage = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      final color = _getColor(i);

      sections.add(
        PieChartSectionData(
          color: color,
          value: amount,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }

    return SizedBox(
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 70,
              sections: sections,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCategoryLegend(List<dynamic> categories) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: List.generate(categories.length, (index) {
        final cat = categories[index];
        // Use the API name directly instead of hardcoded switch
        final name = cat['name'] as String? ?? 'Unknown';
        final color = _getColor(index);
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
      }),
    );
  }
}
