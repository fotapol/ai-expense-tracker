import 'dart:async';

import 'package:flutter/material.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/item_translation_service.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

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
  List<dynamic> _labels = [];
  Set<String> _selectedLabelIds = {};
  List<dynamic> _serverWarnings = [];
  bool _hasLocalEdits = false;
  bool _isTranslatingItems = false;

  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime? _occurredAt;
  String _currency = 'RSD';
  String _displayCurrency = 'RSD';
  double _displayRate = 1.0;
  String _appLanguage = '';
  String _effectiveItemsLanguage = '';

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
    unawaited(ItemTranslationService.instance.flushPending());
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
      final appLanguage = _resolveAppLanguage();
      Map<String, dynamic>? meData;
      try {
        meData = await ApiClient.getMe();
      } catch (_) {
        meData = null;
      }
      final preferredItemsLanguage = _normalizeLanguageCode(
        meData?['items_language']?.toString(),
      );

      final txFuture = ApiClient.getTransaction(
        widget.transactionId,
        itemLanguage: preferredItemsLanguage.isNotEmpty
            ? preferredItemsLanguage
            : null,
        appLanguage: appLanguage.isNotEmpty ? appLanguage : null,
      );
      final catsFuture = ApiClient.listCategories();
      final labelsFuture = ApiClient.listLabels();

      final txData = await txFuture;
      final catsData = await catsFuture;
      final labelsData = await labelsFuture;
      final effectiveItemsLanguage = preferredItemsLanguage.isNotEmpty
          ? preferredItemsLanguage
          : appLanguage;

      for (final c in _itemDescControllers.values) {
        c.dispose();
      }
      for (final c in _itemAmountControllers.values) {
        c.dispose();
      }
      for (final c in _itemQtyControllers.values) {
        c.dispose();
      }
      for (final c in _itemUnitPriceControllers.values) {
        c.dispose();
      }
      _itemDescControllers.clear();
      _itemAmountControllers.clear();
      _itemQtyControllers.clear();
      _itemUnitPriceControllers.clear();
      _itemCategoryIds.clear();

      setState(() {
        _hasLocalEdits = false;
        _categories = catsData;
        _labels = labelsData;
        _appLanguage = appLanguage;
        _effectiveItemsLanguage = effectiveItemsLanguage;
        _items = List.from(txData['items'] ?? []);
        _selectedLabelIds = Set<String>.from(
          (txData['labels'] as List<dynamic>? ?? const [])
              .map((label) => label['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty),
        );
        _serverWarnings = List<dynamic>.from(
          txData['extraction_warnings'] as List<dynamic>? ?? const [],
        );

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
        final sourceTotal = _toDouble(txData['amount_total']);
        final displayTotal = _toDouble(txData['display_amount_total']);
        _displayCurrency = displayTotal != null
            ? (txData['display_currency'] ?? _currency).toString()
            : _currency;
        if (_displayCurrency.toUpperCase() == _currency.toUpperCase()) {
          _displayRate = 1.0;
        } else if (sourceTotal != null &&
            sourceTotal != 0 &&
            displayTotal != null) {
          _displayRate = displayTotal / sourceTotal;
        } else {
          _displayRate = 1.0;
        }

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
            text: _formatNumberForInput(item['qty'], decimals: 3),
          );
          _itemUnitPriceControllers[id] = TextEditingController(
            text: _formatNumberForInput(
              item['unit_price'],
              decimals: 3,
            ),
          );
          _itemCategoryIds[id] = item['category_id']?.toString();
        }

        _isLoading = false;
      });

      if (effectiveItemsLanguage.isNotEmpty) {
        unawaited(
          _translateMissingTransactionItems(
            targetLanguage: effectiveItemsLanguage,
          ),
        );
      }
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
          if (_isUuid(id)) 'id': id,
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

      await ApiClient.updateTransaction(
        widget.transactionId,
        payload,
        itemLanguage: _effectiveItemsLanguage.isNotEmpty
            ? _effectiveItemsLanguage
            : null,
        appLanguage: _appLanguage.isNotEmpty ? _appLanguage : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('transaction_saved_successfully'))),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'common_error_with_message',
                params: {'message': e.toString()},
              ),
            ),
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

  String _normalizeLanguageCode(String? raw) {
    return ItemTranslationService.instance.normalizeLanguageCode(raw);
  }

  String _normalizeText(String? raw) {
    return ItemTranslationService.instance.normalizeSourceText(raw ?? '');
  }

  String _resolveAppLanguage() {
    final fromLocale = _normalizeLanguageCode(
      localeProvider.locale.languageCode,
    );
    if (fromLocale.isNotEmpty) {
      return fromLocale;
    }
    return _normalizeLanguageCode(
      WidgetsBinding.instance.platformDispatcher.locale.languageCode,
    );
  }

  Future<void> _translateMissingTransactionItems({
    required String targetLanguage,
    bool forceRefresh = false,
  }) async {
    if (targetLanguage.isEmpty || _isTranslatingItems) return;

    setState(() => _isTranslatingItems = true);
    try {
      for (final raw in _items) {
        final item = raw as Map<String, dynamic>;
        final itemId = item['id']?.toString();
        if (itemId == null || itemId.isEmpty) continue;

        final description = _normalizeText(
          _itemDescControllers[itemId]?.text ?? item['description']?.toString(),
        );
        if (description.isEmpty) continue;

        final existingTranslation = _normalizeText(
          item['translated_description']?.toString(),
        );
        if (!forceRefresh && existingTranslation.isNotEmpty) continue;

        var sourceLanguage = _normalizeLanguageCode(
          item['description_lang']?.toString(),
        );
        if (sourceLanguage.isEmpty) {
          sourceLanguage = _normalizeLanguageCode(
            item['translation_source_language']?.toString(),
          );
        }
        final result = await ItemTranslationService.instance.translate(
          sourceText: description,
          sourceLanguage: sourceLanguage.isNotEmpty ? sourceLanguage : null,
          targetLanguage: targetLanguage,
          forceRefresh: forceRefresh,
        );
        if (result == null || !mounted) continue;

        final currentDescription = _normalizeText(
          _itemDescControllers[itemId]?.text,
        );
        if (currentDescription != description) continue;

        setState(() {
          item['translated_description'] = result.translatedText;
          item['translation_language'] = result.targetLanguage;
          item['translation_source_language'] = result.sourceLanguage;
          if ((item['description_lang']?.toString().trim().isEmpty ?? true)) {
            item['description_lang'] = result.sourceLanguage;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTranslatingItems = false);
      }
    }
  }

  Future<void> _forceRetranslateItems() async {
    if (_effectiveItemsLanguage.isEmpty || _isTranslatingItems) return;
    await _translateMissingTransactionItems(
      targetLanguage: _effectiveItemsLanguage,
      forceRefresh: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('transaction_translate'))),
    );
    unawaited(ItemTranslationService.instance.flushPending());
  }

  void _openReceiptCurrencyPicker() {
    showCurrencyPicker(
      context: context,
      showSearchField: true,
      showFlag: false,
      favorite: [_currency.toUpperCase()],
      onSelect: (currency) {
        final nextCode = currency.code.toUpperCase();
        if (nextCode == _currency.toUpperCase()) return;
        setState(() {
          _hasLocalEdits = true;
          _currency = nextCode;
          // Keep edit mode amounts coherent in source currency until next backend refresh.
          _displayCurrency = _currency;
          _displayRate = 1.0;
        });
      },
    );
  }

  Map<String, dynamic>? _findCategoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return null;
    for (final raw in _categories) {
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
    final topLevel = _categories
        .whereType<Map<String, dynamic>>()
        .where((category) {
          final parentId = category['parent_id']?.toString();
          return _isItemScopeCategory(category) &&
              (parentId == null || parentId.isEmpty);
        })
        .toList();
    topLevel.sort(
      (a, b) => _localizedCategoryName(
        a,
      ).toLowerCase().compareTo(_localizedCategoryName(b).toLowerCase()),
    );
    return topLevel;
  }

  List<Map<String, dynamic>> _itemSubcategoriesForParent(String parentId) {
    final subcategories = _categories
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

  double _round2(double value) => double.parse(value.toStringAsFixed(2));

  double _toDisplayAmount(double sourceAmount) {
    return _round2(sourceAmount * _displayRate);
  }

  Map<String, Map<String, double>> _computeLineMismatches() {
    final mismatches = <String, Map<String, double>>{};
    for (final item in _items) {
      final itemId = item['id'].toString();
      final qty = _toDouble(_itemQtyControllers[itemId]?.text);
      final unitPrice = _toDouble(_itemUnitPriceControllers[itemId]?.text);
      final amount = _toDouble(_itemAmountControllers[itemId]?.text);
      final discount = _toDouble(item['discount_amount']) ?? 0.0;
      if (qty == null || unitPrice == null || amount == null) continue;
      final expected = _round2((qty * unitPrice) - discount);
      final actual = _round2(amount);
      if (expected != actual) {
        mismatches[itemId] = {
          'expected': expected,
          'actual': actual,
          'difference': _round2(actual - expected),
        };
      }
    }
    return mismatches;
  }

  Map<String, double>? _computeTotalMismatch() {
    final txTotal = _toDouble(_amountController.text);
    if (txTotal == null) return null;

    double sumItems = 0;
    for (final controller in _itemAmountControllers.values) {
      sumItems += _toDouble(controller.text) ?? 0;
    }
    final expected = _round2(sumItems);
    final actual = _round2(txTotal);
    if (expected == actual) return null;
    return {
      'expected': expected,
      'actual': actual,
      'difference': _round2(actual - expected),
    };
  }

  Future<void> _toggleLabel({
    required String labelId,
    required bool selected,
  }) async {
    try {
      if (selected) {
        await ApiClient.assignLabel(
          transactionId: widget.transactionId,
          labelId: labelId,
        );
      } else {
        await ApiClient.unassignLabel(
          transactionId: widget.transactionId,
          labelId: labelId,
        );
      }
      if (!mounted) return;
      setState(() {
        if (selected) {
          _selectedLabelIds.add(labelId);
        } else {
          _selectedLabelIds.remove(labelId);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _createAndAssignLabel() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('labels_new_label')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.tr('labels_name_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.tr('common_create')),
          ),
        ],
      ),
    );

    if (!mounted || name == null || name.isEmpty) return;
    try {
      final created = await ApiClient.createLabel(name);
      final newId = created['id']?.toString();
      if (newId == null || newId.isEmpty) return;
      setState(() {
        _labels = [..._labels, created];
      });
      await _toggleLabel(labelId: newId, selected: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openLabelsPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final sortedLabels = [..._labels]
          ..sort((a, b) {
            final aName = (a['name'] ?? '').toString().toLowerCase();
            final bName = (b['name'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      context.tr('transaction_select_labels'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _createAndAssignLabel();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('common_new')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (sortedLabels.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      context.tr('labels_empty_subtitle'),
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sortedLabels.length,
                      itemBuilder: (context, index) {
                        final label =
                            sortedLabels[index] as Map<String, dynamic>;
                        final id = label['id']?.toString() ?? '';
                        final name =
                            label['name']?.toString() ??
                            context.tr('labels_title');
                        final selected = _selectedLabelIds.contains(id);
                        return CheckboxListTile(
                          value: selected,
                          title: Text(name),
                          onChanged: (value) {
                            Navigator.pop(context);
                            _toggleLabel(labelId: id, selected: value == true);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
    final itemName =
        item['description']?.toString() ?? context.tr('transaction_item');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('transaction_delete_item_title')),
        content: Text(
          context.tr(
            'transaction_delete_item_confirm',
            params: {'name': itemName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.tr('common_delete')),
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
        _hasLocalEdits = true;
        _items.removeWhere((element) => element['id'].toString() == itemId);
        _itemDescControllers.remove(itemId)?.dispose();
        _itemAmountControllers.remove(itemId)?.dispose();
        _itemQtyControllers.remove(itemId)?.dispose();
        _itemUnitPriceControllers.remove(itemId)?.dispose();
        _itemCategoryIds.remove(itemId);
      });
      _recalculateTotal();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('transaction_item_deleted'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'common_error_with_message',
                params: {'message': e.toString()},
              ),
            ),
            backgroundColor: Colors.red,
          ),
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
        appBar: AppBar(title: Text(context.tr('common_error'))),
        body: Center(child: Text(_error!)),
      );
    }

    final lineMismatches = _computeLineMismatches();
    final totalMismatch = _computeTotalMismatch();
    final showServerWarnings = !_hasLocalEdits && _serverWarnings.isNotEmpty;
    final hasWarnings =
        lineMismatches.isNotEmpty ||
        totalMismatch != null ||
        showServerWarnings;

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
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: context.tr('transaction_merchant_name'),
            hintStyle: const TextStyle(color: Colors.white54),
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
          if (hasWarnings)
            _buildWarningsBanner(
              lineMismatchCount: lineMismatches.length,
              hasTotalMismatch: totalMismatch != null,
              serverWarningCount: showServerWarnings
                  ? _serverWarnings.length
                  : 0,
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildLabelsSection(),
                const SizedBox(height: 12),
                ..._items.map((item) {
                  final itemId = item['id'].toString();
                  return _buildItemCard(item, lineMismatches[itemId]);
                }),
                _buildAddItemButton(),
              ],
            ),
          ),
          _buildFixedFooter(totalMismatch: totalMismatch),
        ],
      ),
    );
  }

  Widget _buildWarningsBanner({
    required int lineMismatchCount,
    required bool hasTotalMismatch,
    required int serverWarningCount,
  }) {
    if (lineMismatchCount == 0 && !hasTotalMismatch) {
      return const SizedBox.shrink();
    }

    final lineText = lineMismatchCount == 1
        ? context.tr('transaction_one_line_total_mismatch')
        : context.tr(
            'transaction_line_total_mismatches',
            params: {'count': lineMismatchCount.toString()},
          );
    final parts = <String>[];
    if (lineMismatchCount > 0) {
      parts.add(lineText);
    }
    if (hasTotalMismatch) {
      parts.add(context.tr('transaction_receipt_total_mismatch'));
    }
    if (serverWarningCount > 0) {
      parts.add(
        serverWarningCount == 1
            ? context.tr('transaction_one_extraction_warning')
            : context.tr(
                'transaction_extraction_warnings',
                params: {'count': serverWarningCount.toString()},
              ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(
                'transaction_review_extraction',
                params: {'details': parts.join(' | ')},
              ),
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelsSection() {
    final selectedLabels = _labels.where((label) {
      final id = label['id']?.toString() ?? '';
      return _selectedLabelIds.contains(id);
    }).toList();

    return GestureDetector(
      onTap: _openLabelsPicker,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_outline, color: Colors.white70, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: selectedLabels.isEmpty
                  ? Text(
                      context.tr('transaction_add_labels'),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 16,
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedLabels.map((raw) {
                        final label = raw as Map<String, dynamic>;
                        final name =
                            label['name']?.toString() ??
                            context.tr('labels_title');
                        return Chip(
                          label: Text(name),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        );
                      }).toList(),
                    ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
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
                  : context.tr('transaction_set_date'),
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
                  : context.tr('transaction_set_time'),
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
            _buildBadge(
              icon: Icons.translate,
              label: _isTranslatingItems
                  ? '${context.tr('transaction_translate')}...'
                  : context.tr('transaction_translate'),
              onTap: _effectiveItemsLanguage.isNotEmpty
                  ? _forceRetranslateItems
                  : null,
            ),
            _buildBadge(
              icon: Icons.image_outlined,
              label: context.tr('transaction_photo'),
            ),
            _buildBadge(
              icon: Icons.currency_exchange,
              label: _currency,
              onTap: _openReceiptCurrencyPicker,
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

  Widget _buildItemCard(
    Map<String, dynamic> item,
    Map<String, double>? mismatch,
  ) {
    final id = item['id'].toString();
    final nameController = _itemDescControllers[id];
    final amountController = _itemAmountControllers[id];
    final qtyController = _itemQtyControllers[id];
    final unitPriceController = _itemUnitPriceControllers[id];
    final selectedCatId = _itemCategoryIds[id];

    final category = _findCategoryById(selectedCatId);
    final catTags = _itemCategoryTags(selectedCatId);
    final catColor = category != null
        ? const Color(0xFFAB47BC)
        : Colors.grey; // Hardcoded purple like first screens, or from cat data
    final unit = item['unit']?.toString().trim();
    final sourceQty = _toDouble(qtyController?.text) ?? _toDouble(item['qty']);
    final resolvedUnit = _displayUnit(
      unit,
      description:
          nameController?.text ?? item['description']?.toString() ?? '',
      qty: sourceQty,
    );
    final sourceAmount = _toDouble(amountController?.text) ?? 0;
    final displayAmount = _toDisplayAmount(sourceAmount);
    final currentName = _normalizeText(
      nameController?.text ?? item['description']?.toString(),
    );
    final translatedName = _normalizeText(
      item['translated_description']?.toString(),
    );
    final hasTranslatedName =
        translatedName.isNotEmpty &&
        translatedName.toLowerCase() != currentName.toLowerCase();

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: context.tr('transaction_item_name'),
                        hintStyle: const TextStyle(color: Colors.white24),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _hasLocalEdits = true;
                          item['description'] = value;
                          item['translated_description'] = null;
                          item['translation_language'] = null;
                          item['translation_source_language'] = null;
                        });
                      },
                    ),
                    if (hasTranslatedName)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          translatedName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
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
                hint: '0.000',
                width: 76,
                decimals: 3,
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
                width: 60,
                decimals: 3,
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
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item['amount_before_discount'] != null &&
                        _toDouble(item['amount_before_discount']) != null &&
                        _toDouble(item['amount_before_discount'])! >
                            sourceAmount)
                      Text(
                        _formatMoney(
                            _displayCurrency,
                            _toDisplayAmount(
                                _toDouble(item['amount_before_discount'])!)),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (item['discount_amount'] != null &&
                        _toDouble(item['discount_amount']) != null &&
                        _toDouble(item['discount_amount'])! > 0)
                      Text(
                        '- ${_formatMoney(_displayCurrency, _toDisplayAmount(_toDouble(item['discount_amount'])!))}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      _formatMoney(_displayCurrency, displayAmount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_displayCurrency.toUpperCase() !=
                        _currency.toUpperCase())
                      Text(
                        _formatMoney(_currency, sourceAmount),
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (mismatch != null) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                'transaction_line_mismatch',
                params: {
                  'expected': _formatMoney(
                    _currency,
                    mismatch['expected'] ?? 0,
                  ),
                  'actual': _formatMoney(_currency, mismatch['actual'] ?? 0),
                },
              ),
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(
                onTap: () => _showCategoryPicker(id),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: catTags
                      .map(
                        (tag) => Container(
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
                            tag,
                            style: TextStyle(
                              color: catColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
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
      _hasLocalEdits = true;
      _amountController.text = total.toStringAsFixed(2);
    });
  }

  double _computeTotalSavingsSource() {
    double totalSavings = 0;
    for (final raw in _items) {
      final item = raw as Map<String, dynamic>;
      var discount = _toDouble(item['discount_amount']);
      if (discount == null || discount == 0) {
        final before = _toDouble(item['amount_before_discount']);
        final currentAmount = _toDouble(item['amount']);
        if (before != null && currentAmount != null) {
          final derived = before - currentAmount;
          if (derived > 0) {
            discount = derived;
          }
        }
      }
      if (discount == null || discount == 0) {
        final itemId = item['id']?.toString();
        final before = _toDouble(item['amount_before_discount']);
        final currentAmount = _toDouble(
          itemId == null ? null : _itemAmountControllers[itemId]?.text,
        );
        if (before != null && currentAmount != null) {
          final derived = before - currentAmount;
          if (derived > 0) {
            discount = derived;
          }
        }
      }
      if (discount == null || discount == 0) {
        final itemId = item['id']?.toString();
        final qty = _toDouble(itemId == null ? null : _itemQtyControllers[itemId]?.text) ??
            _toDouble(item['qty']);
        final unitPrice = _toDouble(
              itemId == null ? null : _itemUnitPriceControllers[itemId]?.text,
            ) ??
            _toDouble(item['unit_price']);
        final amount = _toDouble(itemId == null ? null : _itemAmountControllers[itemId]?.text) ??
            _toDouble(item['amount']);
        if (qty != null && unitPrice != null && amount != null) {
          final derived = _round2((qty * unitPrice) - amount);
          if (derived > 0) {
            discount = derived;
          }
        }
      }
      if (discount == null || discount == 0) {
        continue;
      }
      totalSavings += discount.abs();
    }
    return _round2(totalSavings);
  }

  Widget _buildAddItemButton() {
    return GestureDetector(
      onTap: () {
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        setState(() {
          _hasLocalEdits = true;
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
        child: Center(
          child: Text(
            context.tr('transaction_add_item'),
            style: const TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildFixedFooter({Map<String, double>? totalMismatch}) {
    final sourceTotal = _toDouble(_amountController.text) ?? 0;
    final displayTotal = _toDisplayAmount(sourceTotal);
    final sourceSavings = _computeTotalSavingsSource();
    final displaySavings = _toDisplayAmount(sourceSavings);
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.tr('transaction_total_amount'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatMoney(_displayCurrency, displayTotal),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_displayCurrency.toUpperCase() !=
                        _currency.toUpperCase())
                      Text(
                        _formatMoney(_currency, sourceTotal),
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (sourceSavings > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    context.tr('transaction_total_savings'),
                    style: TextStyle(
                      color: Colors.orange.shade300,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatMoney(_displayCurrency, displaySavings),
                        style: TextStyle(
                          color: Colors.orange.shade300,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_displayCurrency.toUpperCase() !=
                          _currency.toUpperCase())
                        Text(
                          _formatMoney(_currency, sourceSavings),
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    context.tr('transaction_no_discounts'),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            if (totalMismatch != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'transaction_total_mismatch',
                  params: {
                    'expected': _formatMoney(
                      _currency,
                      totalMismatch['expected'] ?? 0,
                    ),
                    'actual': _formatMoney(
                      _currency,
                      totalMismatch['actual'] ?? 0,
                    ),
                  },
                ),
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<String?> _pickParentCategory(String? selectedParentId) {
    final topLevel = _topLevelItemCategories();
    if (topLevel.isEmpty) {
      return Future.value(null);
    }

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
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
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(context.tr('common_cancel')),
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
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white,
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
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white38,
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
      backgroundColor: const Color(0xFF1E1E1E),
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
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('common_cancel')),
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
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              trailing: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white38,
              ),
              onTap: () => Navigator.pop(context, categoryId),
            );
          },
        );
      },
    );
  }

  Future<void> _showCategoryPicker(String itemId) async {
    final selectedCategory = _findCategoryById(_itemCategoryIds[itemId]);
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
      selectedSubcategoryId: _itemCategoryIds[itemId],
    );
    if (!mounted) return;

    setState(() {
      _hasLocalEdits = true;
      _itemCategoryIds[itemId] =
          (selectedSubcategoryId == null || selectedSubcategoryId.isEmpty)
          ? parentCategoryId
          : selectedSubcategoryId;
    });
  }
}
