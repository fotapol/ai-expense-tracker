import 'package:flutter/material.dart';
import '../core/api_client.dart';

class TransactionEditScreen extends StatefulWidget {
  final String transactionId;

  const TransactionEditScreen({super.key, required this.transactionId});

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  
  Map<String, dynamic>? _transaction;
  List<dynamic> _items = [];

  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _dateController = TextEditingController();
  
  // A map of item IDs (or index) to their controllers for easy editing
  final Map<String, TextEditingController> _itemDescControllers = {};
  final Map<String, TextEditingController> _itemAmountControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchTransaction();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _dateController.dispose();
    for (var c in _itemDescControllers.values) {
      c.dispose();
    }
    for (var c in _itemAmountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchTransaction() async {
    try {
      final data = await ApiClient.getTransaction(widget.transactionId);
      setState(() {
        _transaction = data;
        _items = List.from(data['items'] ?? []);
        
        _merchantController.text = data['merchant_name'] ?? '';
        _amountController.text = data['amount_total']?.toString() ?? '0.00';
        
        if (data['occurred_at'] != null) {
          // Simplistic date format parsing: "2023-10-12T10:00:00Z" -> "2023-10-12"
          final dt = DateTime.tryParse(data['occurred_at']);
          _dateController.text = dt != null ? "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}" : data['occurred_at'];
        }
        
        for (final item in _items) {
          final id = item['id'];
          _itemDescControllers[id] = TextEditingController(text: item['description'] ?? '');
          _itemAmountControllers[id] = TextEditingController(text: item['amount']?.toString() ?? '0.00');
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTransaction() async {
    setState(() => _isSaving = true);
    try {
      // Build the updated payload
      final payload = {
        'merchant_name': _merchantController.text,
        'amount_total': double.tryParse(_amountController.text) ?? 0.0,
      };
      
      // Parse the date if possible
      if (_dateController.text.isNotEmpty) {
        final dt = DateTime.tryParse(_dateController.text);
        if (dt != null) {
          payload['occurred_at'] = dt.toIso8601String();
        }
      }

      // Rebuild items
      final updatedItems = [];
      for (final item in _items) {
        final id = item['id'];
        final desc = _itemDescControllers[id]?.text ?? item['description'];
        final amount = double.tryParse(_itemAmountControllers[id]?.text ?? '') ?? item['amount'];
        
        updatedItems.add({
          'id': id,
          'description': desc,
          'amount': amount,
        });
      }
      payload['items'] = updatedItems;

      await ApiClient.updateTransaction(widget.transactionId, payload);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction saved!')),
        );
        Navigator.pop(context); // Go back to Home/MainScreen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Transaction')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error loading transaction:\n$_error'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Extracted Data'),
        actions: [
          _isSaving
              ? const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
              : IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: _saveTransaction,
                  tooltip: 'Save',
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OVERVIEW', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: 'Merchant Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Total Amount',
                      prefixText: 'RSD ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'Date (YYYY-MM-DD)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('RECEIPT ITEMS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const Text('No items extracted.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            for (int i = 0; i < _items.length; i++) _buildItemEditor(_items[i], i + 1),
          ],
        ),
      ),
    );
  }

  Widget _buildItemEditor(Map<String, dynamic> item, int index) {
    final id = item['id'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 12.0),
              child: Text('$index.', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _itemDescControllers[id],
                decoration: const InputDecoration(labelText: 'Description', isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextField(
                controller: _itemAmountControllers[id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'Amount', isDense: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
