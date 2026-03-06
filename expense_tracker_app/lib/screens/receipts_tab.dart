import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/period_filter.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'transaction_edit_screen.dart';

class ReceiptsTab extends StatefulWidget {
  const ReceiptsTab({super.key});

  @override
  State<ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends State<ReceiptsTab> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _transactions = [];
  String _preferredCurrency = 'EUR';
  String _selectedPeriod = PeriodFilter.last3Months;
  String _merchantSearch = '';
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];
  List<String> _selectedLabelIds = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, Map<String, dynamic>> _categoriesById = {};

  @override
  void initState() {
    super.initState();
    _loadPreferredCurrency();
    _loadCategories();
    _fetchTransactions();
  }

  Future<void> _loadPreferredCurrency() async {
    try {
      final me = await ApiClient.getMe();
      final currency = me['default_currency']?.toString().trim();
      if (!mounted || currency == null || currency.isEmpty) return;
      setState(() => _preferredCurrency = currency.toUpperCase());
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiClient.listCategories();
      if (!mounted) return;
      setState(() {
        _categoriesById = {
          for (final raw in categories)
            if ((raw as Map<String, dynamic>)['id'] != null)
              raw['id'].toString(): raw,
        };
      });
    } catch (_) {}
  }

  Map<String, dynamic>? _findCategoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return null;
    return _categoriesById[categoryId];
  }

  String? _categoryPathLabel(String? categoryId) {
    final category = _findCategoryById(categoryId);
    if (category == null) return null;
    final childName = category['name']?.toString();
    if (childName == null || childName.isEmpty) return null;
    final parentId = category['parent_id']?.toString();
    if (parentId == null || parentId.isEmpty) {
      return childName;
    }
    final parent = _findCategoryById(parentId);
    final parentName = parent?['name']?.toString();
    if (parentName == null || parentName.isEmpty) {
      return childName;
    }
    return '$parentName * $childName';
  }

  Color _parseHexColor(String? raw, Color fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;

    var hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    if (hex.length != 8) return fallback;

    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

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

  double _displayAmountOf(Map<String, dynamic> tx) {
    final raw = tx['display_amount_total'] ?? tx['amount_total'] ?? 0;
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _displayCurrencyOf(Map<String, dynamic> tx) {
    final hasConvertedValue = tx['display_amount_total'] != null;
    final raw = hasConvertedValue
        ? (tx['display_currency'] ?? tx['currency'] ?? _preferredCurrency)
        : (tx['currency'] ?? _preferredCurrency);
    return raw.toString().toUpperCase();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final startDate = PeriodFilter.getStartDate(_selectedPeriod);
      final searchText = _searchController.text.trim();
      final data = await ApiClient.listTransactions(
        fromDate: startDate,
        merchantNameSearch: searchText.isNotEmpty
            ? searchText
            : _merchantSearch.isNotEmpty
            ? _merchantSearch
            : null,
        categoryIds: _selectedCategoryIds.isNotEmpty
            ? _selectedCategoryIds
            : null,
        subcategoryIds: _selectedSubcategoryIds.isNotEmpty
            ? _selectedSubcategoryIds
            : null,
        labelIds: _selectedLabelIds.isNotEmpty ? _selectedLabelIds : null,
      );
      setState(() {
        _transactions = data;
        _isLoading = false;
      });
    } catch (e) {
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
      selectedLabelIds: _selectedLabelIds,
    );

    if (result != null) {
      setState(() {
        _selectedPeriod = result['period'] as String;
        _selectedCategoryIds = List<String>.from(result['category_ids'] ?? []);
        _selectedSubcategoryIds = List<String>.from(
          result['subcategory_ids'] ?? [],
        );
        _selectedLabelIds = List<String>.from(result['label_ids'] ?? []);
      });
      _fetchTransactions();
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final receiptId = tx['receipt_id'] as String?;
    if (receiptId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Receipt'),
        content: const Text(
          'This will permanently delete the receipt and all its items. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient.deleteReceipt(receiptId);
        _fetchTransactions();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Receipt deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          if (_selectedPeriod != PeriodFilter.last3Months ||
              _merchantSearch.isNotEmpty ||
              _selectedCategoryIds.isNotEmpty ||
              _selectedSubcategoryIds.isNotEmpty ||
              _selectedLabelIds.isNotEmpty)
            _buildActiveFilterChips(),
          Expanded(child: _buildTransactionList()),
          _buildBottomSummary(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by store...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: (_) => _fetchTransactions(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.tune),
            color: Theme.of(context).colorScheme.primary,
            onPressed: _openFilters,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withAlpha(80),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedPeriod,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (_merchantSearch.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  _merchantSearch,
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() => _merchantSearch = '');
                  _fetchTransactions();
                },
              ),
            ],
            if (_selectedCategoryIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  '${_selectedCategoryIds.length} categories',
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _selectedCategoryIds.clear();
                    _selectedSubcategoryIds.clear();
                  });
                  _fetchTransactions();
                },
              ),
            ],
            if (_selectedSubcategoryIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  '${_selectedSubcategoryIds.length} subcategories',
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() => _selectedSubcategoryIds.clear());
                  _fetchTransactions();
                },
              ),
            ],
            if (_selectedLabelIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  '${_selectedLabelIds.length} labels',
                  style: const TextStyle(fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() => _selectedLabelIds.clear());
                  _fetchTransactions();
                },
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

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
              onPressed: _fetchTransactions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No receipts found',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Group transactions by month
    final groupedTransactions = <String, List<dynamic>>{};
    for (var tx in _transactions) {
      final occurredAtStr = tx['occurred_at'] as String?;
      if (occurredAtStr == null) continue;
      final date = DateTime.tryParse(occurredAtStr);
      if (date == null) continue;
      final monthKey = DateFormat('MMMM yyyy').format(date);
      groupedTransactions.putIfAbsent(monthKey, () => []).add(tx);
    }

    return RefreshIndicator(
      onRefresh: _fetchTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedTransactions.length,
        itemBuilder: (context, index) {
          final monthKey = groupedTransactions.keys.elementAt(index);
          final txsForMonth = groupedTransactions[monthKey]!;
          double monthTotal = 0;
          String monthCurrency = _preferredCurrency;
          for (var tx in txsForMonth) {
            final txMap = tx as Map<String, dynamic>;
            monthTotal += _displayAmountOf(txMap);
            monthCurrency = _displayCurrencyOf(txMap);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      monthKey,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _formatMoney(monthCurrency, monthTotal),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              ...txsForMonth.map((tx) => _buildTransactionCard(tx)),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final storeName = tx['merchant_name'] ?? 'Unknown Store';
    final displayAmount = _displayAmountOf(tx);
    final displayCurrency = _displayCurrencyOf(tx);
    final sourceAmount =
        double.tryParse((tx['amount_total'] ?? '0').toString()) ?? 0;
    final sourceCurrency = (tx['currency'] ?? displayCurrency)
        .toString()
        .toUpperCase();
    final showOriginal =
        tx['display_amount_total'] != null &&
        (displayCurrency != sourceCurrency ||
            (displayAmount - sourceAmount).abs() > 0.00001);
    String formattedTime = '';
    final occurredAtStr = tx['occurred_at'] as String?;
    if (occurredAtStr != null) {
      final date = DateTime.tryParse(occurredAtStr);
      if (date != null) formattedTime = DateFormat('d MMM, HH:mm').format(date);
    }

    final txCategoryId = tx['category_id']?.toString();
    final txCategory = _findCategoryById(txCategoryId);
    final txCategoryNameRaw = tx['category_name']?.toString().trim();
    final txCategoryLabel =
        (txCategoryNameRaw != null && txCategoryNameRaw.isNotEmpty)
        ? txCategoryNameRaw
        : _categoryPathLabel(txCategoryId);
    final txCategoryCode = txCategory?['code']?.toString() ?? '';
    final iconColor = txCategory != null
        ? CategoryStyle.colorForCode(txCategoryCode)
        : Theme.of(context).colorScheme.primary;
    final iconData = txCategory != null
        ? CategoryStyle.iconForCode(txCategoryCode)
        : Icons.shopping_bag;

    final allLabelsRaw = tx['labels'];
    final allLabels = allLabelsRaw is List
        ? allLabelsRaw.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final pinnedLabels = allLabels
        .where((label) => label['is_pinned'] == true)
        .toList();
    final labelsToRender = (pinnedLabels.isNotEmpty ? pinnedLabels : allLabels)
        .take(3)
        .toList();
    final hasMetaRow =
        (txCategoryLabel != null && txCategoryLabel.isNotEmpty) ||
        labelsToRender.isNotEmpty;

    return Dismissible(
      key: Key(tx['id'] ?? ''),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteTransaction(tx);
        return false; // We handle deletion ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  TransactionEditScreen(transactionId: tx['id']),
            ),
          ).then((_) => _fetchTransactions());
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconData, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (formattedTime.isNotEmpty)
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    if (hasMetaRow) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (txCategoryLabel != null &&
                              txCategoryLabel.isNotEmpty)
                            _buildMetaChip(
                              label: txCategoryLabel,
                              icon: Icons.category_outlined,
                              color: iconColor,
                            ),
                          ...labelsToRender.map((label) {
                            final fallbackColor = Theme.of(
                              context,
                            ).colorScheme.primary;
                            final chipColor = _parseHexColor(
                              label['color']?.toString(),
                              fallbackColor,
                            );
                            final labelName = label['name']?.toString() ?? '';
                            if (labelName.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _buildMetaChip(
                              label: labelName,
                              icon: Icons.push_pin_outlined,
                              color: chipColor,
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatMoney(displayCurrency, displayAmount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (showOriginal)
                    Text(
                      _formatMoney(sourceCurrency, sourceAmount),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary() {
    double totalPeriodExpense = 0;
    String totalCurrency = _preferredCurrency;
    for (var tx in _transactions) {
      final txMap = tx as Map<String, dynamic>;
      totalPeriodExpense += _displayAmountOf(txMap);
      totalCurrency = _displayCurrencyOf(txMap);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total for period',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                _formatMoney(totalCurrency, totalPeriodExpense),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          Text(
            '${_transactions.length} receipts',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
