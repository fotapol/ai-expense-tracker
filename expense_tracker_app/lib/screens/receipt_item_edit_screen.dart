import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';

class ReceiptItemEditResult {
  const ReceiptItemEditResult({this.item, this.deleted = false});

  const ReceiptItemEditResult.deleted() : item = null, deleted = true;

  final Map<String, dynamic>? item;
  final bool deleted;
}

class ReceiptItemEditScreen extends StatefulWidget {
  const ReceiptItemEditScreen({
    super.key,
    required this.initialItem,
    required this.categories,
    required this.sourceCurrency,
    required this.displayCurrency,
    required this.displayRate,
    required this.canEdit,
    this.isNew = false,
  });

  final Map<String, dynamic> initialItem;
  final List<dynamic> categories;
  final String sourceCurrency;
  final String displayCurrency;
  final double displayRate;
  final bool canEdit;
  final bool isNew;

  @override
  State<ReceiptItemEditScreen> createState() => _ReceiptItemEditScreenState();
}

class _ReceiptItemEditScreenState extends State<ReceiptItemEditScreen> {
  static const Color _bgColor = Color(0xFFF6F6F7);
  static const Color _surfaceColor = Colors.white;
  static const Color _surfaceAltColor = Color(0xFFF1F1F3);
  static const Color _strokeColor = Color(0xFFE3E3E7);
  static const Color _textColor = Color(0xFF17171A);
  static const Color _mutedColor = Color(0xFF7F7F86);
  static const Color _accentColor = Color(0xFF17171A);
  static const Color _warningColor = Color(0xFF5D5D64);

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _qtyController;
  late final TextEditingController _unitPriceController;

  late Map<String, dynamic> _item;
  String? _selectedCategoryId;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _item = Map<String, dynamic>.from(widget.initialItem);
    _selectedCategoryId = _item['category_id']?.toString();
    _unit = _displayUnit(
      _item['unit']?.toString(),
      description: _item['description']?.toString(),
      qty: _toDouble(_item['qty']),
    );
    _nameController = TextEditingController(
      text: _item['description']?.toString() ?? '',
    );
    _amountController = TextEditingController(
      text: _formatNumberForInput(
        _item['amount'],
        decimals: 2,
        keepTrailingZeros: true,
      ),
    );
    _qtyController = TextEditingController(
      text: _formatNumberForInput(_item['qty'], decimals: 3),
    );
    _unitPriceController = TextEditingController(
      text: _formatNumberForInput(_item['unit_price'], decimals: 3),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _qtyController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = value.toString().replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

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

  String _displayUnit(String? rawUnit, {String? description, double? qty}) {
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
          final inferred = _inferUnitFromDescription(description ?? '');
          if (inferred == 'pc' && qty != null && (qty % 1) != 0) {
            return 'kg';
          }
          return inferred;
        }
        if (RegExp(r'\bKG\b|\bKGS\b|\bG\b').hasMatch(normalized)) return 'kg';
        if (RegExp(
          r'\bL\b|\bLT\b|\bLITER\b|\bLITAR\b|\bML\b',
        ).hasMatch(normalized)) {
          return 'l';
        }
        if (qty != null && (qty % 1) != 0) return 'kg';
        return 'pc';
    }
  }

  String _unitLabel(String unit) => unit == 'pc' ? 'pcs' : unit;

  String _formatMoney(String currency, double amount) {
    return '${CurrencyDisplay.labelForCode(currency)} ${amount.toStringAsFixed(2)}';
  }

  double _toDisplayAmount(double sourceAmount) {
    return _round2(sourceAmount * widget.displayRate);
  }

  Map<String, double>? _lineMismatch() {
    final qty = _toDouble(_qtyController.text);
    final unitPrice = _toDouble(_unitPriceController.text);
    final amount = _toDouble(_amountController.text);
    final discount = _toDouble(_item['discount_amount']) ?? 0.0;
    if (qty == null || unitPrice == null || amount == null) return null;
    final expected = _round2((qty * unitPrice) - discount);
    final actual = _round2(amount);
    if (expected == actual) return null;
    return <String, double>{'expected': expected, 'actual': actual};
  }

  Map<String, dynamic>? _findCategoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return null;
    for (final raw in widget.categories) {
      final category = raw as Map<String, dynamic>;
      if (category['id']?.toString() == categoryId) {
        return category;
      }
    }
    return null;
  }

  bool _isItemScopeCategory(Map<String, dynamic> category) {
    final scope = (category['scope']?.toString() ?? '').trim().toLowerCase();
    if (scope.isEmpty) return true;
    return scope == 'item';
  }

  String _localizedCategoryName(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  List<Map<String, dynamic>> _topLevelItemCategories() {
    final topLevel = widget.categories.whereType<Map<String, dynamic>>().where((
      category,
    ) {
      final parentId = category['parent_id']?.toString();
      return _isItemScopeCategory(category) &&
          (parentId == null || parentId.isEmpty);
    }).toList();
    topLevel.sort(
      (a, b) => _localizedCategoryName(
        a,
      ).toLowerCase().compareTo(_localizedCategoryName(b).toLowerCase()),
    );
    return topLevel;
  }

  List<Map<String, dynamic>> _itemSubcategoriesForParent(String parentId) {
    final subcategories = widget.categories
        .whereType<Map<String, dynamic>>()
        .where((category) {
          final categoryParentId = category['parent_id']?.toString();
          return _isItemScopeCategory(category) && categoryParentId == parentId;
        })
        .toList();
    subcategories.sort(
      (a, b) => _localizedCategoryName(
        a,
      ).toLowerCase().compareTo(_localizedCategoryName(b).toLowerCase()),
    );
    return subcategories;
  }

  List<String> _itemCategoryTags(String? categoryId) {
    final category = _findCategoryById(categoryId);
    if (category == null) return [context.tr('transaction_select_category')];

    final childName = localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    ).trim();
    if (childName.isEmpty) {
      return [context.tr('transaction_select_category')];
    }

    final parentId = category['parent_id']?.toString();
    if (parentId == null || parentId.isEmpty) {
      return [childName];
    }

    final parent = _findCategoryById(parentId);
    final parentName = localizeCategoryByCode(
      context,
      code: parent?['code']?.toString(),
      fallbackName: parent?['name']?.toString(),
    ).trim();
    if (parentName.isEmpty) {
      return [childName];
    }

    return [parentName, childName];
  }

  Future<String?> _pickParentCategory(String? selectedParentId) {
    final topLevel = _topLevelItemCategories();
    if (topLevel.isEmpty) {
      return Future.value(null);
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String? currentSelectedParentId = selectedParentId;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          context.tr('filters_category'),
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            context.tr('common_cancel'),
                            style: const TextStyle(color: _mutedColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      shrinkWrap: true,
                      itemCount: topLevel.length,
                      itemBuilder: (context, index) {
                        final category = topLevel[index];
                        final categoryId = category['id']?.toString() ?? '';
                        final selected = categoryId == currentSelectedParentId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _localizedCategoryName(category),
                            style: TextStyle(
                              color: selected
                                  ? _accentColor
                                  : _textColor,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          trailing: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected
                                ? _accentColor
                                : _mutedColor,
                          ),
                          onTap: () {
                            setModalState(
                              () => currentSelectedParentId = categoryId,
                            );
                            Navigator.pop(context, categoryId);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _pickSubcategory({
    required String parentCategoryId,
    String? selectedSubcategoryId,
  }) {
    final subcategories = _itemSubcategoriesForParent(parentCategoryId);
    if (subcategories.isEmpty) {
      return Future.value(null);
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: subcategories.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      context.tr('filters_subcategory'),
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        context.tr('common_cancel'),
                        style: const TextStyle(color: _mutedColor),
                      ),
                    ),
                  ],
                ),
              );
            }

            final category = subcategories[index - 1];
            final categoryId = category['id']?.toString() ?? '';
            final selected = categoryId == selectedSubcategoryId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _localizedCategoryName(category),
                style: TextStyle(
                  color: selected
                      ? _accentColor
                      : _textColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              trailing: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? _accentColor
                    : _mutedColor,
              ),
              onTap: () => Navigator.pop(context, categoryId),
            );
          },
        );
      },
    );
  }

  Future<void> _showCategoryPicker() async {
    final selectedCategory = _findCategoryById(_selectedCategoryId);
    var selectedParentId = selectedCategory?['parent_id']?.toString();
    if (selectedParentId == null || selectedParentId.isEmpty) {
      selectedParentId = selectedCategory == null
          ? null
          : selectedCategory['id']?.toString();
    }

    final parentCategoryId = await _pickParentCategory(selectedParentId);
    if (!mounted || parentCategoryId == null || parentCategoryId.isEmpty) {
      return;
    }

    final selectedSubcategoryId = await _pickSubcategory(
      parentCategoryId: parentCategoryId,
      selectedSubcategoryId: _selectedCategoryId,
    );
    if (!mounted) return;

    setState(() {
      _selectedCategoryId =
          (selectedSubcategoryId == null || selectedSubcategoryId.isEmpty)
          ? parentCategoryId
          : selectedSubcategoryId;
    });
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _surfaceColor,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _strokeColor),
    );
  }

  void _save() {
    final next = Map<String, dynamic>.from(_item);
    final originalDescription = (_item['description']?.toString() ?? '').trim();
    final nextDescription = _nameController.text.trim();

    next['description'] = nextDescription;
    next['amount'] = _toDouble(_amountController.text) ?? 0.0;
    next['qty'] = _toDouble(_qtyController.text);
    next['unit_price'] = _toDouble(_unitPriceController.text);
    next['unit'] = _unit;
    next['category_id'] = _selectedCategoryId;

    if (nextDescription.toLowerCase() != originalDescription.toLowerCase()) {
      next['translated_description'] = null;
      next['translation_language'] = null;
      next['translation_source_language'] = null;
    }

    Navigator.pop(context, ReceiptItemEditResult(item: next));
  }

  InputDecoration _fieldDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: _mutedColor),
      filled: true,
      fillColor: _surfaceAltColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _strokeColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _strokeColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _textColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _strokeColor),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _mutedColor,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _darkTextField({
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      readOnly: !widget.canEdit,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(
        color: _textColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      decoration: _fieldDecoration(hintText: hintText),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: _surfaceAltColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _strokeColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _mutedColor,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevronDown,
              size: 18,
              color: onTap == null ? _mutedColor : _textColor,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final translatedName = (_item['translated_description']?.toString() ?? '')
        .trim();
    final currentName = _nameController.text.trim();
    final hasTranslatedName =
        translatedName.isNotEmpty &&
        translatedName.toLowerCase() != currentName.toLowerCase();
    final sourceAmount = _toDouble(_amountController.text) ?? 0;
    final displayAmount = _toDisplayAmount(sourceAmount);
    final mismatch = _lineMismatch();
    final categoryTags = _itemCategoryTags(_selectedCategoryId);
    final categoryValue = categoryTags.join(' | ');
    final currentCategory = _findCategoryById(_selectedCategoryId);
    final parentId = currentCategory?['parent_id']?.toString();
    final topLevelCategory = parentId == null || parentId.isEmpty
        ? currentCategory
        : _findCategoryById(parentId);
    final subcategoryValue = parentId == null || parentId.isEmpty
        ? 'Select subcategory'
        : _localizedCategoryName(currentCategory!);

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: _mutedColor, fontSize: 16),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.isNew ? 'New Item' : 'Edit Item',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.canEdit ? _save : null,
                    child: Text(
                      context.tr('common_save'),
                      style: TextStyle(
                        color: widget.canEdit ? _accentColor : _mutedColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('ITEM NAME, QUANTITY'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _darkTextField(
                              controller: _nameController,
                              hintText: context.tr('transaction_item_name'),
                            ),
                            if (hasTranslatedName) ...[
                              const SizedBox(height: 10),
                              Text(
                                translatedName,
                                style: const TextStyle(
                                  color: _mutedColor,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _darkTextField(
                                    controller: _qtyController,
                                    hintText: '1',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _surfaceAltColor,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(color: _strokeColor),
                                      ),
                                      child: DropdownButton<String>(
                                        value: _unit,
                                        isExpanded: true,
                                        dropdownColor: _surfaceColor,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: _textColor,
                                        ),
                                        style: const TextStyle(
                                          color: _textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        items: const ['pc', 'kg', 'l']
                                            .map(
                                              (value) => DropdownMenuItem(
                                                value: value,
                                                child: Text(_unitLabel(value)),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: !widget.canEdit
                                            ? null
                                            : (value) {
                                                if (value == null) return;
                                                setState(() => _unit = value);
                                              },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('PRICE'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _darkTextField(
                              controller: _amountController,
                              hintText: '0.00',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.displayCurrency.toUpperCase() ==
                                      widget.sourceCurrency.toUpperCase()
                                  ? 'Matches the receipt currency.'
                                  : 'Converted: ${_formatMoney(widget.displayCurrency, displayAmount)}',
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _darkTextField(
                              controller: _unitPriceController,
                              hintText: '0.000',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Unit price in ${widget.sourceCurrency.toUpperCase()} per ${_unitLabel(_unit)}',
                              style: const TextStyle(
                                color: _mutedColor,
                                fontSize: 13,
                              ),
                            ),
                            if (mismatch != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                context.tr(
                                  'transaction_line_mismatch',
                                  params: {
                                    'expected': _formatMoney(
                                      widget.sourceCurrency,
                                      mismatch['expected'] ?? 0,
                                    ),
                                    'actual': _formatMoney(
                                      widget.sourceCurrency,
                                      mismatch['actual'] ?? 0,
                                    ),
                                  },
                                ),
                                style: const TextStyle(
                                  color: _warningColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('CATEGORY, SUBCATEGORY'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: _cardDecoration(),
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _pickerField(
                              label: 'Category',
                              value: topLevelCategory == null
                                  ? context.tr('transaction_select_category')
                                  : _localizedCategoryName(topLevelCategory),
                              onTap: widget.canEdit ? _showCategoryPicker : null,
                            ),
                            const SizedBox(height: 12),
                            _pickerField(
                              label: 'Subcategory',
                              value: parentId == null || parentId.isEmpty
                                  ? categoryValue
                                  : subcategoryValue,
                              onTap: widget.canEdit ? _showCategoryPicker : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
