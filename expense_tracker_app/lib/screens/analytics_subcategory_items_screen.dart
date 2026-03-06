import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import '../l10n/app_localizations.dart';

class AnalyticsSubcategoryItemsScreen extends StatefulWidget {
  final String subcategoryId;
  final String subcategoryName;
  final String subcategoryCode;
  final DateTime? fromDate;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;
  final List<String> selectedLabelIds;

  const AnalyticsSubcategoryItemsScreen({
    super.key,
    required this.subcategoryId,
    required this.subcategoryName,
    required this.subcategoryCode,
    required this.fromDate,
    required this.selectedCategoryIds,
    required this.selectedSubcategoryIds,
    required this.selectedLabelIds,
  });

  @override
  State<AnalyticsSubcategoryItemsScreen> createState() =>
      _AnalyticsSubcategoryItemsScreenState();
}

class _AnalyticsSubcategoryItemsScreenState
    extends State<AnalyticsSubcategoryItemsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  String _currencySymbol(String code) {
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
    if (symbol.trim().length == 1 || symbol == 'RSD ') {
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
      final data = await ApiClient.getSubcategoryItemsSummary(
        subcategoryId: widget.subcategoryId,
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

  String _formatQty(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _inferUnitFromDescription(String description) {
    final upper = description.toUpperCase();
    if (RegExp(r'\bKG\b|\bKGS\b').hasMatch(upper)) return 'kg';
    if (RegExp(r'\bG\b').hasMatch(upper)) return 'kg';
    if (RegExp(r'\bML\b').hasMatch(upper)) return 'l';
    if (RegExp(r'\bL\b|\bLTR\b|\bLITAR\b|\bLITER\b').hasMatch(upper)) {
      return 'l';
    }
    return 'pc';
  }

  String _displayUnit(String? unit, {String? description}) {
    final normalized = (unit ?? '').trim().toUpperCase();
    switch (normalized) {
      case 'KG':
      case 'KGS':
        return 'kg';
      case 'G':
        return 'kg';
      case 'L':
      case 'LT':
      case 'LITER':
      case 'LITAR':
        return 'l';
      case 'ML':
        return 'l';
      case 'KOM':
      case 'PCS':
      case 'PC':
      case 'UNIT':
      case 'UN':
        return 'pc';
      default:
        if (normalized.isEmpty) {
          return _inferUnitFromDescription(description ?? '');
        }
        if (RegExp(r'\bKG\b|\bKGS\b|\bG\b').hasMatch(normalized)) return 'kg';
        if (RegExp(
          r'\bL\b|\bLT\b|\bLITER\b|\bLITAR\b|\bML\b',
        ).hasMatch(normalized)) {
          return 'l';
        }
        return 'pc';
    }
  }

  String _buildDetailsLine({
    required int occurrences,
    required double? totalQty,
    required String? unit,
    required String description,
  }) {
    final timesText = occurrences == 1
        ? context.tr('analytics_bought_once')
        : context.tr(
            'analytics_bought_times',
            params: {'count': occurrences.toString()},
          );
    if (totalQty == null) return timesText;

    final qtyText = context.tr(
      'analytics_total_quantity',
      params: {
        'qty': _formatQty(totalQty),
        'unit': _displayUnit(unit, description: description),
      },
    );
    return '$timesText - $qtyText';
  }

  @override
  Widget build(BuildContext context) {
    final accent = CategoryStyle.colorForCode(widget.subcategoryCode);
    return Scaffold(
      appBar: AppBar(title: Text(widget.subcategoryName)),
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
          : _buildContent(accent),
    );
  }

  Widget _buildContent(Color accent) {
    final totalAmount = (_data?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalItems = (_data?['total_items'] as num?)?.toInt() ?? 0;
    final items = _data?['items'] as List<dynamic>? ?? [];
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
              color: accent.withAlpha(35),
              border: Border.all(color: accent.withAlpha(90)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.subcategoryName,
                  style: TextStyle(
                    color: accent,
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
                    'analytics_purchases_count',
                    params: {'count': totalItems.toString()},
                  ),
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('analytics_purchased_items'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                context.tr('analytics_no_items_for_subcategory'),
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ...items.map((raw) {
            final item = raw as Map<String, dynamic>;
            final name =
                item['description']?.toString() ??
                context.tr('analytics_unknown_item');
            final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
            final occurrences = (item['occurrences'] as num?)?.toInt() ?? 0;
            final totalQty = (item['total_qty'] as num?)?.toDouble();
            final unit = item['unit']?.toString();
            final details = _buildDetailsLine(
              occurrences: occurrences,
              totalQty: totalQty,
              unit: unit,
              description: name,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withAlpha(180),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shopping_bag, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 128,
                    child: Text(
                      _formatMoney(currency, amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
