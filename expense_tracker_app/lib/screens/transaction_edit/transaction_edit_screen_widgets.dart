part of '../transaction_edit_screen.dart';

extension _TransactionEditScreenWidgets on _TransactionEditScreenState {
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
        ? formatLocalizedDayMonthTime(context, occurred)
        : context.tr('transaction_set_date');
    final translationEnabled =
        _effectiveItemsLanguage.isNotEmpty && _showTranslatedItems;
    final languageLabel = _effectiveItemsLanguage.isEmpty
        ? 'LANG'
        : _effectiveItemsLanguage.toUpperCase();

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
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: _panelDecoration(
                color: _surfaceColor,
                borderColor: _strokeColor,
                radius: 14,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: _mutedColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _canEditTransaction ? _openReceiptCurrencyPicker : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: _panelDecoration(
              color: _surfaceColor,
              borderColor: _strokeColor,
              radius: 14,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.currency, size: 15, color: _mutedColor),
                const SizedBox(width: 6),
                Text(
                  _currency.toUpperCase(),
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _effectiveItemsLanguage.isNotEmpty && !_isTranslatingItems
              ? _toggleTranslatedItems
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 42,
            width: _isTranslatingItems ? 42 : null,
            padding: EdgeInsets.symmetric(
              horizontal: _isTranslatingItems ? 0 : 10,
            ),
            decoration: _panelDecoration(
              color: translationEnabled
                  ? ShellStyles.accentTone(context).container
                  : _surfaceColor,
              borderColor: translationEnabled
                  ? ShellStyles.accentTone(context).border
                  : _strokeColor,
              radius: 14,
            ),
            child: _isTranslatingItems
                ? Center(
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppIcons.translate,
                        size: 15,
                        color: _effectiveItemsLanguage.isEmpty
                            ? _mutedColor
                            : translationEnabled
                            ? ShellStyles.accentTone(context).foreground
                            : _textColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        languageLabel,
                        style: TextStyle(
                          color: _effectiveItemsLanguage.isEmpty
                              ? _mutedColor
                              : translationEnabled
                              ? ShellStyles.accentTone(context).foreground
                              : _textColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: _panelDecoration(radius: 18),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 70,
                height: 58,
                child: ColoredBox(
                  color: _surfaceAltColor,
                  child: _isLoadingReceiptPreview
                      ? Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _accentColor,
                              ),
                            ),
                          ),
                        )
                      : hasPreview
                      ? Image.network(
                          _receiptPreviewUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _buildPhotoFallback(compact: true),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _accentColor,
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : _buildPhotoFallback(compact: true),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('transaction_receipt_photo_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.tr('transaction_receipt_photo_subtitle'),
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(AppIcons.chevronRight, size: 16, color: _mutedColor),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoFallback({bool compact = false}) {
    return Center(
      child: compact
          ? Icon(AppIcons.photo, size: 22, color: _mutedColor)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(AppIcons.photo, size: 30, color: _mutedColor),
                SizedBox(height: 10),
                Text(
                  context.tr('transaction_receipt_photo_title'),
                  style: TextStyle(
                    color: _mutedColor,
                    fontWeight: FontWeight.w600,
                  ),
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
        ? context.tr('transaction_warning_review_one_item')
        : context.tr(
            'transaction_warning_review_items',
            params: {'count': lineMismatchCount.toString()},
          );
    final parts = <String>[];
    if (lineMismatchCount > 0) {
      parts.add(lineText);
    }
    if (hasTotalMismatch) {
      parts.add(context.tr('transaction_warning_review_total'));
    }
    if (serverWarningCount > 0) {
      parts.add(
        serverWarningCount == 1
            ? context.tr('transaction_warning_check_one_detail')
            : context.tr(
                'transaction_warning_check_details',
                params: {'count': serverWarningCount.toString()},
              ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: _panelDecoration(
        color: _surfaceAltColor,
        borderColor: _strokeColor,
        radius: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: _warningColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(
                'transaction_warning_accepts_edits',
                params: {'details': parts.join(' / ')},
              ),
              style: TextStyle(
                color: _textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: _panelDecoration(radius: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(AppIcons.labels, size: 17, color: _mutedColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _labelsSummaryText(selectedLabels),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(AppIcons.chevronRight, size: 16, color: _mutedColor),
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
    _applyPickedOccurredDate(date);
  }

  Future<void> _pickOccurredTime() async {
    final base = _occurredAt ?? DateTime.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (selected == null || !mounted) return;
    _applyPickedOccurredTime(selected);
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
    final discountAmount = _itemDiscountValue(item);
    final hasDiscount = discountAmount > 0;
    final beforeDiscountAmount = _itemAmountBeforeDiscountValue(item);
    final displayName = ItemNameDisplayResolver.resolve(
      item: item,
      currentDescription: _itemDescription(item),
      translationEnabled:
          _showTranslatedItems && _effectiveItemsLanguage.isNotEmpty,
    );
    final currentName = displayName.primaryText;
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
    final convertedVisible =
        _displayCurrency.toUpperCase() != _currency.toUpperCase();

    return InkWell(
      onTap: _canEditTransaction ? () => _openItemEditor(item) : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: _strokeColor.withAlpha(180)))
              : null,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (hasDiscount && beforeDiscountAmount != null) ...[
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                context.tr(
                                  'transaction_was_amount',
                                  params: {
                                    'amount': _formatMoney(
                                      _currency,
                                      beforeDiscountAmount,
                                    ),
                                  },
                                ),
                                style: TextStyle(
                                  color: _mutedColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: _mutedColor,
                                ),
                              ),
                              Text(
                                context.tr(
                                  'transaction_saved_amount',
                                  params: {
                                    'amount': _formatMoney(
                                      _currency,
                                      discountAmount,
                                    ),
                                  },
                                ),
                                style: TextStyle(
                                  color: _successColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 7),
                        Text(
                          quantityLineParts.isEmpty
                              ? context.tr('transaction_missing_quantity_price')
                              : quantityLineParts.join(' / '),
                          style: TextStyle(
                            color: _mutedColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatMoney(_currency, sourceAmount),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                      if (convertedVisible) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$displayCurrencyLabel ${displayAmount.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: _mutedColor, fontSize: 11.5),
                        ),
                      ],
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
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: catTags
                    .map((tag) => _buildCategoryBadge(tag: tag))
                    .toList(growable: false),
              ),
              if (mismatch != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lineReviewMessage(mismatch),
                  style: TextStyle(
                    color: _warningColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge({required _CategoryTagData tag}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tag.tone.container,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tag.tone.border),
      ),
      child: Text(
        tag.label.trim(),
        style: TextStyle(
          color: tag.tone.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAddItemButton() {
    return InkWell(
      onTap: !_canEditTransaction ? null : _addItemAndOpenEditor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: _panelDecoration(
          color: Colors.transparent,
          borderColor: _strokeColor,
          radius: 16,
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.add, size: 16, color: _textColor),
              const SizedBox(width: 8),
              Text(
                context.tr('transaction_add_item'),
                style: TextStyle(
                  color: _textColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
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
    final totalSavings = _totalSavingsValue();
    final hasSavings = totalSavings > 0;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: _surfaceColor,
          border: Border(top: BorderSide(color: _strokeColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (totalMismatch != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _totalReviewMessage(totalMismatch),
                    style: TextStyle(
                      color: _warningColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('transaction_receipt_total_label'),
                            style: TextStyle(
                              color: _mutedColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              Text(
                                _formatMoney(_currency, sourceTotal),
                                style: TextStyle(
                                  color: _textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (_displayCurrency.toUpperCase() !=
                                  _currency.toUpperCase())
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    _formatMoney(
                                      _displayCurrency,
                                      displayTotal,
                                    ),
                                    style: TextStyle(
                                      color: _mutedColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (hasSavings) ...[
                            const SizedBox(height: 2),
                            Text(
                              context.tr(
                                'transaction_saved_amount',
                                params: {
                                  'amount': _formatMoney(
                                    _currency,
                                    totalSavings,
                                  ),
                                },
                              ),
                              style: TextStyle(
                                color: _successColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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

class _CategoryTagData {
  const _CategoryTagData({required this.label, required this.tone});

  final String label;
  final SemanticColorTone tone;
}
