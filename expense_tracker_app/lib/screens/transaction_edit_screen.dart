import 'dart:async';

import 'package:flutter/material.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/auth_session.dart';
import '../core/item_translation_preferences.dart';
import '../core/item_translation_service.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'receipt_item_edit_screen.dart';
import 'receipt_photo_view_screen.dart';

class TransactionEditScreen extends StatefulWidget {
  final String? transactionId;

  const TransactionEditScreen({super.key, this.transactionId});

  const TransactionEditScreen.create({super.key}) : transactionId = null;

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  Color get _bgColor => ShellStyles.background(context);
  Color get _surfaceColor => ShellStyles.surface(context);
  Color get _surfaceAltColor => ShellStyles.inputSurface(context);
  Color get _strokeColor => ShellStyles.border(context);
  Color get _textColor => ShellStyles.textPrimary(context);
  Color get _mutedColor => ShellStyles.textMuted(context);
  Color get _accentColor => ShellStyles.accent(context);
  Color get _primaryActionColor => ShellStyles.heroSurface(context);
  Color get _focusColor => ShellStyles.focusRing(context);
  Color get _dangerColor => ShellStyles.error(context);
  Color get _warningColor => ShellStyles.warningPremium(context);

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
  bool _showTranslatedItems = true;
  Map<String, dynamic>? _transactionData;
  String? _transactionId;
  String? _viewerUserId;
  String? _transactionCategoryId;
  bool _hasFamilyEntitlement = false;
  bool _hasManualTotalOverride = false;
  bool _isLoadingReceiptPreview = false;
  String? _receiptPreviewUrl;
  String? _receiptPreviewFilename;

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
  final Map<String, String> _itemUnits = {}; // item id -> selected unit

  String? get _receiptId {
    final value = _transactionData?['receipt_id']?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get _isDraftCreateMode => _transactionId == null;

  bool get _canEditTransaction {
    if (_isDraftCreateMode) return true;
    final viewerUserId = _viewerUserId?.trim() ?? '';
    if (viewerUserId.isEmpty) return true;
    return _transactionData?['user_id']?.toString() == viewerUserId;
  }

  @override
  void initState() {
    super.initState();
    _transactionId = widget.transactionId;
    _fetchData();
  }

  @override
  void dispose() {
    unawaited(ItemTranslationService.instance.flushPending());
    _merchantController.dispose();
    _amountController.dispose();
    _disposeItemControllers();
    super.dispose();
  }

  void _disposeItemControllers() {
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
    _itemUnits.clear();
  }

  void _applyTransactionState({
    required Map<String, dynamic> txData,
    required List<dynamic> categories,
    required List<dynamic> labels,
    required String appLanguage,
    required String effectiveItemsLanguage,
  }) {
    _disposeItemControllers();
    _hasLocalEdits = false;
    _transactionData = txData;
    _categories = categories;
    _labels = labels;
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

    _merchantController.text = txData['merchant_name']?.toString() ?? '';
    _transactionCategoryId = txData['category_id']?.toString();
    _amountController.text = _formatNumberForInput(
      txData['amount_total'],
      decimals: 2,
      keepTrailingZeros: true,
    );
    if (!_isDraftCreateMode && _amountController.text.isEmpty) {
      _amountController.text = '0.00';
    }
    _currency = (txData['currency'] ?? 'RSD').toString();
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

    _occurredAt = txData['occurred_at'] != null
        ? DateTime.tryParse(txData['occurred_at'].toString())
        : null;

    for (final item in _items) {
      final id = item['id'].toString();
      _itemDescControllers[id] = TextEditingController(
        text: item['description']?.toString() ?? '',
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
        text: _formatNumberForInput(item['unit_price'], decimals: 3),
      );
      _itemCategoryIds[id] = item['category_id']?.toString();
      // Resolve initial unit
      final rawUnit = item['unit']?.toString().trim() ?? '';
      final qty = _toDouble(item['qty']);
      _itemUnits[id] = _displayUnit(
        rawUnit.isNotEmpty ? rawUnit : null,
        qty: qty,
      );
    }

    final subtotal = _subtotalFromItemsList(_items);
    _hasManualTotalOverride =
        sourceTotal != null && _round2(sourceTotal) != subtotal;
  }

  Map<String, dynamic> _blankDraftTransaction({
    required String currency,
    required String? currentUserId,
  }) {
    final occurredAt = DateTime.now().toIso8601String();
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
      final viewerUserId = meData?['id']?.toString();
      final defaultCurrency = (meData?['default_currency'] ?? 'RSD').toString();

      final catsFuture = ApiClient.listCategories();
      final labelsFuture = ApiClient.listLabels();
      final entitlementsFuture = ApiClient.getMeEntitlements();
      final catsData = await catsFuture;
      final labelsData = await labelsFuture;
      var hasFamilyEntitlement = false;
      try {
        final entitlements = await entitlementsFuture;
        final featureCodes =
            (entitlements['feature_codes'] as List<dynamic>? ??
                    const <dynamic>[])
                .map((value) => value.toString())
                .toSet();
        hasFamilyEntitlement = featureCodes.contains('premium.family_plan');
      } catch (_) {
        hasFamilyEntitlement = false;
      }
      final effectiveItemsLanguage = preferredItemsLanguage.isNotEmpty
          ? preferredItemsLanguage
          : appLanguage;

      if (_transactionId == null) {
        final draft = _blankDraftTransaction(
          currency: defaultCurrency,
          currentUserId: viewerUserId,
        );
        if (!mounted) return;
        setState(() {
          _viewerUserId = viewerUserId;
          _hasFamilyEntitlement = hasFamilyEntitlement;
          _applyTransactionState(
            txData: draft,
            categories: catsData,
            labels: labelsData,
            appLanguage: appLanguage,
            effectiveItemsLanguage: effectiveItemsLanguage,
          );
          _currency = defaultCurrency;
          _displayCurrency = defaultCurrency;
          _displayRate = 1.0;
          _occurredAt = DateTime.now();
          _amountController.text = '0.00';
          _hasManualTotalOverride = false;
          _receiptPreviewUrl = null;
          _receiptPreviewFilename = null;
          _isLoadingReceiptPreview = false;
          _isLoading = false;
        });
        return;
      }

      final txFuture = ApiClient.getTransaction(
        _transactionId!,
        itemLanguage: preferredItemsLanguage.isNotEmpty
            ? preferredItemsLanguage
            : null,
        appLanguage: appLanguage.isNotEmpty ? appLanguage : null,
      );

      final txData = await txFuture;

      setState(() {
        _viewerUserId = viewerUserId;
        _hasFamilyEntitlement = hasFamilyEntitlement;
        _applyTransactionState(
          txData: txData,
          categories: catsData,
          labels: labelsData,
          appLanguage: appLanguage,
          effectiveItemsLanguage: effectiveItemsLanguage,
        );
        _isLoading = false;
      });

      unawaited(_loadReceiptPreview());

      if (effectiveItemsLanguage.isNotEmpty) {
        unawaited(
          _translateMissingTransactionItems(
            targetLanguage: effectiveItemsLanguage,
          ),
        );
      }
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      if (mounted) {
        setState(() {
          _error = _friendlyEditorError(
            e,
            fallback:
                'We could not open this receipt right now. Please try again.',
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;

    final amountText = _amountController.text.trim();
    final parsedAmount = double.tryParse(amountText.replaceAll(',', '.'));
    if (parsedAmount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_amount_required'))),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payload = {
        'merchant_name': _merchantController.text,
        'amount_total': parsedAmount,
        'currency': _currency,
        'category_id': _transactionCategoryId,
      };

      if (_occurredAt != null) {
        payload['occurred_at'] = _occurredAt!.toIso8601String();
      }

      final updatedItems = [];
      var nextLineNo = 1;
      for (final item in _items) {
        final id = item['id'].toString();
        final description = (_itemDescControllers[id]?.text ?? '').trim();
        final amount =
            double.tryParse(_itemAmountControllers[id]?.text ?? '0.00') ?? 0.0;
        final qty = _toDouble(_itemQtyControllers[id]?.text);
        final unitPrice = _toDouble(_itemUnitPriceControllers[id]?.text);
        final categoryId = _itemCategoryIds[id];
        final unit = _itemUnits[id] ?? item['unit'];
        final isBlankDraftItem =
            description.isEmpty &&
            amount == 0.0 &&
            qty == null &&
            unitPrice == null &&
            (unit == null || unit.toString().trim().isEmpty) &&
            (categoryId == null || categoryId.isEmpty);
        if (_isDraftCreateMode && isBlankDraftItem) {
          continue;
        }
        final itemPayload = <String, dynamic>{
          'description': description,
          'amount': amount,
          'qty': qty,
          'unit_price': unitPrice,
          'unit': unit,
          'category_id': categoryId,
        };
        if (_isUuid(id)) {
          itemPayload['id'] = id;
        }
        if (_isDraftCreateMode) {
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
      payload['items'] = updatedItems;

      if (_transactionId == null) {
        final created = await ApiClient.createTransaction(
          payload,
          itemLanguage: _effectiveItemsLanguage.isNotEmpty
              ? _effectiveItemsLanguage
              : null,
          appLanguage: _appLanguage.isNotEmpty ? _appLanguage : null,
        );
        if (!mounted) return;
        setState(() {
          _transactionId = created['id']?.toString();
          _applyTransactionState(
            txData: created,
            categories: _categories,
            labels: _labels,
            appLanguage: _appLanguage,
            effectiveItemsLanguage: _effectiveItemsLanguage,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('transaction_created_successfully')),
          ),
        );
        return;
      }

      await ApiClient.updateTransaction(
        _transactionId!,
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
      _showEditorError(
        e,
        fallback:
            'We could not save your changes. Please review the receipt and try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openReceiptPhoto() async {
    final receiptId = _receiptId;
    if (receiptId == null) return;

    try {
      final payload = await ApiClient.getReceiptViewUrl(receiptId);
      if (!mounted) return;
      final viewUrl = payload['view_url']?.toString();
      if (viewUrl == null || viewUrl.isEmpty) {
        throw Exception(context.tr('receipt_photo_invalid_url'));
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptPhotoViewScreen(
            title:
                payload['original_filename']?.toString() ??
                context.tr('transaction_photo'),
            viewUrl: viewUrl,
            mimeType: payload['mime_type']?.toString() ?? '',
          ),
        ),
      );
    } catch (e) {
      _showEditorError(
        e,
        fallback: 'We could not open the receipt preview right now.',
      );
    }
  }

  Future<void> _loadReceiptPreview() async {
    final receiptId = _receiptId;
    if (receiptId == null) {
      if (!mounted) return;
      setState(() {
        _receiptPreviewUrl = null;
        _receiptPreviewFilename = null;
        _isLoadingReceiptPreview = false;
      });
      return;
    }

    setState(() => _isLoadingReceiptPreview = true);
    try {
      final payload = await ApiClient.getReceiptViewUrl(receiptId);
      if (!mounted || _receiptId != receiptId) return;
      final viewUrl = payload['view_url']?.toString();
      setState(() {
        _receiptPreviewUrl = (viewUrl == null || viewUrl.isEmpty)
            ? null
            : viewUrl;
        _receiptPreviewFilename = payload['original_filename']?.toString();
        _isLoadingReceiptPreview = false;
      });
    } catch (_) {
      if (!mounted || _receiptId != receiptId) return;
      setState(() {
        _receiptPreviewUrl = null;
        _receiptPreviewFilename = null;
        _isLoadingReceiptPreview = false;
      });
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

  // ignore: unused_element
  String _currencySymbol(String code) {
    final normalized = code.toUpperCase();
    if (normalized == 'EUR') return '\u20AC';
    if (normalized == 'USD') return '\$';
    if (normalized == 'GBP') return '\u00A3';
    if (normalized == 'AUD') return 'A\$';
    if (normalized == 'CAD') return 'C\$';
    if (normalized == 'RSD') return 'RSD ';
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
    return formatMoney(currency, amount);
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

        var sourceLanguage = _normalizeLanguageCode(
          item['description_lang']?.toString(),
        );
        if (sourceLanguage.isEmpty) {
          sourceLanguage = _normalizeLanguageCode(
            item['translation_source_language']?.toString(),
          );
        }
        sourceLanguage =
            itemTranslationPreferences.resolveSourceLanguage(
              sourceLanguage,
              fallbackLanguageCode: _resolveAppLanguage(),
            ) ??
            '';
        final existingTranslation = _normalizeText(
          item['translated_description']?.toString(),
        );
        final shouldRefreshExistingTranslation =
            ItemTranslationService.shouldRetranslate(
              translatedText: existingTranslation,
              expectedSourceLanguage: sourceLanguage,
              expectedTargetLanguage: targetLanguage,
              translatedSourceLanguage: item['translation_source_language']
                  ?.toString(),
              translatedTargetLanguage: item['translation_language']
                  ?.toString(),
            );
        if (!forceRefresh && !shouldRefreshExistingTranslation) continue;

        final result = await ItemTranslationService.instance.translate(
          sourceText: description,
          sourceLanguage: sourceLanguage.isNotEmpty ? sourceLanguage : null,
          targetLanguage: targetLanguage,
          forceRefresh: forceRefresh || shouldRefreshExistingTranslation,
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

  Future<void> _toggleTranslatedItems() async {
    if (_effectiveItemsLanguage.isEmpty || _isTranslatingItems) return;
    final nextValue = !_showTranslatedItems;
    setState(() => _showTranslatedItems = nextValue);
    if (!nextValue) return;
    await _translateMissingTransactionItems(
      targetLanguage: _effectiveItemsLanguage,
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

  String _merchantDisplayName() {
    final merchant = _merchantController.text.trim();
    if (merchant.isNotEmpty) return merchant;
    return _isDraftCreateMode ? 'New expense' : 'Review receipt';
  }

  Future<void> _openMerchantNameEditor() async {
    if (!_canEditTransaction) return;
    var draftValue = _merchantController.text;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ShellStyles.clampOverlayScale(
        dialogContext,
        AlertDialog(
          backgroundColor: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: _strokeColor),
          ),
          title: Text(
            'Merchant',
            style: TextStyle(color: _textColor, fontWeight: FontWeight.w700),
          ),
          content: TextFormField(
            initialValue: draftValue,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (_) =>
                Navigator.pop(dialogContext, draftValue.trim()),
            style: TextStyle(color: _textColor),
            decoration: InputDecoration(
              hintText: 'Store or merchant name',
              hintStyle: TextStyle(color: _mutedColor),
              filled: true,
              fillColor: _surfaceAltColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _strokeColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _strokeColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _focusColor, width: 1.6),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: _mutedColor)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draftValue.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                foregroundColor: ShellStyles.heroTextPrimary(context),
              ),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || value == null) return;
    setState(() {
      _merchantController.text = value;
      _hasLocalEdits = true;
    });
  }

  Future<void> _openTotalEditor() async {
    if (!_canEditTransaction) return;
    var draftValue = _amountController.text;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ShellStyles.clampOverlayScale(
        dialogContext,
        AlertDialog(
          backgroundColor: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: _strokeColor),
          ),
          title: Text(
            'Receipt total',
            style: TextStyle(color: _textColor, fontWeight: FontWeight.w700),
          ),
          content: TextFormField(
            initialValue: draftValue,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (_) =>
                Navigator.pop(dialogContext, draftValue.trim()),
            style: TextStyle(color: _textColor),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: _mutedColor),
              filled: true,
              fillColor: _surfaceAltColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _strokeColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _strokeColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: _focusColor, width: 1.6),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: _mutedColor)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draftValue.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                foregroundColor: ShellStyles.heroTextPrimary(context),
              ),
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || value == null) return;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid total amount.')),
      );
      return;
    }
    setState(() {
      _amountController.text = parsed.toStringAsFixed(2);
      _hasLocalEdits = true;
      _hasManualTotalOverride = _round2(parsed) != _round2(_subtotalValue);
    });
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

  double _subtotalFromItemsList(List<dynamic> items) {
    double subtotal = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      subtotal += _itemAmountValue(item);
    }
    return _round2(subtotal);
  }

  double get _subtotalValue {
    return _subtotalFromItemsList(_items);
  }

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

    final expected = _round2(_subtotalValue);
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
    final transactionId = _transactionId;
    if (transactionId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_save_before_labels'))),
      );
      return;
    }
    try {
      if (selected) {
        await ApiClient.assignLabel(
          transactionId: transactionId,
          labelId: labelId,
        );
      } else {
        await ApiClient.unassignLabel(
          transactionId: transactionId,
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
      _showEditorError(
        e,
        fallback: 'We could not update labels right now. Please try again.',
      );
    }
  }

  Future<void> _createAndAssignLabel() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: _strokeColor),
        ),
        title: Text(
          context.tr('labels_new_label'),
          style: TextStyle(color: _textColor, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: _textColor),
          decoration: InputDecoration(
            hintText: context.tr('labels_name_hint'),
            hintStyle: TextStyle(color: _mutedColor),
            filled: true,
            fillColor: _surfaceAltColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _strokeColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _strokeColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _focusColor, width: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _mutedColor)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: _primaryActionColor,
              foregroundColor: ShellStyles.heroTextPrimary(context),
            ),
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
      _showEditorError(
        e,
        fallback: 'We could not create that label right now. Please try again.',
      );
    }
  }

  Future<void> _openLabelsPicker() async {
    if (_transactionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_save_before_labels'))),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: _accentColor,
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _createAndAssignLabel();
                      },
                      icon: Icon(Icons.add),
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
                      style: TextStyle(color: _mutedColor),
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
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: _panelDecoration(color: _surfaceAltColor),
                          child: CheckboxListTile(
                            value: selected,
                            activeColor: _accentColor,
                            checkColor: _bgColor,
                            side: BorderSide(color: _strokeColor),
                            title: Text(
                              name,
                              style: TextStyle(
                                color: _textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) {
                              Navigator.pop(context);
                              _toggleLabel(
                                labelId: id,
                                selected: value == true,
                              );
                            },
                          ),
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

  String _itemDescription(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return (_itemDescControllers[id]?.text ??
            item['description']?.toString() ??
            '')
        .trim();
  }

  double _itemAmountValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return _toDouble(_itemAmountControllers[id]?.text) ??
        _toDouble(item['amount']) ??
        0.0;
  }

  double? _itemQtyValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return _toDouble(_itemQtyControllers[id]?.text) ?? _toDouble(item['qty']);
  }

  double? _itemUnitPriceValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return _toDouble(_itemUnitPriceControllers[id]?.text) ??
        _toDouble(item['unit_price']);
  }

  String? _itemCategoryId(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    return _itemCategoryIds[id] ?? item['category_id']?.toString();
  }

  String _itemUnitValue(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    final qty = _itemQtyValue(item);
    return _itemUnits[id] ??
        _displayUnit(
          item['unit']?.toString(),
          description: _itemDescription(item),
          qty: qty,
        );
  }

  void _syncItemControllersFromData(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final descController = _itemDescControllers[id];
    if (descController == null) {
      _itemDescControllers[id] = TextEditingController(
        text: item['description']?.toString() ?? '',
      );
    } else {
      descController.text = item['description']?.toString() ?? '';
    }

    final amountController = _itemAmountControllers[id];
    final amountText = _formatNumberForInput(
      item['amount'],
      decimals: 2,
      keepTrailingZeros: true,
    );
    if (amountController == null) {
      _itemAmountControllers[id] = TextEditingController(text: amountText);
    } else {
      amountController.text = amountText;
    }

    final qtyController = _itemQtyControllers[id];
    final qtyText = _formatNumberForInput(item['qty'], decimals: 3);
    if (qtyController == null) {
      _itemQtyControllers[id] = TextEditingController(text: qtyText);
    } else {
      qtyController.text = qtyText;
    }

    final unitPriceController = _itemUnitPriceControllers[id];
    final unitPriceText = _formatNumberForInput(
      item['unit_price'],
      decimals: 3,
    );
    if (unitPriceController == null) {
      _itemUnitPriceControllers[id] = TextEditingController(
        text: unitPriceText,
      );
    } else {
      unitPriceController.text = unitPriceText;
    }

    _itemCategoryIds[id] = item['category_id']?.toString();
    _itemUnits[id] = _displayUnit(
      item['unit']?.toString(),
      description: item['description']?.toString(),
      qty: _toDouble(item['qty']),
    );
  }

  void _removeItemLocally(String itemId) {
    _items.removeWhere((element) => element['id']?.toString() == itemId);
    _itemDescControllers.remove(itemId)?.dispose();
    _itemAmountControllers.remove(itemId)?.dispose();
    _itemQtyControllers.remove(itemId)?.dispose();
    _itemUnitPriceControllers.remove(itemId)?.dispose();
    _itemCategoryIds.remove(itemId);
    _itemUnits.remove(itemId);
  }

  void _syncTotalToItems({bool force = false}) {
    if (_hasManualTotalOverride && !force) return;
    final subtotal = _subtotalValue;
    _amountController.text = subtotal.toStringAsFixed(2);
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: _amountController.text.length),
    );
    _hasManualTotalOverride = false;
  }

  Future<bool> _confirmDeleteItemFromList(Map<String, dynamic> item) async {
    final itemName = _itemDescription(item).isEmpty
        ? context.tr('transaction_item')
        : _itemDescription(item);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text(
          context.tr('transaction_delete_item_title'),
          style: TextStyle(color: _textColor),
        ),
        content: Text(
          context.tr(
            'transaction_delete_item_confirm',
            params: {'name': itemName},
          ),
          style: TextStyle(color: _mutedColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _mutedColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: _dangerColor)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _hasLocalEdits = true;
        _removeItemLocally(item['id']?.toString() ?? '');
        _syncTotalToItems();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_item_deleted'))),
      );
      return true;
    }
    return false;
  }

  Future<void> _openItemEditor(
    Map<String, dynamic> item, {
    bool isNew = false,
  }) async {
    final editableItem = Map<String, dynamic>.from(item);
    editableItem['description'] = _itemDescription(item);
    editableItem['amount'] = _itemAmountValue(item);
    editableItem['qty'] = _itemQtyValue(item);
    editableItem['unit_price'] = _itemUnitPriceValue(item);
    editableItem['unit'] = _itemUnitValue(item);
    editableItem['category_id'] = _itemCategoryId(item);

    final result = await Navigator.of(context).push<ReceiptItemEditResult>(
      MaterialPageRoute(
        builder: (_) => ReceiptItemEditScreen(
          initialItem: editableItem,
          categories: _categories,
          sourceCurrency: _currency,
          displayCurrency: _displayCurrency,
          displayRate: _displayRate,
          canEdit: _canEditTransaction,
          isNew: isNew,
        ),
      ),
    );

    if (!mounted || result == null) return;

    final itemId = editableItem['id']?.toString() ?? '';
    if (result.deleted) {
      if (itemId.isEmpty) return;
      setState(() {
        _hasLocalEdits = true;
        _removeItemLocally(itemId);
        _syncTotalToItems();
      });
      return;
    }

    final nextItem = result.item;
    if (nextItem == null) return;
    final nextId = nextItem['id']?.toString() ?? '';
    if (nextId.isEmpty) return;

    setState(() {
      _hasLocalEdits = true;
      final existingIndex = _items.indexWhere(
        (candidate) => candidate['id']?.toString() == nextId,
      );
      if (existingIndex >= 0) {
        _items[existingIndex] = Map<String, dynamic>.from(nextItem);
      } else {
        _items.add(Map<String, dynamic>.from(nextItem));
      }
      _syncItemControllersFromData(nextItem);
      _syncTotalToItems();
    });
  }

  Future<void> _addItemAndOpenEditor() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final draft = <String, dynamic>{
      'id': id,
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
    await _openItemEditor(draft, isNew: true);
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

  String _friendlyEditorError(Object error, {required String fallback}) {
    return friendlyLaunchErrorMessage(error, fallback: fallback);
  }

  void _showEditorError(Object error, {required String fallback}) {
    if (isExpiredSessionError(error)) {
      unawaited(maybeHandleExpiredSession(error));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyEditorError(error, fallback: fallback)),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _lineReviewMessage(Map<String, double> mismatch) {
    return 'Review this line item: it should be ${_formatMoney(_currency, mismatch['expected'] ?? 0)} and currently shows ${_formatMoney(_currency, mismatch['actual'] ?? 0)}.';
  }

  String _totalReviewMessage(Map<String, double> totalMismatch) {
    return 'Review the total before saving: items add up to ${_formatMoney(_currency, totalMismatch['expected'] ?? 0)} while the receipt total is ${_formatMoney(_currency, totalMismatch['actual'] ?? 0)}.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Review receipt')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _fetchData,
                  child: Text(context.tr('common_retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final lineMismatches = _computeLineMismatches();
    final totalMismatch = _computeTotalMismatch();
    final showServerWarnings = !_hasLocalEdits && _serverWarnings.isNotEmpty;
    final hasWarnings =
        lineMismatches.isNotEmpty ||
        totalMismatch != null ||
        showServerWarnings;
    final attributionSection = _buildAttributionSection();
    final merchantTitle = _merchantDisplayName();

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: _canEditTransaction ? _openMerchantNameEditor : null,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    merchantTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_canEditTransaction) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.edit_outlined, size: 16, color: _mutedColor),
                ],
              ],
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: FilledButton(
              onPressed: _isSaving || !_canEditTransaction
                  ? null
                  : _saveTransaction,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                disabledBackgroundColor: _surfaceAltColor,
                foregroundColor: ShellStyles.heroTextPrimary(context),
                minimumSize: const Size(0, 42),
                fixedSize: const Size(42, 42),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(Icons.check_rounded, size: 20),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          MediaQuery.of(context).padding.bottom + 120,
        ),
        children: [
          if (_receiptId != null) ...[
            _buildReceiptPhotoSection(),
            const SizedBox(height: 14),
          ],
          _buildTopControlRow(),
          const SizedBox(height: 14),
          _buildReviewSummaryCard(hasWarnings: hasWarnings),
          if (hasWarnings) ...[
            const SizedBox(height: 14),
            _buildWarningsBanner(
              lineMismatchCount: lineMismatches.length,
              hasTotalMismatch: totalMismatch != null,
              serverWarningCount: showServerWarnings
                  ? _serverWarnings.length
                  : 0,
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Items',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: _panelDecoration(),
              child: Text(
                'No line items yet. Add your first item to finish this receipt.',
                style: TextStyle(color: _mutedColor, fontSize: 14),
              ),
            )
          else
            Container(
              decoration: _panelDecoration(),
              child: Column(
                children: [
                  for (var index = 0; index < _items.length; index++)
                    _buildSwipeableItemRow(
                      item: _items[index] as Map<String, dynamic>,
                      mismatch:
                          lineMismatches[_items[index]['id']?.toString() ?? ''],
                      showDivider: index != _items.length - 1,
                    ),
                ],
              ),
            ),
          _buildAddItemButton(),
          const SizedBox(height: 16),
          Text(
            'Labels',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          _buildLabelsSection(),
          if (attributionSection != null) ...[
            const SizedBox(height: 14),
            attributionSection,
          ],
          if (!_canEditTransaction) ...[
            const SizedBox(height: 16),
            Text(
              'You can review this receipt, but only the owner can edit it.',
              style: TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _buildStickyTotalBar(totalMismatch: totalMismatch),
    );
  }

  Widget _buildReviewSummaryCard({required bool hasWarnings}) {
    final title = hasWarnings
        ? 'Check before saving'
        : _isDraftCreateMode
        ? 'Ready to save'
        : 'Ready to update';
    final subtitle = hasWarnings
        ? 'A few extracted details need a quick check before you save this expense.'
        : _isDraftCreateMode
        ? 'Save this expense once everything looks right.'
        : 'Save when you are ready to update this expense in your history.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _panelDecoration(
        color: _surfaceAltColor,
        borderColor: _strokeColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: _mutedColor, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration({
    Color? color,
    Color? borderColor,
    bool withShadow = false,
    double radius = 20,
  }) {
    return BoxDecoration(
      color: color ?? _surfaceColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? _strokeColor),
      boxShadow: withShadow
          ? const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ]
          : const [],
    );
  }

  Widget _buildTopControlRow() {
    final occurred = _occurredAt;
    final dateLabel = occurred != null
        ? DateFormat('MMM d, h:mm a').format(occurred)
        : 'Set date & time';
    final translationEnabled =
        _effectiveItemsLanguage.isNotEmpty && _showTranslatedItems;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: !_canEditTransaction
                ? null
                : () async {
                    await _pickOccurredDate();
                    if (!mounted) return;
                    await _pickOccurredTime();
                  },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: _panelDecoration(
                color: _surfaceColor,
                borderColor: _strokeColor,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: _textColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: _canEditTransaction ? _openReceiptCurrencyPicker : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _panelDecoration(
              color: _surfaceColor,
              borderColor: _strokeColor,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.currency, size: 18, color: _textColor),
                const SizedBox(width: 8),
                Text(
                  _currency.toUpperCase(),
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: _effectiveItemsLanguage.isNotEmpty && !_isTranslatingItems
              ? _toggleTranslatedItems
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: _panelDecoration(
              color: translationEnabled ? _surfaceAltColor : _surfaceColor,
              borderColor: translationEnabled ? _textColor : _strokeColor,
            ),
            alignment: Alignment.center,
            child: _isTranslatingItems
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_textColor),
                    ),
                  )
                : Icon(
                    AppIcons.translate,
                    size: 18,
                    color: _effectiveItemsLanguage.isEmpty
                        ? _mutedColor
                        : _textColor,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptPhotoSection() {
    final hasPreview = (_receiptPreviewUrl ?? '').isNotEmpty;
    return InkWell(
      onTap: _openReceiptPhoto,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: _panelDecoration(withShadow: true),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ColoredBox(
                color: _surfaceAltColor,
                child: _isLoadingReceiptPreview
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(_textColor),
                        ),
                      )
                    : hasPreview
                    ? Image.network(
                        _receiptPreviewUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildPhotoFallback(),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _textColor,
                              ),
                            ),
                          );
                        },
                      )
                    : _buildPhotoFallback(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _receiptPreviewFilename?.trim().isNotEmpty == true
                              ? _receiptPreviewFilename!
                              : context.tr('transaction_photo'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Open receipt photo',
                          style: TextStyle(color: _mutedColor, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(AppIcons.chevronRight, size: 18, color: _mutedColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoFallback() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.photo, size: 30, color: _mutedColor),
          SizedBox(height: 10),
          Text(
            'Receipt photo',
            style: TextStyle(color: _mutedColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _labelsSummaryText(List<dynamic> selectedLabels) {
    if (selectedLabels.isEmpty) return 'Add labels';
    final names = selectedLabels
        .map((raw) => (raw as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    if (names.isEmpty) return 'Add labels';
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  Widget _buildWarningsBanner({
    required int lineMismatchCount,
    required bool hasTotalMismatch,
    required int serverWarningCount,
  }) {
    if (lineMismatchCount == 0 &&
        !hasTotalMismatch &&
        serverWarningCount == 0) {
      return const SizedBox.shrink();
    }

    final lineText = lineMismatchCount == 1
        ? 'Review 1 item total'
        : 'Review $lineMismatchCount item totals';
    final parts = <String>[];
    if (lineMismatchCount > 0) {
      parts.add(lineText);
    }
    if (hasTotalMismatch) {
      parts.add('Review the receipt total');
    }
    if (serverWarningCount > 0) {
      parts.add(
        serverWarningCount == 1
            ? 'Check 1 extracted detail'
            : 'Check $serverWarningCount extracted details',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
        color: _surfaceAltColor,
        borderColor: _strokeColor,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: _textColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Take a quick final look before saving. ${parts.join(' • ')}.',
              style: TextStyle(
                color: _textColor,
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

    return InkWell(
      onTap: _openLabelsPicker,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: _panelDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(AppIcons.labels, size: 20, color: _mutedColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _labelsSummaryText(selectedLabels),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(AppIcons.chevronRight, size: 18, color: _mutedColor),
          ],
        ),
      ),
    );
  }

  Widget? _buildAttributionSection() {
    if (!_hasFamilyEntitlement) {
      return null;
    }
    // Hidden in the single-user launch build.
    return null;
  }

  Future<void> _pickOccurredDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (dialogContext, child) =>
          ShellStyles.clampOverlayScale(dialogContext, child!),
    );
    if (date == null || !mounted) return;
    final base = _occurredAt ?? DateTime.now();
    setState(() {
      _hasLocalEdits = true;
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

  Future<void> _pickOccurredTime() async {
    final base = _occurredAt ?? DateTime.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _hasLocalEdits = true;
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

  Widget _buildSwipeableItemRow({
    required Map<String, dynamic> item,
    required Map<String, double>? mismatch,
    required bool showDivider,
  }) {
    return Dismissible(
      key: Key(item['id']?.toString() ?? DateTime.now().toIso8601String()),
      direction: _canEditTransaction
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) => _confirmDeleteItemFromList(item),
      background: Container(
        margin: EdgeInsets.only(bottom: showDivider ? 1 : 0),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: _dangerColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: _buildItemCard(item, mismatch, showDivider: showDivider),
    );
  }

  Widget _buildItemCard(
    Map<String, dynamic> item,
    Map<String, double>? mismatch, {
    bool showDivider = true,
  }) {
    final selectedCatId = _itemCategoryId(item);
    final catTags = _itemCategoryTags(selectedCatId);
    final sourceQty = _itemQtyValue(item);
    final resolvedUnit = _itemUnitValue(item);
    final unitLabel = resolvedUnit == 'pc' ? 'pcs' : resolvedUnit;
    final unitPrice = _itemUnitPriceValue(item);
    final sourceAmount = _itemAmountValue(item);
    final displayAmount = _toDisplayAmount(sourceAmount);
    final currentName = _normalizeText(_itemDescription(item));
    final translatedName = _normalizeText(
      item['translated_description']?.toString(),
    );
    final hasTranslatedName =
        translatedName.isNotEmpty &&
        translatedName.toLowerCase() != currentName.toLowerCase();
    final showTranslatedName = _showTranslatedItems && hasTranslatedName;
    final itemCurrencyLabel = CurrencyDisplay.labelForCode(_currency);
    final displayCurrencyLabel = CurrencyDisplay.labelForCode(_displayCurrency);
    final quantityLineParts = <String>[];
    if (sourceQty != null) {
      final qtyLabel = sourceQty % 1 == 0
          ? sourceQty.toStringAsFixed(0)
          : sourceQty
                .toStringAsFixed(3)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '');
      quantityLineParts.add('$qtyLabel $unitLabel');
    }
    if (unitPrice != null) {
      quantityLineParts.add(
        '${_formatMoney(_currency, unitPrice)} / $unitLabel',
      );
    }

    return InkWell(
      onTap: _canEditTransaction ? () => _openItemEditor(item) : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: _strokeColor.withAlpha(180)))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentName.isEmpty
                            ? context.tr('transaction_item_name')
                            : currentName,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      if (showTranslatedName) ...[
                        const SizedBox(height: 6),
                        Text(
                          translatedName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _mutedColor, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatMoney(_currency, sourceAmount),
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 18,
                      child:
                          _displayCurrency.toUpperCase() !=
                              _currency.toUpperCase()
                          ? Text(
                              '$displayCurrencyLabel ${displayAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: _mutedColor,
                                fontSize: 12,
                              ),
                            )
                          : Text(
                              ' ',
                              style: TextStyle(
                                color: Colors.transparent,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: _mutedColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: catTags
                  .map((tag) => _buildCategoryBadge(label: tag))
                  .toList(growable: false),
            ),
            const SizedBox(height: 8),
            Text(
              quantityLineParts.isEmpty
                  ? 'Add quantity, unit, and price'
                  : quantityLineParts.join(' / '),
              style: TextStyle(
                color: _mutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_displayCurrency.toUpperCase() != _currency.toUpperCase()) ...[
              const SizedBox(height: 8),
              Text(
                '$itemCurrencyLabel ${sourceAmount.toStringAsFixed(2)} / $displayCurrencyLabel ${displayAmount.toStringAsFixed(2)}',
                style: TextStyle(color: _mutedColor, fontSize: 12),
              ),
            ],
            if (mismatch != null) ...[
              const SizedBox(height: 8),
              Text(
                _lineReviewMessage(mismatch),
                style: TextStyle(
                  color: _mutedColor,
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

  Widget _buildCategoryBadge({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _surfaceAltColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _strokeColor),
      ),
      child: Text(
        label.trim(),
        style: TextStyle(
          color: _mutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAddItemButton() {
    return InkWell(
      onTap: !_canEditTransaction ? null : _addItemAndOpenEditor,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: _panelDecoration(
          color: Colors.transparent,
          borderColor: _strokeColor,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.add, size: 18, color: _textColor),
              const SizedBox(width: 8),
              Text(
                context.tr('transaction_add_item'),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyTotalBar({Map<String, double>? totalMismatch}) {
    final sourceTotal = _toDouble(_amountController.text) ?? 0;
    final displayTotal = _toDisplayAmount(sourceTotal);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: _surfaceColor,
          border: Border(top: BorderSide(color: _strokeColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (totalMismatch != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _totalReviewMessage(totalMismatch),
                    style: TextStyle(
                      color: _warningColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _canEditTransaction ? _openTotalEditor : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Receipt total',
                            style: TextStyle(
                              color: _mutedColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatMoney(_currency, sourceTotal),
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_displayCurrency.toUpperCase() != _currency.toUpperCase())
                  Text(
                    _formatMoney(_displayCurrency, displayTotal),
                    style: TextStyle(color: _mutedColor, fontSize: 12),
                  ),
                if (_canEditTransaction) ...[
                  const SizedBox(width: 10),
                  Icon(Icons.edit_outlined, size: 16, color: _mutedColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
