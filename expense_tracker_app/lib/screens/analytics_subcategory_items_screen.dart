import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/item_translation_service.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';

class AnalyticsSubcategoryItemsScreen extends StatefulWidget {
  final String subcategoryId;
  final String subcategoryName;
  final String subcategoryCode;
  final DateTime? fromDate;
  final List<String> selectedCategoryIds;
  final List<String> selectedSubcategoryIds;
  final List<String> selectedLabelIds;

  const AnalyticsSubcategoryItemsScreen({
    super.key,
    required this.subcategoryId,
    required this.subcategoryName,
    required this.subcategoryCode,
    required this.fromDate,
    required this.selectedCategoryIds,
    required this.selectedSubcategoryIds,
    required this.selectedLabelIds,
  });

  @override
  State<AnalyticsSubcategoryItemsScreen> createState() =>
      _AnalyticsSubcategoryItemsScreenState();
}

class _AnalyticsSubcategoryItemsScreenState
    extends State<AnalyticsSubcategoryItemsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

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

  Future<void> _translateMissingItems({required String targetLanguage}) async {
    if (targetLanguage.isEmpty || _data == null) return;
    final rawItems = _data?['items'];
    if (rawItems is! List<dynamic>) return;

    for (final raw in rawItems) {
      final item = raw as Map<String, dynamic>;
      final description = _normalizeText(item['description']?.toString());
      if (description.isEmpty) continue;

      final translated = _normalizeText(
        item['translated_description']?.toString(),
      );
      if (translated.isNotEmpty) continue;

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
      );
      if (result == null || !mounted) continue;

      setState(() {
        item['translated_description'] = result.translatedText;
        item['translation_language'] = result.targetLanguage;
        item['translation_source_language'] = result.sourceLanguage;
        if ((item['description_lang']?.toString().trim().isEmpty ?? true)) {
          item['description_lang'] = result.sourceLanguage;
        }
      });
    }

    unawaited(ItemTranslationService.instance.flushPending());
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    unawaited(ItemTranslationService.instance.flushPending());
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
      final effectiveItemsLanguage = preferredItemsLanguage.isNotEmpty
          ? preferredItemsLanguage
          : appLanguage;

      final data = await ApiClient.getSubcategoryItemsSummary(
        subcategoryId: widget.subcategoryId,
        fromDate: widget.fromDate,
        categoryIds: widget.selectedCategoryIds.isNotEmpty
            ? widget.selectedCategoryIds
            : null,
        subcategoryIds: widget.selectedSubcategoryIds.isNotEmpty
            ? widget.selectedSubcategoryIds
            : null,
        labelIds: widget.selectedLabelIds.isNotEmpty
            ? widget.selectedLabelIds
            : null,
        itemLanguage: preferredItemsLanguage.isNotEmpty
            ? preferredItemsLanguage
            : null,
        appLanguage: appLanguage.isNotEmpty ? appLanguage : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
      if (effectiveItemsLanguage.isNotEmpty) {
        unawaited(
          _translateMissingItems(targetLanguage: effectiveItemsLanguage),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  String _formatQty(double value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
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

  String _displayUnit(String? unit, {String? description}) {
    final normalized = (unit ?? '').trim().toUpperCase();
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

  String _buildDetailsLine({
    required int occurrences,
    required double? totalQty,
    required String? unit,
    required String description,
  }) {
    final timesText = occurrences == 1
        ? context.tr('analytics_bought_once')
        : context.tr(
            'analytics_bought_times',
            params: {'count': occurrences.toString()},
          );
    if (totalQty == null) return timesText;

    final qtyText = context.tr(
      'analytics_total_quantity',
      params: {
        'qty': _formatQty(totalQty),
        'unit': _displayUnit(unit, description: description),
      },
    );
    return '$timesText - $qtyText';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(title: Text(widget.subcategoryName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error ?? context.tr('common_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ShellColors.softRed),
                ),
              ),
            )
          : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final totalAmount = (_data?['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalItems = (_data?['total_items'] as num?)?.toInt() ?? 0;
    final items = _data?['items'] as List<dynamic>? ?? [];
    final currency = (_data?['currency']?.toString() ?? 'EUR').toUpperCase();

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: ShellStyles.cardDecoration(context, radius: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShellStyles.sectionLabel(
                  context,
                  context.tr('filters_subcategory'),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.subcategoryName,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney(currency, totalAmount),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'analytics_purchases_count',
                    params: {'count': totalItems.toString()},
                  ),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.tr('analytics_purchased_items'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                context.tr('analytics_no_items_for_subcategory'),
                style: TextStyle(color: ShellStyles.textMuted(context)),
              ),
            ),
          ...items.map((raw) {
            final item = raw as Map<String, dynamic>;
            final name =
                item['description']?.toString() ??
                context.tr('analytics_unknown_item');
            final translatedName = _normalizeText(
              item['translated_description']?.toString(),
            );
            final hasTranslatedName =
                translatedName.isNotEmpty &&
                translatedName.toLowerCase() != name.trim().toLowerCase();
            final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
            final occurrences = (item['occurrences'] as num?)?.toInt() ?? 0;
            final totalQty = (item['total_qty'] as num?)?.toDouble();
            final unit = item['unit']?.toString();
            final details = _buildDetailsLine(
              occurrences: occurrences,
              totalQty: totalQty,
              unit: unit,
              description: name,
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: ShellStyles.cardDecoration(
                context,
                radius: 18,
                withShadow: false,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: ShellStyles.iconBadgeDecoration(context),
                    child: Icon(
                      Icons.shopping_bag_outlined,
                      size: 18,
                      color: ShellStyles.textPrimary(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (hasTranslatedName) ...[
                          const SizedBox(height: 3),
                          Text(
                            translatedName,
                            style: TextStyle(
                              fontSize: 12,
                              color: ShellStyles.textMuted(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: TextStyle(
                            fontSize: 12,
                            color: ShellStyles.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 128,
                    child: Text(
                      formatMoney(currency, amount),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
