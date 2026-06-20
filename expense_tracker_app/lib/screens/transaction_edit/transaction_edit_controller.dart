import 'package:flutter/material.dart';

import '../../core/item_translation_service.dart';

class TransactionEditController {
  bool isLoading = true;
  bool isSaving = false;
  String? error;

  List<dynamic> items = [];
  List<dynamic> categories = [];
  List<dynamic> labels = [];
  Set<String> selectedLabelIds = {};
  List<dynamic> serverWarnings = [];
  bool hasLocalEdits = false;
  bool isTranslatingItems = false;
  bool showTranslatedItems = true;
  Map<String, dynamic>? transactionData;
  String? transactionId;
  String? viewerUserId;
  String? transactionCategoryId;
  bool hasFamilyEntitlement = false;
  bool hasManualTotalOverride = false;
  bool isLoadingReceiptPreview = false;
  String? receiptPreviewUrl;

  final merchantController = TextEditingController();
  final amountController = TextEditingController();
  DateTime? occurredAt;
  String currency = 'RSD';
  String displayCurrency = 'RSD';
  double displayRate = 1.0;
  String appLanguage = '';
  String effectiveItemsLanguage = '';

  final Map<String, TextEditingController> itemDescControllers = {};
  final Map<String, TextEditingController> itemAmountControllers = {};
  final Map<String, TextEditingController> itemQtyControllers = {};
  final Map<String, TextEditingController> itemUnitPriceControllers = {};
  final Map<String, String?> itemCategoryIds = {};
  final Map<String, String> itemUnits = {};

  String? get receiptId {
    final value = transactionData?['receipt_id']?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get isDraftCreateMode => transactionId == null;

  bool get canEditTransaction {
    if (isDraftCreateMode) return true;
    final currentViewerUserId = viewerUserId?.trim() ?? '';
    if (currentViewerUserId.isEmpty) return true;
    return transactionData?['user_id']?.toString() == currentViewerUserId;
  }

  double get subtotalValue => subtotalFromItemsList(items);

  double? get parsedAmountTotal => toDouble(amountController.text);

  void dispose() {
    merchantController.dispose();
    amountController.dispose();
    disposeItemControllers();
  }

  void disposeItemControllers() {
    for (final controller in itemDescControllers.values) {
      controller.dispose();
    }
    for (final controller in itemAmountControllers.values) {
      controller.dispose();
    }
    for (final controller in itemQtyControllers.values) {
      controller.dispose();
    }
    for (final controller in itemUnitPriceControllers.values) {
      controller.dispose();
    }
    itemDescControllers.clear();
    itemAmountControllers.clear();
    itemQtyControllers.clear();
    itemUnitPriceControllers.clear();
    itemCategoryIds.clear();
    itemUnits.clear();
  }

  void applyTransactionState({
    required Map<String, dynamic> txData,
    required List<dynamic> categories,
    required List<dynamic> labels,
    required String appLanguage,
    required String effectiveItemsLanguage,
  }) {
    disposeItemControllers();
    hasLocalEdits = false;
    transactionData = txData;
    this.categories = categories;
    this.labels = labels;
    this.appLanguage = appLanguage;
    this.effectiveItemsLanguage = effectiveItemsLanguage;
    items = List.from(txData['items'] ?? []);
    selectedLabelIds = Set<String>.from(
      (txData['labels'] as List<dynamic>? ?? const [])
          .map((label) => label['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty),
    );
    serverWarnings = List<dynamic>.from(
      txData['extraction_warnings'] as List<dynamic>? ?? const [],
    );

    merchantController.text = txData['merchant_name']?.toString() ?? '';
    transactionCategoryId = txData['category_id']?.toString();
    amountController.text = formatNumberForInput(
      txData['amount_total'],
      decimals: 2,
      keepTrailingZeros: true,
    );
    if (!isDraftCreateMode && amountController.text.isEmpty) {
      amountController.text = '0.00';
    }
    currency = (txData['currency'] ?? 'RSD').toString();
    final sourceTotal = toDouble(txData['amount_total']);
    final displayTotal = toDouble(txData['display_amount_total']);
    displayCurrency = displayTotal != null
        ? (txData['display_currency'] ?? currency).toString()
        : currency;
    if (displayCurrency.toUpperCase() == currency.toUpperCase()) {
      displayRate = 1.0;
    } else if (sourceTotal != null &&
        sourceTotal != 0 &&
        displayTotal != null) {
      displayRate = displayTotal / sourceTotal;
    } else {
      displayRate = 1.0;
    }

    occurredAt = txData['occurred_at'] != null
        ? DateTime.tryParse(txData['occurred_at'].toString())
        : null;

    for (final item in items) {
      final id = item['id'].toString();
      itemDescControllers[id] = TextEditingController(
        text: item['description']?.toString() ?? '',
      );
      itemAmountControllers[id] = TextEditingController(
        text: formatNumberForInput(
          item['amount'],
          decimals: 2,
          keepTrailingZeros: true,
        ),
      );
      itemQtyControllers[id] = TextEditingController(
        text: formatNumberForInput(item['qty'], decimals: 3),
      );
      itemUnitPriceControllers[id] = TextEditingController(
        text: formatNumberForInput(item['unit_price'], decimals: 3),
      );
      itemCategoryIds[id] = item['category_id']?.toString();
      final rawUnit = item['unit']?.toString().trim() ?? '';
      final qty = toDouble(item['qty']);
      itemUnits[id] = displayUnit(
        rawUnit.isNotEmpty ? rawUnit : null,
        qty: qty,
      );
    }

    hasManualTotalOverride =
        sourceTotal != null && round2(sourceTotal) != subtotalValue;
  }

  Map<String, dynamic> blankDraftTransaction({
    required String currency,
    required String? currentUserId,
    DateTime? now,
  }) {
    final occurredAt = (now ?? DateTime.now()).toIso8601String();
    return <String, dynamic>{
      'user_id': currentUserId,
      'receipt_id': null,
      'occurred_at': occurredAt,
      'amount_total': null,
      'currency': currency,
      'merchant_name': '',
      'category_id': null,
      'items': const <dynamic>[],
      'labels': const <dynamic>[],
      'extraction_warnings': const <dynamic>[],
      'source': 'MANUAL',
      'status': 'DRAFT',
      'display_currency': currency,
      'display_amount_total': null,
      'household': null,
      'created_by_user': null,
      'owner_user': null,
    };
  }

  Map<String, dynamic>? buildSavePayload() {
    final parsedAmount = parsedAmountTotal;
    if (parsedAmount == null) return null;

    final payload = <String, dynamic>{
      'merchant_name': merchantController.text,
      'amount_total': parsedAmount,
      'currency': currency,
      'category_id': transactionCategoryId,
      'status': 'CONFIRMED',
    };

    final occurredAt = this.occurredAt;
    if (occurredAt != null) {
      payload['occurred_at'] = occurredAt.toIso8601String();
    }

    payload['items'] = buildItemsPayload();
    return payload;
  }

  List<Map<String, dynamic>> buildItemsPayload() {
    final updatedItems = <Map<String, dynamic>>[];
    var nextLineNo = 1;
    for (final item in items) {
      final id = item['id'].toString();
      final description = (itemDescControllers[id]?.text ?? '').trim();
      final amount =
          double.tryParse(itemAmountControllers[id]?.text ?? '0.00') ?? 0.0;
      final qty = toDouble(itemQtyControllers[id]?.text);
      final unitPrice = toDouble(itemUnitPriceControllers[id]?.text);
      final categoryId = itemCategoryIds[id];
      final unit = itemUnits[id] ?? item['unit'];
      final isBlankDraftItem =
          description.isEmpty &&
          amount == 0.0 &&
          qty == null &&
          unitPrice == null &&
          (unit == null || unit.toString().trim().isEmpty) &&
          (categoryId == null || categoryId.isEmpty);
      if (isDraftCreateMode && isBlankDraftItem) {
        continue;
      }

      final itemPayload = <String, dynamic>{
        'description': description,
        'amount': amount,
        'qty': qty,
        'unit_price': unitPrice,
        'unit': unit,
        'category_id': categoryId,
        'discount_amount': itemDiscountValue(item),
        'amount_before_discount': itemAmountBeforeDiscountValue(item),
      };
      if (isUuid(id)) {
        itemPayload['id'] = id;
      }
      if (isDraftCreateMode) {
        itemPayload['line_no'] = nextLineNo++;
      }
      itemPayload.removeWhere((key, value) {
        if (value == null) return true;
        if ((key == 'unit' || key == 'category_id') &&
            value is String &&
            value.trim().isEmpty) {
          return true;
        }
        return false;
      });
      updatedItems.add(itemPayload);
    }
    return updatedItems;
  }

  void applyMerchantName(String value) {
    merchantController.text = value;
    hasLocalEdits = true;
  }

  void applyCurrency(String nextCode) {
    hasLocalEdits = true;
    currency = nextCode;
    displayCurrency = currency;
    displayRate = 1.0;
  }

  void applyManualTotal(double parsed) {
    amountController.text = parsed.toStringAsFixed(2);
    hasLocalEdits = true;
    hasManualTotalOverride = round2(parsed) != round2(subtotalValue);
  }

  void applyOccurredDate(DateTime date, {DateTime? now}) {
    final base = occurredAt ?? now ?? DateTime.now();
    hasLocalEdits = true;
    occurredAt = DateTime(
      date.year,
      date.month,
      date.day,
      base.hour,
      base.minute,
      base.second,
      base.millisecond,
      base.microsecond,
    );
  }

  void applyOccurredTime(TimeOfDay selected, {DateTime? now}) {
    final base = occurredAt ?? now ?? DateTime.now();
    hasLocalEdits = true;
    occurredAt = DateTime(
      base.year,
      base.month,
      base.day,
      selected.hour,
      selected.minute,
      base.second,
      base.millisecond,
      base.microsecond,
    );
  }

  void setLabelSelection({required String labelId, required bool selected}) {
    if (selected) {
      selectedLabelIds.add(labelId);
    } else {
      selectedLabelIds.remove(labelId);
    }
  }

  void appendLabel(Map<String, dynamic> label) {
    labels = [...labels, label];
  }

  void beginReceiptPreviewLoad() {
    isLoadingReceiptPreview = true;
  }

  void finishReceiptPreviewLoad(String? viewUrl) {
    receiptPreviewUrl = (viewUrl == null || viewUrl.isEmpty) ? null : viewUrl;
    isLoadingReceiptPreview = false;
  }

  void clearReceiptPreview() {
    receiptPreviewUrl = null;
    isLoadingReceiptPreview = false;
  }

  Map<String, dynamic> buildDraftItem({String? id}) {
    return <String, dynamic>{
      'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'description': '',
      'amount': 0.0,
      'qty': 1.0,
      'unit': 'pc',
      'unit_price': 0.0,
      'category_id': null,
      'translated_description': null,
      'translation_language': null,
      'translation_source_language': null,
    };
  }

  Map<String, dynamic>? findCategoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return null;
    for (final raw in categories) {
      final category = raw as Map<String, dynamic>;
      if (category['id']?.toString() == categoryId) {
        return category;
      }
    }
    return null;
  }

  Map<String, Map<String, double>> computeLineMismatches() {
    final mismatches = <String, Map<String, double>>{};
    for (final item in items) {
      final itemId = item['id'].toString();
      final qty = toDouble(itemQtyControllers[itemId]?.text);
      final unitPrice = toDouble(itemUnitPriceControllers[itemId]?.text);
      final amount = toDouble(itemAmountControllers[itemId]?.text);
      final discount = itemDiscountValue(item);
      if (qty == null || unitPrice == null || amount == null) continue;
      final expected = round2((qty * unitPrice) - discount);
      final actual = round2(amount);
      if (expected != actual) {
        mismatches[itemId] = {
          'expected': expected,
          'actual': actual,
          'difference': round2(actual - expected),
        };
      }
    }
    return mismatches;
  }

  Map<String, double>? computeTotalMismatch() {
    final txTotal = toDouble(amountController.text);
    if (txTotal == null) return null;

    final expected = round2(subtotalValue);
    final actual = round2(txTotal);
    if (expected == actual) return null;
    return {
      'expected': expected,
      'actual': actual,
      'difference': round2(actual - expected),
    };
  }

  String itemDescription(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return (itemDescControllers[id]?.text ??
            item['description']?.toString() ??
            '')
        .trim();
  }

  double itemAmountValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return toDouble(itemAmountControllers[id]?.text) ??
        toDouble(item['amount']) ??
        0.0;
  }

  double? itemQtyValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return toDouble(itemQtyControllers[id]?.text) ?? toDouble(item['qty']);
  }

  double? itemUnitPriceValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return toDouble(itemUnitPriceControllers[id]?.text) ??
        toDouble(item['unit_price']);
  }

  double itemDiscountValue(Map<String, dynamic> item) {
    final explicitDiscount = toDouble(item['discount_amount']) ?? 0.0;
    if (explicitDiscount > 0) return round2(explicitDiscount);

    final amount = itemAmountValue(item);
    final amountBeforeDiscount = toDouble(item['amount_before_discount']);
    if (amountBeforeDiscount != null && amountBeforeDiscount > amount) {
      return round2(amountBeforeDiscount - amount);
    }

    final qty = itemQtyValue(item);
    final unitPrice = itemUnitPriceValue(item);
    if (qty == null || unitPrice == null || qty <= 0) return 0.0;
    final inferredDiscount = round2((qty * unitPrice) - amount);
    return inferredDiscount > 0.01 ? inferredDiscount : 0.0;
  }

  double? itemAmountBeforeDiscountValue(Map<String, dynamic> item) {
    final amount = itemAmountValue(item);
    final explicitBefore = toDouble(item['amount_before_discount']);
    if (explicitBefore != null && explicitBefore > amount) {
      return round2(explicitBefore);
    }

    final discount = itemDiscountValue(item);
    if (discount > 0) {
      return round2(amount + discount);
    }

    return null;
  }

  double totalSavingsValue() {
    var total = 0.0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      total += itemDiscountValue(item);
    }
    return round2(total);
  }

  String? itemCategoryId(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return itemCategoryIds[id] ?? item['category_id']?.toString();
  }

  String itemUnitValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final qty = itemQtyValue(item);
    return itemUnits[id] ??
        displayUnit(
          item['unit']?.toString(),
          description: itemDescription(item),
          qty: qty,
        );
  }

  void syncItemControllersFromData(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final descController = itemDescControllers[id];
    if (descController == null) {
      itemDescControllers[id] = TextEditingController(
        text: item['description']?.toString() ?? '',
      );
    } else {
      descController.text = item['description']?.toString() ?? '';
    }

    final amountController = itemAmountControllers[id];
    final amountText = formatNumberForInput(
      item['amount'],
      decimals: 2,
      keepTrailingZeros: true,
    );
    if (amountController == null) {
      itemAmountControllers[id] = TextEditingController(text: amountText);
    } else {
      amountController.text = amountText;
    }

    final qtyController = itemQtyControllers[id];
    final qtyText = formatNumberForInput(item['qty'], decimals: 3);
    if (qtyController == null) {
      itemQtyControllers[id] = TextEditingController(text: qtyText);
    } else {
      qtyController.text = qtyText;
    }

    final unitPriceController = itemUnitPriceControllers[id];
    final unitPriceText = formatNumberForInput(item['unit_price'], decimals: 3);
    if (unitPriceController == null) {
      itemUnitPriceControllers[id] = TextEditingController(text: unitPriceText);
    } else {
      unitPriceController.text = unitPriceText;
    }

    itemCategoryIds[id] = item['category_id']?.toString();
    itemUnits[id] = displayUnit(
      item['unit']?.toString(),
      description: item['description']?.toString(),
      qty: toDouble(item['qty']),
    );
  }

  void removeItemLocally(String itemId) {
    items.removeWhere((element) => element['id']?.toString() == itemId);
    itemDescControllers.remove(itemId)?.dispose();
    itemAmountControllers.remove(itemId)?.dispose();
    itemQtyControllers.remove(itemId)?.dispose();
    itemUnitPriceControllers.remove(itemId)?.dispose();
    itemCategoryIds.remove(itemId);
    itemUnits.remove(itemId);
  }

  void syncTotalToItems({bool force = false}) {
    if (hasManualTotalOverride && !force) return;
    final subtotal = subtotalValue;
    amountController.text = subtotal.toStringAsFixed(2);
    amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: amountController.text.length),
    );
    hasManualTotalOverride = false;
  }

  String normalizeLanguageCode(String? raw) {
    return ItemTranslationService.instance.normalizeLanguageCode(raw);
  }

  String normalizeText(String? raw) {
    return ItemTranslationService.instance.normalizeSourceText(raw ?? '');
  }

  double? toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final normalized = value.toString().replaceAll(',', '.').trim();
    return double.tryParse(normalized);
  }

  String formatNumberForInput(
    dynamic value, {
    int decimals = 2,
    bool keepTrailingZeros = false,
  }) {
    final parsed = toDouble(value);
    if (parsed == null) return '';
    final fixed = parsed.toStringAsFixed(decimals);
    if (keepTrailingZeros) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double round2(double value) => double.parse(value.toStringAsFixed(2));

  double subtotalFromItemsList(List<dynamic> items) {
    double subtotal = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      subtotal += itemAmountValue(item);
    }
    return round2(subtotal);
  }

  double toDisplayAmount(double sourceAmount) {
    return round2(sourceAmount * displayRate);
  }

  String inferUnitFromDescription(String description) {
    final upper = description.toUpperCase();
    if (RegExp(r'\bKG\b|\bKGS\b').hasMatch(upper)) return 'kg';
    if (RegExp(r'\bG\b').hasMatch(upper)) return 'kg';
    if (RegExp(r'\bML\b').hasMatch(upper)) return 'l';
    if (RegExp(r'\bL\b|\bLTR\b|\bLITAR\b|\bLITER\b').hasMatch(upper)) {
      return 'l';
    }
    return 'pc';
  }

  String displayUnit(String? rawUnit, {String? description, double? qty}) {
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
          final inferred = inferUnitFromDescription(description ?? '');
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

  bool isUuid(String value) => _uuidPattern.hasMatch(value);

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
}
