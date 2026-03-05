import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  
  List<dynamic> _items = [];
  List<dynamic> _categories = [];

  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime? _occurredAt;
  String _currency = 'RSD';
  
  final Map<String, TextEditingController> _itemDescControllers = {};
  final Map<String, TextEditingController> _itemAmountControllers = {};
  final Map<String, String?> _itemCategoryIds = {};

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    for (var c in _itemDescControllers.values) {
      c.dispose();
    }
    for (var c in _itemAmountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final txData = await ApiClient.getTransaction(widget.transactionId);
      final catsData = await ApiClient.listCategories();
      
      setState(() {
        _categories = catsData;
        _items = List.from(txData['items'] ?? []);
        
        _merchantController.text = txData['merchant_name'] ?? '';
        _amountController.text = txData['amount_total']?.toString() ?? '0.00';
        _currency = txData['currency'] ?? 'RSD';
        
        if (txData['occurred_at'] != null) {
          _occurredAt = DateTime.tryParse(txData['occurred_at']);
        }
        
        for (final item in _items) {
          final id = item['id'].toString();
          _itemDescControllers[id] = TextEditingController(text: item['description'] ?? '');
          _itemAmountControllers[id] = TextEditingController(text: item['amount']?.toString() ?? '0.00');
          _itemCategoryIds[id] = item['category_id']?.toString();
        }
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    setState(() => _isSaving = true);
    try {
      final payload = {
        'merchant_name': _merchantController.text,
        'amount_total': double.tryParse(_amountController.text) ?? 0.0,
        'currency': _currency,
      };
      
      if (_occurredAt != null) {
        payload['occurred_at'] = _occurredAt!.toIso8601String();
      }

      final updatedItems = [];
      for (final item in _items) {
        final id = item['id'].toString();
        updatedItems.add({
          'id': id,
          'description': _itemDescControllers[id]?.text ?? '',
          'amount': double.tryParse(_itemAmountControllers[id]?.text ?? '0.00') ?? 0.0,
          'category_id': _itemCategoryIds[id],
        });
      }
      payload['items'] = updatedItems;

      await ApiClient.updateTransaction(widget.transactionId, payload);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved Successfully')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _merchantController,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Merchant Name', hintStyle: TextStyle(color: Colors.white54)),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            IconButton(
              icon: const Icon(Icons.done, color: Colors.purpleAccent),
              onPressed: _saveTransaction,
            )
        ],
      ),
      body: Column(
        children: [
          _buildActionBadges(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _items.length + 1,
              itemBuilder: (context, index) {
                if (index == _items.length) return _buildAddItemButton();
                return _buildItemCard(_items[index], index);
              },
            ),
          ),
          _buildFixedFooter(),
        ],
      ),
    );
  }

  Widget _buildActionBadges() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildBadge(
              icon: Icons.calendar_today, 
              label: _occurredAt != null ? DateFormat('dd.MM.yyyy').format(_occurredAt!) : 'Set Date',
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _occurredAt ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null) setState(() => _occurredAt = date);
              },
            ),
            _buildBadge(icon: Icons.translate, label: 'Translate'),
            _buildBadge(icon: Icons.image_outlined, label: 'Photo'),
            _buildBadge(
              icon: Icons.currency_exchange, 
              label: _currency,
              onTap: () {
                // simple cycle for demo or a dialog
                setState(() => _currency = _currency == 'RSD' ? 'EUR' : 'RSD');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, int index) {
    final id = item['id'].toString();
    final nameController = _itemDescControllers[id];
    final amountController = _itemAmountControllers[id];
    final selectedCatId = _itemCategoryIds[id];
    
    // Find category info
    final category = _categories.firstWhere((c) => c['id'].toString() == selectedCatId, orElse: () => null);
    final catName = category != null ? category['name'] : 'Select Category';
    final catColor = category != null ? const Color(0xFFAB47BC) : Colors.grey; // Hardcoded purple like first screens, or from cat data

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'Item Name', hintStyle: TextStyle(color: Colors.white24)),
                ),
              ),
              const Icon(Icons.edit, color: Colors.white24, size: 14),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showCategoryPicker(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: catColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: catColor.withAlpha(100)),
                  ),
                  child: Text(catName, style: TextStyle(color: catColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const Spacer(),
              const Text('1 x ', style: TextStyle(color: Colors.white54, fontSize: 14)),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: amountController,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  onChanged: (v) {
                    _recalculateTotal();
                  },
                ),
              ),
              Text(' $_currency', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  void _recalculateTotal() {
    double total = 0;
    for (var c in _itemAmountControllers.values) {
      total += double.tryParse(c.text) ?? 0;
    }
    setState(() {
      _amountController.text = total.toStringAsFixed(2);
    });
  }

  Widget _buildAddItemButton() {
    return GestureDetector(
      onTap: () {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        setState(() {
          _items.add({'id': id, 'description': '', 'amount': 0.0});
          _itemDescControllers[id] = TextEditingController();
          _itemAmountControllers[id] = TextEditingController(text: '0.00');
          _itemCategoryIds[id] = null;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 32),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, style: BorderStyle.solid), // Dashed borders need a CustomPainter, use solid for now
        ),
        child: const Center(
          child: Text('+ Add item', style: TextStyle(color: Colors.white38, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildFixedFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Text('Total Amount:', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$_currency ${_amountController.text}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            // IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 18), onPressed: () {}),
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker(String itemId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index];
            return ListTile(
              title: Text(cat['name'], style: const TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _itemCategoryIds[itemId] = cat['id'].toString();
                });
                Navigator.pop(context);
              },
            );
          },
        );
      }
    );
  }
}

