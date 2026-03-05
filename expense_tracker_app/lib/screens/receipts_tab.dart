import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
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
  String _selectedPeriod = PeriodFilter.last3Months;
  String _merchantSearch = '';
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
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
    );

    if (result != null) {
      setState(() {
        _selectedPeriod = result['period'] as String;
        _selectedCategoryIds = List<String>.from(result['category_ids'] ?? []);
        _selectedSubcategoryIds = List<String>.from(
          result['subcategory_ids'] ?? [],
        );
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
              _selectedSubcategoryIds.isNotEmpty)
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
          for (var tx in txsForMonth) {
            monthTotal +=
                double.tryParse((tx['amount_total'] ?? '0').toString()) ?? 0;
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
                      'RSD ${monthTotal.toStringAsFixed(2)}',
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
    final amount = double.tryParse((tx['amount_total'] ?? '0').toString()) ?? 0;
    String formattedTime = '';
    final occurredAtStr = tx['occurred_at'] as String?;
    if (occurredAtStr != null) {
      final date = DateTime.tryParse(occurredAtStr);
      if (date != null) formattedTime = DateFormat('d MMM, HH:mm').format(date);
    }

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
                  color: Theme.of(context).colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.shopping_bag,
                  color: Theme.of(context).colorScheme.primary,
                ),
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
                  ],
                ),
              ),
              Text(
                'RSD ${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSummary() {
    double totalPeriodExpense = 0;
    for (var tx in _transactions) {
      totalPeriodExpense +=
          double.tryParse((tx['amount_total'] ?? '0').toString()) ?? 0;
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
                'RSD ${totalPeriodExpense.toStringAsFixed(2)}',
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
