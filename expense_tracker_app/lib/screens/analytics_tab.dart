import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/api_client.dart';
import '../core/period_filter.dart';

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

  // Helper mapping a backend code to a rich color and icon label
  (Color, String) _getCategoryDesign(String code) {
    switch (code) {
      case 'FOOD':
        return (const Color(0xFFFF7043), 'Food'); // Deep Orange
      case 'CLOTHING':
        return (const Color(0xFFAB47BC), 'Clothing & Footwear'); // Purple 400
      case 'TRANSPORT':
        return (const Color(0xFF29B6F6), 'Transport'); // Light Blue
      case 'UTILITIES':
        return (const Color(0xFFFFCA28), 'Utilities'); // Amber
      case 'HEALTH':
        return (const Color(0xFF66BB6A), 'Health'); // Green
      case 'ENTERTAINMENT':
        return (const Color(0xFFEC407A), 'Entertainment'); // Pink
      case 'HOME':
        return (const Color(0xFF8D6E63), 'Home'); // Brown
      default:
        return (const Color(0xFF78909C), 'Other'); // Blue Grey
    }
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
      child: PopupMenuButton<String>(
        onSelected: (String value) {
          setState(() {
            _selectedFilter = value;
          });
          _fetchSummary();
        },
        itemBuilder: (context) {
          return PeriodFilter.values.map((filter) {
            return PopupMenuItem<String>(
              value: filter,
              child: Text(filter),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today, size: 14),
              const SizedBox(width: 8),
              Text(_selectedFilter),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16),
            ],
          ),
        ),
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
            )
          ],
        ),
      );
    }

    final totalAmount = (_summaryData?['total_amount'] as num?)?.toDouble() ?? 0.0;
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
          _buildTotalCard(totalAmount),
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

  Widget _buildTotalCard(double totalAmount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4A148C), // Deep purple
            Color(0xFF311B92), // Deeper purple
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
                    'RSD ${(totalAmount / 30).toStringAsFixed(2)}', // Rough estimate for now
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              const Column(
                children: [
                  Text(
                    'Total Transactions',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '--', // Would come from backend ideally
                    style: TextStyle(color: Colors.white, fontSize: 16),
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
    for (var cat in categories) {
      final code = cat['code'] as String? ?? 'OTHER';
      final amount = (cat['amount'] as num?)?.toDouble() ?? 0.0;
      final percentage = (cat['percentage'] as num?)?.toDouble() ?? 0.0;
      final (color, text) = _getCategoryDesign(code);

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
        )
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
      children: categories.map((cat) {
        final code = cat['code'] as String? ?? 'OTHER';
        final (color, name) = _getCategoryDesign(code);
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
    );
  }
}
