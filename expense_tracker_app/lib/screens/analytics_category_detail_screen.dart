import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'analytics_subcategory_items_screen.dart';

class AnalyticsCategoryDetailScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final String categoryCode;
  final String? categoryColor;
  final DateTime? fromDate;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;
  final List<String> selectedLabelIds;

  const AnalyticsCategoryDetailScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryCode,
    this.categoryColor,
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
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
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(title: Text(widget.categoryName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error ?? context.tr('common_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ShellColors.softRed),
                ),
              ),
            )
          : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final subcategories = _data?['subcategories'] as List<dynamic>? ?? [];
    final totalAmount = (_data?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final currency = (_data?['currency']?.toString() ?? 'EUR').toUpperCase();
    final headerTone = ShellStyles.categoryTone(
      context,
      code: widget.categoryCode,
      name: widget.categoryName,
      rawHex: widget.categoryColor ?? _data?['category_color']?.toString(),
    );

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: ShellStyles.cardDecoration(context, radius: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShellStyles.sectionLabel(
                  context,
                  context.tr('analytics_tab_categories'),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.categoryName,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: headerTone.container,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: headerTone.border),
                  ),
                  child: Text(
                    'Category overview',
                    style: TextStyle(
                      color: headerTone.foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                  context.tr(
                    'analytics_subcategories_count',
                    params: {'count': subcategories.length.toString()},
                  ),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('filters_subcategory'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (subcategories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                context.tr('analytics_no_subcategory_data'),
                style: TextStyle(color: ShellStyles.textMuted(context)),
              ),
            ),
          ...subcategories.map((raw) {
            final sub = raw as Map<String, dynamic>;
            final subName = localizeCategoryByCode(
              context,
              code: sub['code']?.toString(),
              fallbackName: sub['name']?.toString(),
            );
            final tone = ShellStyles.categoryTone(
              context,
              code: sub['code']?.toString(),
              parentCode: widget.categoryCode,
              name: sub['name']?.toString(),
              rawHex: sub['color']?.toString(),
            );
            final amount = (sub['amount'] as num?)?.toDouble() ?? 0.0;
            final percentage = (sub['percentage'] as num?)?.toDouble() ?? 0.0;
            final itemCount = (sub['item_count'] as num?)?.toInt() ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: ShellStyles.cardDecoration(
                context,
                radius: 18,
                withShadow: false,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _openSubcategory(sub),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: ShellStyles.semanticBadgeDecoration(
                          context,
                          tone: tone,
                        ),
                        child: Icon(
                          Icons.account_tree_outlined,
                          size: 18,
                          color: tone.foreground,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subName,
                              style: TextStyle(
                                color: ShellStyles.textPrimary(context),
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
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
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontWeight: FontWeight.w700,
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
          }),
        ],
      ),
    );
  }
}
