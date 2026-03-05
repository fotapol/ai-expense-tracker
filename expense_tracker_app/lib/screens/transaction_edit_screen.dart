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
  final Map<String, TextEditingController> _itemQtyControllers = {};
  final Map<String, TextEditingController> _itemUnitPriceControllers = {};
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
    for (var c in _itemQtyControllers.values) {
      c.dispose();
    }
    for (var c in _itemUnitPriceControllers.values) {
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
        _amountController.text = _formatNumberForInput(
          txData['amount_total'],
          decimals: 2,
          keepTrailingZeros: true,
        );
        if (_amountController.text.isEmpty) {
          _amountController.text = '0.00';
        }
        _currency = txData['currency'] ?? 'RSD';

        if (txData['occurred_at'] != null) {
          _occurredAt = DateTime.tryParse(txData['occurred_at']);
        }

        for (final item in _items) {
          final id = item['id'].toString();
          _itemDescControllers[id] = TextEditingController(
            text: item['description'] ?? '',
          );
          _itemAmountControllers[id] = TextEditingController(
            text: _formatNumberForInput(
              item['amount'],
              decimals: 2,
              keepTrailingZeros: true,
            ),
          );
          _itemQtyControllers[id] = TextEditingController(
            text: _formatNumberForInput(item['qty'], decimals: 2),
          );
          _itemUnitPriceControllers[id] = TextEditingController(
            text: _formatNumberForInput(
              item['unit_price'],
              decimals: 2,
              keepTrailingZeros: true,
            ),
          );
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
          'amount':
              double.tryParse(_itemAmountControllers[id]?.text ?? '0.00') ??
              0.0,
          'qty': _toDouble(_itemQtyControllers[id]?.text),
          'unit_price': _toDouble(_itemUnitPriceControllers[id]?.text),
          'unit': item['unit'],
          'category_id': _itemCategoryIds[id],
        });
      }
      payload['items'] = updatedItems;

      await ApiClient.updateTransaction(widget.transactionId, payload);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved Successfully')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = value.toString().replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  String _formatNumberForInput(
    dynamic value, {
    int decimals = 2,
    bool keepTrailingZeros = false,
  }) {
    final parsed = _toDouble(value);
    if (parsed == null) return '';
    final fixed = parsed.toStringAsFixed(decimals);
    if (keepTrailingZeros) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
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

  String _displayUnit(String? rawUnit, {String? description}) {
    final normalized = (rawUnit ?? '').trim().toUpperCase();
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

  void _recalculateItemAmount(String itemId) {
    final qty = _toDouble(_itemQtyControllers[itemId]?.text);
    final unitPrice = _toDouble(_itemUnitPriceControllers[itemId]?.text);
    if (qty != null && unitPrice != null) {
      final amount = qty * unitPrice;
      final amountController = _itemAmountControllers[itemId];
      if (amountController != null) {
        amountController.text = amount.toStringAsFixed(2);
        amountController.selection = TextSelection.fromPosition(
          TextPosition(offset: amountController.text.length),
        );
      }
    }
    _recalculateTotal();
  }

  Widget _buildFormulaNumberInput({
    required TextEditingController? controller,
    required String hint,
    required double width,
    required ValueChanged<String> onChanged,
    int decimals = 2,
    bool keepTrailingZeros = false,
  }) {
    return SizedBox(
      width: width,
      height: 28,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 5,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFAB47BC)),
          ),
        ),
        onChanged: onChanged,
        onSubmitted: (_) {
          if (controller == null) return;
          controller.text = _formatNumberForInput(
            controller.text,
            decimals: decimals,
            keepTrailingZeros: keepTrailingZeros,
          );
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
          onChanged(controller.text);
        },
      ),
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final itemId = item['id']?.toString() ?? '';
    final itemName = item['description']?.toString() ?? 'item';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "$itemName" from this receipt?'),
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

    if (confirmed != true) return;

    try {
      if (_isUuid(itemId)) {
        await ApiClient.deleteTransactionItem(widget.transactionId, itemId);
      }

      setState(() {
        _items.removeWhere((element) => element['id'].toString() == itemId);
        _itemDescControllers.remove(itemId)?.dispose();
        _itemAmountControllers.remove(itemId)?.dispose();
        _itemQtyControllers.remove(itemId)?.dispose();
        _itemUnitPriceControllers.remove(itemId)?.dispose();
        _itemCategoryIds.remove(itemId);
      });
      _recalculateTotal();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Item deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Merchant Name',
            hintStyle: TextStyle(color: Colors.white54),
          ),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.done, color: Colors.purpleAccent),
              onPressed: _saveTransaction,
            ),
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
    final occurred = _occurredAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildBadge(
              icon: Icons.calendar_today,
              label: occurred != null
                  ? DateFormat('dd.MM.yyyy').format(occurred)
                  : 'Set Date',
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _occurredAt ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date != null) {
                  final base = _occurredAt ?? DateTime.now();
                  setState(() {
                    _occurredAt = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      base.hour,
                      base.minute,
                      base.second,
                      base.millisecond,
                      base.microsecond,
                    );
                  });
                }
              },
            ),
            _buildBadge(
              icon: Icons.access_time,
              label: occurred != null
                  ? DateFormat('HH:mm').format(occurred)
                  : 'Set Time',
              onTap: () async {
                final base = _occurredAt ?? DateTime.now();
                final selected = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
                );
                if (selected != null) {
                  setState(() {
                    _occurredAt = DateTime(
                      base.year,
                      base.month,
                      base.day,
                      selected.hour,
                      selected.minute,
                      base.second,
                      base.millisecond,
                      base.microsecond,
                    );
                  });
                }
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

  Widget _buildBadge({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
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
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, int index) {
    final id = item['id'].toString();
    final nameController = _itemDescControllers[id];
    final amountController = _itemAmountControllers[id];
    final qtyController = _itemQtyControllers[id];
    final unitPriceController = _itemUnitPriceControllers[id];
    final selectedCatId = _itemCategoryIds[id];

    // Find category info
    final category = _categories.firstWhere(
      (c) => c['id'].toString() == selectedCatId,
      orElse: () => null,
    );
    final catName = category != null ? category['name'] : 'Select Category';
    final catColor = category != null
        ? const Color(0xFFAB47BC)
        : Colors.grey; // Hardcoded purple like first screens, or from cat data
    final unit = item['unit']?.toString().trim();
    final resolvedUnit = _displayUnit(
      unit,
      description:
          nameController?.text ?? item['description']?.toString() ?? '',
    );

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
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Item Name',
                    hintStyle: TextStyle(color: Colors.white24),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                splashRadius: 18,
                onPressed: () => _deleteItem(item),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFormulaNumberInput(
                controller: unitPriceController,
                hint: '0.00',
                width: 76,
                keepTrailingZeros: true,
                onChanged: (_) => _recalculateItemAmount(id),
              ),
              const SizedBox(width: 4),
              Text(
                '$_currency x',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              _buildFormulaNumberInput(
                controller: qtyController,
                hint: '1',
                width: 50,
                onChanged: (_) => _recalculateItemAmount(id),
              ),
              const SizedBox(width: 4),
              Text(
                '$resolvedUnit =',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_formatNumberForInput(amountController?.text, decimals: 2, keepTrailingZeros: true)} $_currency',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showCategoryPicker(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: catColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: catColor.withAlpha(100)),
                  ),
                  child: Text(
                    catName,
                    style: TextStyle(
                      color: catColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
          _items.add({'id': id, 'description': '', 'amount': 0.0, 'qty': 1.0});
          _itemDescControllers[id] = TextEditingController();
          _itemAmountControllers[id] = TextEditingController(text: '0.00');
          _itemQtyControllers[id] = TextEditingController(text: '1');
          _itemUnitPriceControllers[id] = TextEditingController(text: '0.00');
          _itemCategoryIds[id] = null;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 32),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white24,
            style: BorderStyle.solid,
          ), // Dashed borders need a CustomPainter, use solid for now
        ),
        child: const Center(
          child: Text(
            '+ Add item',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
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
            const Text(
              'Total Amount:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '$_currency ${_amountController.text}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index];
            return ListTile(
              title: Text(
                cat['name'],
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                setState(() {
                  _itemCategoryIds[itemId] = cat['id'].toString();
                });
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}
