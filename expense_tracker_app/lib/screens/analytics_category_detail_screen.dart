import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import 'analytics_subcategory_items_screen.dart';

class AnalyticsCategoryDetailScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final String categoryCode;
  final DateTime? fromDate;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;

  const AnalyticsCategoryDetailScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryCode,
    required this.fromDate,
    required this.selectedCategoryIds,
    required this.selectedSubcategoryIds,
  });

  @override
  State<AnalyticsCategoryDetailScreen> createState() =>
      _AnalyticsCategoryDetailScreenState();
}

class _AnalyticsCategoryDetailScreenState
    extends State<AnalyticsCategoryDetailScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await ApiClient.getCategorySubcategorySummary(
        categoryId: widget.categoryId,
        fromDate: widget.fromDate,
        categoryIds: widget.selectedCategoryIds.isNotEmpty
            ? widget.selectedCategoryIds
            : null,
        subcategoryIds: widget.selectedSubcategoryIds.isNotEmpty
            ? widget.selectedSubcategoryIds
            : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
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

  void _openSubcategory(Map<String, dynamic> subcategory) {
    final subcategoryId = subcategory['subcategory_id']?.toString();
    if (subcategoryId == null || subcategoryId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalyticsSubcategoryItemsScreen(
          subcategoryId: subcategoryId,
          subcategoryName: subcategory['name']?.toString() ?? 'Subcategory',
          subcategoryCode: subcategory['code']?.toString() ?? '',
          fromDate: widget.fromDate,
          selectedCategoryIds: widget.selectedCategoryIds,
          selectedSubcategoryIds: widget.selectedSubcategoryIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = CategoryStyle.colorForCode(widget.categoryCode);
    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : _buildContent(categoryColor),
    );
  }

  Widget _buildContent(Color categoryColor) {
    final subcategories = _data?['subcategories'] as List<dynamic>? ?? [];
    final totalAmount = (_data?['total_amount'] as num?)?.toDouble() ?? 0.0;

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: categoryColor.withAlpha(35),
              border: Border.all(color: categoryColor.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.categoryName,
                  style: TextStyle(
                    color: categoryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'RSD ${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${subcategories.length} subcategories',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Subcategories',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (subcategories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'No subcategory data for current filters.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ...subcategories.map((raw) {
            final sub = raw as Map<String, dynamic>;
            final subName = sub['name']?.toString() ?? 'Subcategory';
            final subCode = sub['code']?.toString() ?? '';
            final amount = (sub['amount'] as num?)?.toDouble() ?? 0.0;
            final percentage = (sub['percentage'] as num?)?.toDouble() ?? 0.0;
            final itemCount = (sub['item_count'] as num?)?.toInt() ?? 0;
            final subColor = CategoryStyle.colorForCode(subCode);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withAlpha(180),
                borderRadius: BorderRadius.circular(14),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openSubcategory(sub),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: subColor.withAlpha(35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.account_tree,
                          size: 18,
                          color: subColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'RSD ${amount.toStringAsFixed(2)} - $itemCount purchases',
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Colors.grey.shade300,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade500,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
