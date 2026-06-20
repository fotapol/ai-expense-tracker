import 'dart:async';

import 'package:flutter/material.dart';
import 'package:currency_picker/currency_picker.dart';
import '../core/api_client.dart';
import '../core/app_color_semantics.dart';
import '../core/auth_session.dart';
import '../core/item_name_display.dart';
import '../core/item_translation_preferences.dart';
import '../core/item_translation_service.dart';
import '../core/launch_error_copy.dart';
import '../core/localized_dates.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'receipt_item_edit_screen.dart';
import 'receipt_photo_view_screen.dart';
import 'transaction_edit/transaction_edit_controller.dart';

part 'transaction_edit/transaction_edit_screen_widgets.dart';

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
  Color get _primaryActionColor => ShellStyles.accent(context);
  Color get _focusColor => ShellStyles.focusRing(context);
  Color get _dangerColor => ShellStyles.error(context);
  Color get _warningColor => ShellStyles.warningPremium(context);
  Color get _successColor => ShellStyles.success(context);

  final TransactionEditController _controller = TransactionEditController();

  bool get _isLoading => _controller.isLoading;
  set _isLoading(bool value) => _controller.isLoading = value;
  bool get _isSaving => _controller.isSaving;
  set _isSaving(bool value) => _controller.isSaving = value;
  String? get _error => _controller.error;
  set _error(String? value) => _controller.error = value;

  List<dynamic> get _items => _controller.items;
  List<dynamic> get _categories => _controller.categories;
  List<dynamic> get _labels => _controller.labels;
  Set<String> get _selectedLabelIds => _controller.selectedLabelIds;
  List<dynamic> get _serverWarnings => _controller.serverWarnings;
  bool get _hasLocalEdits => _controller.hasLocalEdits;
  set _hasLocalEdits(bool value) => _controller.hasLocalEdits = value;
  bool get _isTranslatingItems => _controller.isTranslatingItems;
  set _isTranslatingItems(bool value) => _controller.isTranslatingItems = value;
  bool get _showTranslatedItems => _controller.showTranslatedItems;
  set _showTranslatedItems(bool value) =>
      _controller.showTranslatedItems = value;
  String? get _transactionId => _controller.transactionId;
  set _transactionId(String? value) => _controller.transactionId = value;
  bool get _isLoadingReceiptPreview => _controller.isLoadingReceiptPreview;
  set _isLoadingReceiptPreview(bool value) =>
      _controller.isLoadingReceiptPreview = value;
  String? get _receiptPreviewUrl => _controller.receiptPreviewUrl;
  set _receiptPreviewUrl(String? value) =>
      _controller.receiptPreviewUrl = value;

  TextEditingController get _merchantController =>
      _controller.merchantController;
  TextEditingController get _amountController => _controller.amountController;
  DateTime? get _occurredAt => _controller.occurredAt;
  set _occurredAt(DateTime? value) => _controller.occurredAt = value;
  String get _currency => _controller.currency;
  set _currency(String value) => _controller.currency = value;
  String get _displayCurrency => _controller.displayCurrency;
  set _displayCurrency(String value) => _controller.displayCurrency = value;
  double get _displayRate => _controller.displayRate;
  set _displayRate(double value) => _controller.displayRate = value;
  String get _appLanguage => _controller.appLanguage;
  String get _effectiveItemsLanguage => _controller.effectiveItemsLanguage;

  Map<String, TextEditingController> get _itemDescControllers =>
      _controller.itemDescControllers;

  String? get _receiptId => _controller.receiptId;
  bool get _isDraftCreateMode => _controller.isDraftCreateMode;
  bool get _canEditTransaction => _controller.canEditTransaction;

  @override
  void initState() {
    super.initState();
    _transactionId = widget.transactionId;
    _fetchData();
  }

  @override
  void dispose() {
    unawaited(ItemTranslationService.instance.flushPending());
    _controller.dispose();
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
      final viewerUserId = meData?['id']?.toString();
      final defaultCurrency = (meData?['default_currency'] ?? 'RSD').toString();

      final catsFuture = ApiClient.listCategories();
      final labelsFuture = ApiClient.listLabels();
      final catsData = await catsFuture;
      final labelsData = await labelsFuture;
      final effectiveItemsLanguage = preferredItemsLanguage.isNotEmpty
          ? preferredItemsLanguage
          : appLanguage;

      if (_transactionId == null) {
        final draft = _controller.blankDraftTransaction(
          currency: defaultCurrency,
          currentUserId: viewerUserId,
        );
        if (!mounted) return;
        setState(() {
          _controller.viewerUserId = viewerUserId;
          _controller.applyTransactionState(
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
          _controller.hasManualTotalOverride = false;
          _receiptPreviewUrl = null;
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
        _controller.viewerUserId = viewerUserId;
        _controller.applyTransactionState(
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
            fallback: context.tr('transaction_open_receipt_error'),
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTransaction() async {
    if (_isSaving) return;

    final payload = _controller.buildSavePayload();
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_amount_required'))),
      );
      return;
    }

    setState(() => _isSaving = true);
    final saveError = context.tr('transaction_save_error');
    try {
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
          _controller.applyTransactionState(
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
      _showEditorError(e, fallback: saveError);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openReceiptPhoto() async {
    final receiptId = _receiptId;
    if (receiptId == null) return;
    final invalidUrlText = context.tr('receipt_photo_invalid_url');
    final previewError = context.tr('transaction_receipt_preview_error');
    final photoTitle = context.tr('transaction_receipt_photo_title');

    try {
      final payload = await ApiClient.getReceiptViewUrl(receiptId);
      if (!mounted) return;
      final viewUrl = payload['view_url']?.toString();
      if (viewUrl == null || viewUrl.isEmpty) {
        throw Exception(invalidUrlText);
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptPhotoViewScreen(
            title: photoTitle,
            viewUrl: viewUrl,
            mimeType: payload['mime_type']?.toString() ?? '',
          ),
        ),
      );
    } catch (e) {
      _showEditorError(e, fallback: previewError);
    }
  }

  Future<void> _loadReceiptPreview() async {
    final receiptId = _receiptId;
    if (receiptId == null) {
      if (!mounted) return;
      setState(() {
        _controller.clearReceiptPreview();
      });
      return;
    }

    setState(() => _controller.beginReceiptPreviewLoad());
    try {
      final payload = await ApiClient.getReceiptViewUrl(receiptId);
      if (!mounted || _receiptId != receiptId) return;
      final viewUrl = payload['view_url']?.toString();
      setState(() {
        _controller.finishReceiptPreviewLoad(viewUrl);
      });
    } catch (_) {
      if (!mounted || _receiptId != receiptId) return;
      setState(() {
        _controller.clearReceiptPreview();
      });
    }
  }

  double? _toDouble(dynamic value) => _controller.toDouble(value);

  String _formatMoney(String currency, double amount) {
    return formatMoney(currency, amount);
  }

  String _normalizeLanguageCode(String? raw) =>
      _controller.normalizeLanguageCode(raw);

  String _normalizeText(String? raw) => _controller.normalizeText(raw);
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

        final currentDescription = _normalizeText(
          _itemDescControllers[itemId]?.text ?? item['description']?.toString(),
        );
        if (currentDescription.isEmpty) continue;

        final translationSource =
            ItemNameDisplayResolver.preferredTranslationSource(
              item: item,
              currentDescription: currentDescription,
            );
        if (translationSource == null || translationSource.text.isEmpty) {
          continue;
        }

        var sourceLanguage = _normalizeLanguageCode(translationSource.language);
        sourceLanguage =
            itemTranslationPreferences.resolveSourceLanguage(
              sourceLanguage,
              fallbackLanguageCode:
                  itemTranslationPreferences.autoDetectSourceLanguage
                  ? null
                  : _resolveAppLanguage(),
            ) ??
            '';
        final existingTranslation = _normalizeText(
          item['translated_description']?.toString(),
        );
        final existingSourceText = _normalizeText(
          item['translation_source_text']?.toString(),
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
            ) ||
            existingSourceText.toLowerCase() !=
                translationSource.text.toLowerCase();
        if (!forceRefresh && !shouldRefreshExistingTranslation) continue;

        final result = await ItemTranslationService.instance.translate(
          sourceText: translationSource.text,
          sourceLanguage: sourceLanguage.isNotEmpty ? sourceLanguage : null,
          targetLanguage: targetLanguage,
          forceRefresh: forceRefresh || shouldRefreshExistingTranslation,
        );
        if (result == null || !mounted) continue;

        final latestDescription = _normalizeText(
          _itemDescControllers[itemId]?.text,
        );
        final latestSource = ItemNameDisplayResolver.preferredTranslationSource(
          item: item,
          currentDescription: latestDescription,
        );
        if (latestSource == null ||
            latestSource.text.toLowerCase() !=
                translationSource.text.toLowerCase()) {
          continue;
        }

        setState(() {
          item['translated_description'] = result.translatedText;
          item['translation_language'] = result.targetLanguage;
          item['translation_source_language'] = result.sourceLanguage;
          item['translation_source_text'] = translationSource.text;
          if (!translationSource.usesNormalizedName &&
              (item['description_lang']?.toString().trim().isEmpty ?? true)) {
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
          _controller.applyCurrency(nextCode);
        });
      },
    );
  }

  String _merchantDisplayName() {
    final merchant = _merchantController.text.trim();
    if (merchant.isNotEmpty) return merchant;
    return _isDraftCreateMode
        ? context.tr('transaction_new_expense')
        : context.tr('transaction_review_receipt');
  }

  void _applyPickedOccurredDate(DateTime date) {
    setState(() {
      _controller.applyOccurredDate(date);
    });
  }

  void _applyPickedOccurredTime(TimeOfDay selected) {
    setState(() {
      _controller.applyOccurredTime(selected);
    });
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
            context.tr('transaction_merchant_dialog_title'),
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
              hintText: context.tr('transaction_merchant_hint'),
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
              child: Text(
                context.tr('common_cancel'),
                style: TextStyle(color: _mutedColor),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draftValue.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(context.tr('common_save')),
            ),
          ],
        ),
      ),
    );

    if (!mounted || value == null) return;
    setState(() {
      _controller.applyMerchantName(value);
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
            context.tr('transaction_receipt_total_label'),
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
              child: Text(
                context.tr('common_cancel'),
                style: TextStyle(color: _mutedColor),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draftValue.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(context.tr('common_save')),
            ),
          ],
        ),
      ),
    );

    if (!mounted || value == null) return;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('transaction_invalid_total'))),
      );
      return;
    }
    setState(() {
      _controller.applyManualTotal(parsed);
    });
  }

  Map<String, dynamic>? _findCategoryById(String? categoryId) =>
      _controller.findCategoryById(categoryId);

  List<_CategoryTagData> _itemCategoryTags(String? categoryId) {
    final category = _findCategoryById(categoryId);
    if (category == null) {
      return <_CategoryTagData>[
        _CategoryTagData(
          label: context.tr('transaction_select_category'),
          tone: ShellStyles.accentTone(context),
        ),
      ];
    }

    final childName = localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    ).trim();
    if (childName.isEmpty) {
      return <_CategoryTagData>[
        _CategoryTagData(
          label: context.tr('transaction_select_category'),
          tone: ShellStyles.accentTone(context),
        ),
      ];
    }
    final childTone = ShellStyles.categoryTone(
      context,
      code: category['code']?.toString(),
      parentCode: category['parent_category_code']?.toString(),
      name: category['name']?.toString(),
      rawHex: category['color']?.toString(),
    );

    final parentId = category['parent_id']?.toString();
    if (parentId == null || parentId.isEmpty) {
      return <_CategoryTagData>[
        _CategoryTagData(label: childName, tone: childTone),
      ];
    }

    final parent = _findCategoryById(parentId);
    final parentName = localizeCategoryByCode(
      context,
      code: parent?['code']?.toString(),
      fallbackName: parent?['name']?.toString(),
    ).trim();
    if (parentName.isEmpty) {
      return <_CategoryTagData>[
        _CategoryTagData(label: childName, tone: childTone),
      ];
    }
    final parentTone = ShellStyles.categoryTone(
      context,
      code: parent?['code']?.toString(),
      name: parent?['name']?.toString(),
      rawHex: parent?['color']?.toString(),
    );

    return <_CategoryTagData>[
      _CategoryTagData(label: parentName, tone: parentTone),
      _CategoryTagData(label: childName, tone: childTone),
    ];
  }

  double _toDisplayAmount(double sourceAmount) =>
      _controller.toDisplayAmount(sourceAmount);

  Map<String, Map<String, double>> _computeLineMismatches() =>
      _controller.computeLineMismatches();

  Map<String, double>? _computeTotalMismatch() =>
      _controller.computeTotalMismatch();
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
        _controller.setLabelSelection(labelId: labelId, selected: selected);
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
            child: Text(
              context.tr('common_cancel'),
              style: TextStyle(color: _mutedColor),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: _primaryActionColor,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
        _controller.appendLabel(created);
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

  String _itemDescription(Map<String, dynamic> item) =>
      _controller.itemDescription(item);

  double _itemAmountValue(Map<String, dynamic> item) =>
      _controller.itemAmountValue(item);

  double? _itemQtyValue(Map<String, dynamic> item) =>
      _controller.itemQtyValue(item);

  double? _itemUnitPriceValue(Map<String, dynamic> item) =>
      _controller.itemUnitPriceValue(item);

  double _itemDiscountValue(Map<String, dynamic> item) =>
      _controller.itemDiscountValue(item);

  double? _itemAmountBeforeDiscountValue(Map<String, dynamic> item) =>
      _controller.itemAmountBeforeDiscountValue(item);

  double _totalSavingsValue() => _controller.totalSavingsValue();

  String? _itemCategoryId(Map<String, dynamic> item) =>
      _controller.itemCategoryId(item);

  String _itemUnitValue(Map<String, dynamic> item) =>
      _controller.itemUnitValue(item);

  void _syncItemControllersFromData(Map<String, dynamic> item) {
    _controller.syncItemControllersFromData(item);
  }

  void _removeItemLocally(String itemId) {
    _controller.removeItemLocally(itemId);
  }

  void _syncTotalToItems({bool force = false}) {
    _controller.syncTotalToItems(force: force);
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
            child: Text(
              context.tr('common_cancel'),
              style: TextStyle(color: _mutedColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.tr('common_delete'),
              style: TextStyle(color: _dangerColor),
            ),
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
    final draft = _controller.buildDraftItem();
    await _openItemEditor(draft, isNew: true);
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

  Future<void> _handleBackPressed() async {
    if (!_hasLocalEdits || !_canEditTransaction) {
      Navigator.pop(context);
      return;
    }

    final action = await showDialog<String>(
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
            context.tr('transaction_unsaved_changes_title'),
            style: TextStyle(color: _textColor, fontWeight: FontWeight.w800),
          ),
          content: Text(
            context.tr('transaction_unsaved_changes_body'),
            style: TextStyle(color: _mutedColor, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'stay'),
              child: Text(
                context.tr('transaction_keep_editing'),
                style: TextStyle(color: _mutedColor),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'discard'),
              child: Text(
                context.tr('transaction_discard_changes'),
                style: TextStyle(color: _dangerColor),
              ),
            ),
            FilledButton(
              onPressed: _isSaving
                  ? null
                  : () => Navigator.pop(dialogContext, 'save'),
              style: FilledButton.styleFrom(
                backgroundColor: _primaryActionColor,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Text(context.tr('common_save')),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null || action == 'stay') return;
    if (action == 'discard') {
      Navigator.pop(context);
      return;
    }
    if (action == 'save') {
      await _saveTransaction();
    }
  }

  String _lineReviewMessage(Map<String, double> mismatch) {
    return context.tr(
      'transaction_line_review_message',
      params: {
        'expected': _formatMoney(_currency, mismatch['expected'] ?? 0),
        'actual': _formatMoney(_currency, mismatch['actual'] ?? 0),
      },
    );
  }

  String _totalReviewMessage(Map<String, double> totalMismatch) {
    return context.tr(
      'transaction_total_review_message',
      params: {
        'expected': _formatMoney(_currency, totalMismatch['expected'] ?? 0),
        'actual': _formatMoney(_currency, totalMismatch['actual'] ?? 0),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('transaction_review_receipt'))),
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
    final showServerWarnings = _serverWarnings.isNotEmpty;
    final hasWarnings =
        lineMismatches.isNotEmpty ||
        totalMismatch != null ||
        showServerWarnings;
    final merchantTitle = _merchantDisplayName();

    return PopScope(
      canPop: !_hasLocalEdits || !_canEditTransaction,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_handleBackPressed());
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: _textColor),
            onPressed: _handleBackPressed,
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
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(Icons.check_rounded, size: 20),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            8,
            14,
            MediaQuery.of(context).padding.bottom + 104,
          ),
          children: [
            if (_receiptId != null) ...[
              _buildReceiptPhotoSection(),
              const SizedBox(height: 10),
            ],
            _buildTopControlRow(),
            if (hasWarnings) ...[
              const SizedBox(height: 10),
              _buildWarningsBanner(
                lineMismatchCount: lineMismatches.length,
                hasTotalMismatch: totalMismatch != null,
                serverWarningCount: showServerWarnings
                    ? _serverWarnings.length
                    : 0,
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Text(
                    context.tr('transaction_items_heading'),
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_items.length}',
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: _panelDecoration(),
                child: Text(
                  context.tr('transaction_empty_items'),
                  style: TextStyle(color: _mutedColor, fontSize: 13),
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
                            lineMismatches[_items[index]['id']?.toString() ??
                                ''],
                        showDivider: index != _items.length - 1,
                      ),
                  ],
                ),
              ),
            _buildAddItemButton(),
            const SizedBox(height: 12),
            Text(
              context.tr('labels_title'),
              style: TextStyle(
                color: _mutedColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            _buildLabelsSection(),
            if (!_canEditTransaction) ...[
              const SizedBox(height: 12),
              Text(
                context.tr('transaction_read_only_owner'),
                style: TextStyle(color: _mutedColor, fontSize: 13),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _buildStickyTotalBar(totalMismatch: totalMismatch),
      ),
    );
  }
}
