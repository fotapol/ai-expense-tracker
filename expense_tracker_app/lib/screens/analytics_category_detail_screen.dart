import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'analytics_subcategory_items_screen.dart';

class AnalyticsCategoryDetailScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final String categoryCode;
  final DateTime? fromDate;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;
  final List<String> selectedLabelIds;

  const AnalyticsCategoryDetailScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryCode,
    required this.fromDate,
    required this.selectedCategoryIds,
    required this.selectedSubcategoryIds,
    required this.selectedLabelIds,
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
        labelIds: widget.selectedLabelIds.isNotEmpty
            ? widget.selectedLabelIds
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
          subcategoryName: localizeCategoryByCode(
            context,
            code: subcategory['code']?.toString(),
            fallbackName: subcategory['name']?.toString(),
          ),
          subcategoryCode: subcategory['code']?.toString() ?? '',
          fromDate: widget.fromDate,
          selectedCategoryIds: widget.selectedCategoryIds,
          selectedSubcategoryIds: widget.selectedSubcategoryIds,
          selectedLabelIds: widget.selectedLabelIds,
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
                  _error ?? context.tr('common_error'),
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
    final currency = (_data?['currency']?.toString() ?? 'EUR').toUpperCase();

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
                  _formatMoney(currency, totalAmount),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'analytics_subcategories_count',
                    params: {'count': subcategories.length.toString()},
                  ),
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('filters_subcategory'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (subcategories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                context.tr('analytics_no_subcategory_data'),
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ...subcategories.map((raw) {
            final sub = raw as Map<String, dynamic>;
            final subCode = sub['code']?.toString() ?? '';
            final subName = localizeCategoryByCode(
              context,
              code: subCode,
              fallbackName: sub['name']?.toString(),
            );
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
