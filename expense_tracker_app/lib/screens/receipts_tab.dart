import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/period_filter.dart';
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
  String _selectedFilter = PeriodFilter.last3Months;

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
      final startDate = PeriodFilter.getStartDate(_selectedFilter);
      final data = await ApiClient.listTransactions(fromDate: startDate);
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          _buildFilterPill(),
          Expanded(
            child: _buildTransactionList(),
          ),
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
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search by store or category...',
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.tune),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () {},
          ),
        ],
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
          _fetchTransactions();
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
              Text(_selectedFilter),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
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
              onPressed: _fetchTransactions,
              child: const Text('Retry'),
            )
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
            Text('No receipts found', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          ],
        ),
      );
    }

    // Group transactions by month for display
    final groupedTransactions = <String, List<dynamic>>{};
    for (var tx in _transactions) {
      final occurredAtStr = tx['occurred_at'] as String?;
      if (occurredAtStr == null) continue;
      
      final date = DateTime.tryParse(occurredAtStr);
      if (date == null) continue;

      final monthKey = DateFormat('MMMM yyyy').format(date); // e.g., "March 2025"
      groupedTransactions.putIfAbsent(monthKey, () => []).add(tx);
    }

    return RefreshIndicator(
      onRefresh: _fetchTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: groupedTransactions.length,
        itemBuilder: (context, index) {
          final monthKey = groupedTransactions.keys.elementAt(index);
          final transactionsForMonth = groupedTransactions[monthKey]!;
          
          double monthTotal = 0;
          for(var tx in transactionsForMonth) {
             monthTotal += double.tryParse((tx['total_amount'] ?? '0').toString()) ?? 0;
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
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'RSD ${monthTotal.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    ),
                  ],
                ),
              ),
              ...transactionsForMonth.map((tx) => _buildTransactionCard(tx)).toList(),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final storeName = tx['merchant_name'] ?? 'Unknown Store';
    final amount = double.tryParse((tx['total_amount'] ?? '0').toString()) ?? 0;
    
    // Format Date
    String formattedTime = '';
    final occurredAtStr = tx['occurred_at'] as String?;
    if (occurredAtStr != null) {
      final date = DateTime.tryParse(occurredAtStr);
      if (date != null) {
        // e.g., "3 Mar, 10:43"
        formattedTime = DateFormat('d MMM, HH:mm').format(date);
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TransactionEditScreen(transactionId: tx['id']),
          ),
        ).then((_) {
          // Refresh list when coming back just in case they edited it
          _fetchTransactions();
        });
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
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.shopping_bag, // Could be dynamic based on category later
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (formattedTime.isNotEmpty)
                    Text(
                      formattedTime,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                ],
              ),
            ),
            // Amount
            Text(
              'RSD ${amount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSummary() {
    double totalPeriodExpense = 0;
    for (var tx in _transactions) {
      totalPeriodExpense += double.tryParse((tx['total_amount'] ?? '0').toString()) ?? 0;
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
                'Expenses for the period',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'RSD ${totalPeriodExpense.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
          Icon(Icons.pie_chart, color: Theme.of(context).colorScheme.primary, size: 32),
        ],
      ),
    );
  }
}
