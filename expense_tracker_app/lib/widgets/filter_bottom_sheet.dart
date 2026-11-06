import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/localized_dates.dart';
import '../core/period_filter.dart';
import '../core/receipt_filter_formatting.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({
    super.key,
    required this.selectedPeriod,
    this.selectedCustomRange,
    this.selectedCategoryIds,
    this.selectedSubcategoryIds,
    this.selectedLabelIds,
    this.enableReceiptFilters = false,
    this.selectedMinAmount,
    this.selectedMaxAmount,
    this.selectedCurrency,
    this.selectedSource,
    this.selectedStatus,
  });

  final String selectedPeriod;
  final PeriodDateRange? selectedCustomRange;
  final List<String>? selectedCategoryIds;
  final List<String>? selectedSubcategoryIds;
  final List<String>? selectedLabelIds;
  final bool enableReceiptFilters;
  final String? selectedMinAmount;
  final String? selectedMaxAmount;
  final String? selectedCurrency;
  final String? selectedSource;
  final String? selectedStatus;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String selectedPeriod,
    PeriodDateRange? selectedCustomRange,
    List<String>? selectedCategoryIds,
    List<String>? selectedSubcategoryIds,
    List<String>? selectedLabelIds,
    bool enableReceiptFilters = false,
    String? selectedMinAmount,
    String? selectedMaxAmount,
    String? selectedCurrency,
    String? selectedSource,
    String? selectedStatus,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FilterBottomSheet(
        selectedPeriod: selectedPeriod,
        selectedCustomRange: selectedCustomRange,
        selectedCategoryIds: selectedCategoryIds,
        selectedSubcategoryIds: selectedSubcategoryIds,
        selectedLabelIds: selectedLabelIds,
        enableReceiptFilters: enableReceiptFilters,
        selectedMinAmount: selectedMinAmount,
        selectedMaxAmount: selectedMaxAmount,
        selectedCurrency: selectedCurrency,
        selectedSource: selectedSource,
        selectedStatus: selectedStatus,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _selectedPeriod;
  PeriodDateRange? _selectedCustomRange;
  late Set<String> _selectedCategoryIds;
  late Set<String> _selectedSubcategoryIds;
  late Set<String> _selectedLabelIds;
  List<dynamic> _categories = [];
  List<dynamic> _labels = [];
  bool _loadingCats = true;
  final _amountFormKey = GlobalKey<FormState>();
  late final TextEditingController _minAmount;
  late final TextEditingController _maxAmount;
  String? _currency;
  String? _source;
  String? _status;
  late final List<String> _currencyCodes;

  @override
  void initState() {
    super.initState();
    _minAmount = TextEditingController(text: widget.selectedMinAmount);
    _maxAmount = TextEditingController(text: widget.selectedMaxAmount);
    _currency = widget.selectedCurrency;
    _source = widget.selectedSource;
    _status = widget.selectedStatus;
    _currencyCodes = {
      ...CurrencyService().getAll().map((currency) => currency.code),
      ?_currency,
    }.toList()..sort();
    _selectedPeriod = widget.selectedPeriod;
    _selectedCustomRange = widget.selectedCustomRange;
    if (_selectedPeriod == PeriodFilter.custom &&
        !PeriodFilter.isValidCustomRange(_selectedCustomRange)) {
      _selectedPeriod = PeriodFilter.last3Months;
      _selectedCustomRange = null;
    }
    _selectedCategoryIds = Set<String>.from(widget.selectedCategoryIds ?? []);
    _selectedSubcategoryIds = Set<String>.from(
      widget.selectedSubcategoryIds ?? [],
    );
    _selectedLabelIds = Set<String>.from(widget.selectedLabelIds ?? []);
    _loadData();
  }

  @override
  void dispose() {
    _minAmount.dispose();
    _maxAmount.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final cats = await ApiClient.listCategories();
      List<dynamic> labels = [];
      try {
        labels = await ApiClient.listLabels();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _labels = labels;
        _pruneUnavailableSubcategories();
        _loadingCats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCats = false);
    }
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedCategoryIds.isNotEmpty) count += 1;
    if (_selectedSubcategoryIds.isNotEmpty) count += 1;
    if (_selectedLabelIds.isNotEmpty) count += 1;
    if (widget.enableReceiptFilters) {
      if (_currency != null) count++;
      if (_minAmount.text.trim().isNotEmpty ||
          _maxAmount.text.trim().isNotEmpty) {
        count++;
      }
      if (_source != null) count++;
      if (_status != null) count++;
    }
    return count;
  }

  String _localizedCategoryName(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  List<dynamic> get _topLevelCategories {
    return _categories.where((c) => c['parent_id'] == null).toList()..sort(
      (a, b) => _localizedCategoryName(a as Map<String, dynamic>)
          .toLowerCase()
          .compareTo(
            _localizedCategoryName(b as Map<String, dynamic>).toLowerCase(),
          ),
    );
  }

  List<dynamic> get _availableSubcategories {
    if (_selectedCategoryIds.isEmpty) return [];
    return _categories.where((c) {
      final parentId = c['parent_id'] as String?;
      return parentId != null && _selectedCategoryIds.contains(parentId);
    }).toList()..sort(
      (a, b) => _localizedCategoryName(a as Map<String, dynamic>)
          .toLowerCase()
          .compareTo(
            _localizedCategoryName(b as Map<String, dynamic>).toLowerCase(),
          ),
    );
  }

  void _pruneUnavailableSubcategories() {
    final availableIds = _availableSubcategories
        .map((c) => c['id'] as String)
        .toSet();
    _selectedSubcategoryIds.removeWhere((id) => !availableIds.contains(id));
  }

  void _clearAll() {
    setState(() {
      _selectedCategoryIds.clear();
      _selectedSubcategoryIds.clear();
      _selectedLabelIds.clear();
      _amountFormKey.currentState?.reset();
      _minAmount.clear();
      _maxAmount.clear();
      _currency = null;
      _source = null;
      _status = null;
    });
  }

  void _apply() {
    if (widget.enableReceiptFilters &&
        !_amountFormKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(context, {
      'period': _selectedPeriod,
      'custom_range': _selectedCustomRange,
      'category_ids': _selectedCategoryIds.toList(),
      'subcategory_ids': _selectedSubcategoryIds.toList(),
      'label_ids': _selectedLabelIds.toList(),
      if (widget.enableReceiptFilters) ...{
        'min_amount': _normalizedAmount(_minAmount.text),
        'max_amount': _normalizedAmount(_maxAmount.text),
        'currency': _currency,
        'source': _source,
        'status': _status,
      },
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial =
        _selectedCustomRange ??
        PeriodFilter.getRange(
          _selectedPeriod == PeriodFilter.allTime
              ? PeriodFilter.last30Days
              : _selectedPeriod,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: DateTimeRange(start: initial.start!, end: initial.end!),
      helpText: context.tr('period_custom'),
      builder: (dialogContext, child) {
        final theme = Theme.of(dialogContext);
        final picker =
            MediaQuery.sizeOf(dialogContext).width < 480 &&
                ShellStyles.textScale(dialogContext) > 1
            ? Theme(
                data: theme.copyWith(
                  datePickerTheme: theme.datePickerTheme.copyWith(
                    rangePickerHeaderHeadlineStyle: theme.textTheme.bodySmall
                        ?.copyWith(letterSpacing: 0),
                  ),
                ),
                child: child!,
              )
            : child!;
        return ShellStyles.clampOverlayScale(dialogContext, picker);
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedPeriod = PeriodFilter.custom;
      _selectedCustomRange = PeriodDateRange(
        start: picked.start,
        end: picked.end,
      );
    });
  }

  Future<void> _openSubcategoryPicker() async {
    final available = _availableSubcategories;
    if (available.isEmpty) return;

    final initialSelected = Set<String>.from(_selectedSubcategoryIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String search = '';
        final selected = Set<String>.from(initialSelected);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = available.where((subcat) {
              final name = _localizedCategoryName(
                subcat as Map<String, dynamic>,
              ).toLowerCase();
              return name.contains(search.toLowerCase());
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('filters_select_subcategories'),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.tr('filters_search_subcategory'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setModalState(() => search = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                context.tr('filters_no_matching_subcategories'),
                                style: TextStyle(
                                  color: ShellStyles.textMuted(context),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final subcat = filtered[index];
                                final id = subcat['id'] as String;
                                final name = _localizedCategoryName(
                                  subcat as Map<String, dynamic>,
                                );
                                final checked = selected.contains(id);
                                return CheckboxListTile(
                                  value: checked,
                                  title: Text(name),
                                  onChanged: (value) {
                                    setModalState(() {
                                      if (value == true) {
                                        selected.add(id);
                                      } else {
                                        selected.remove(id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(context.tr('common_cancel')),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: Text(context.tr('common_apply')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;
    setState(() {
      _selectedSubcategoryIds = result;
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.48,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ShellStyles.border(context),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _activeFilterCount > 0
                        ? context.tr(
                            'filters_title_with_count',
                            params: {
                              'count': MaterialLocalizations.of(
                                context,
                              ).formatDecimal(_activeFilterCount),
                            },
                          )
                        : context.tr('filters_title'),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: context.tr('common_cancel'),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section(
                      icon: Icons.calendar_today_outlined,
                      title: context.tr('filters_period'),
                      children: [
                        _buildPeriodChips(),
                        if (_selectedPeriod == PeriodFilter.custom &&
                            _selectedCustomRange != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _pickCustomRange,
                            icon: const Icon(Icons.edit_calendar_outlined),
                            label: Text(
                              formatLocalizedDateRange(
                                context,
                                _selectedCustomRange!.start!,
                                _selectedCustomRange!.end!,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.enableReceiptFilters) ...[
                      const SizedBox(height: 12),
                      _buildReceiptFilters(),
                    ],
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.category_outlined,
                      title: context.tr('filters_category'),
                      children: [_buildCategoryChips()],
                    ),
                    const SizedBox(height: 12),
                    _section(
                      icon: Icons.account_tree_outlined,
                      title: context.tr('filters_subcategory'),
                      children: [_buildSubcategoryPicker()],
                    ),
                    if (_labels.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _section(
                        icon: Icons.label_outline,
                        title: context.tr('filters_labels'),
                        children: [_buildLabelChips()],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ShellStyles.surface(context),
              border: Border(
                top: BorderSide(color: ShellStyles.border(context)),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _clearAll,
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: Text(context.tr('common_clear_filters')),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          context.tr('common_cancel'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 20),
                    label: Text(context.tr('common_apply')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _surface(Widget child) => Container(
    decoration: ShellStyles.cardDecoration(
      context,
      radius: 18,
      withShadow: false,
    ),
    padding: const EdgeInsets.all(16),
    child: child,
  );

  Widget _section({
    Key? key,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => KeyedSubtree(
    key: key,
    child: _surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(icon: icon, title: title),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );

  String? _normalizedAmount(String value) =>
      normalizeReceiptFilterAmount(value);

  String? _validateAmount(String? value) {
    final text = _normalizedAmount(value ?? '');
    if (text != null && !RegExp(r'^-?\d{1,10}(\.\d{1,2})?$').hasMatch(text)) {
      return context.tr('filters_invalid_amount');
    }
    return null;
  }

  Widget _choice({
    required String id,
    required String label,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) => KeyedSubtree(
    key: ValueKey(id),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$id:${value ?? ''}'),
      initialValue: value ?? '',
      isExpanded: true,
      decoration: _inputDecoration(label),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      validator: validator,
      onChanged: (selected) =>
          setState(() => onChanged(selected == '' ? null : selected)),
    ),
  );

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: ShellStyles.surfaceAlt(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    errorMaxLines: 3,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: ShellStyles.border(context)),
    ),
  );

  Widget _amountField({required bool minimum}) => TextFormField(
    key: ValueKey(minimum ? 'filter-min-amount' : 'filter-max-amount'),
    controller: minimum ? _minAmount : _maxAmount,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: _inputDecoration(
      context.tr(minimum ? 'filters_min_amount' : 'filters_max_amount'),
    ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
    validator: (value) {
      final error = _validateAmount(value);
      if (minimum || error != null) return error;
      final min = num.tryParse(_normalizedAmount(_minAmount.text) ?? '');
      final max = num.tryParse(_normalizedAmount(value ?? '') ?? '');
      return min != null && max != null && min > max
          ? context.tr('filters_invalid_range')
          : null;
    },
    onChanged: (_) => setState(() {}),
  );

  Widget _buildReceiptFilters() => Form(
    key: _amountFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          key: const ValueKey('filter-amount-section'),
          icon: Icons.payments_outlined,
          title: context.tr('filters_amount'),
          children: [
            _choice(
              id: 'filter-currency',
              label: context.tr('filters_currency'),
              value: _currency,
              options: {
                '': context.tr('filters_all_currencies'),
                for (final code in _currencyCodes) code: code,
              },
              validator: (_) =>
                  _currency == null &&
                      (_normalizedAmount(_minAmount.text) != null ||
                          _normalizedAmount(_maxAmount.text) != null)
                  ? context.tr('filters_choose_currency')
                  : null,
              onChanged: (value) => _currency = value,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 320 &&
                      ShellStyles.textScale(context) <= 1.2
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _amountField(minimum: true)),
                        const SizedBox(width: 12),
                        Expanded(child: _amountField(minimum: false)),
                      ],
                    )
                  : Column(
                      children: [
                        _amountField(minimum: true),
                        const SizedBox(height: 14),
                        _amountField(minimum: false),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('filters_amount_hint'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _surface(
          Column(
            children: [
              _choice(
                id: 'filter-source',
                label: context.tr('filters_source'),
                value: _source,
                options: {
                  '': context.tr('filters_any_source'),
                  'RECEIPT': context.tr('filters_scanned'),
                  'MANUAL': context.tr('filters_manual'),
                  'IMPORTED': context.tr('filters_imported'),
                },
                onChanged: (value) => _source = value,
              ),
              const SizedBox(height: 16),
              _choice(
                id: 'filter-status',
                label: context.tr('filters_status'),
                value: _status,
                options: {
                  '': context.tr('filters_any_status'),
                  'DRAFT': context.tr('receipts_draft'),
                  'CONFIRMED': context.tr('filters_confirmed'),
                },
                onChanged: (value) => _status = value,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildSectionTitle({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ShellStyles.textPrimary(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PeriodFilter.values.map((period) {
        final isSelected = _selectedPeriod == period;
        return FilterChip(
          label: Text(context.tr(PeriodFilter.localizationKey(period))),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) {
            if (period == PeriodFilter.custom) {
              _pickCustomRange();
              return;
            }
            setState(() {
              _selectedPeriod = period;
              _selectedCustomRange = null;
            });
          },
          selectedColor: ShellStyles.textPrimary(context).withAlpha(18),
          backgroundColor: ShellStyles.surface(context),
          side: BorderSide(
            color: isSelected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.border(context),
          ),
          labelStyle: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryChips() {
    if (_loadingCats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return Text(
        context.tr('filters_no_categories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _topLevelCategories.map((cat) {
        final id = cat['id'] as String;
        final name = _localizedCategoryName(cat as Map<String, dynamic>);
        final isSelected = _selectedCategoryIds.contains(id);
        final tone = ShellStyles.categoryTone(
          context,
          code: cat['code']?.toString(),
          parentCode: cat['parent_category_code']?.toString(),
          name: cat['name']?.toString(),
          rawHex: cat['color']?.toString(),
        );

        return FilterChip(
          label: Text(name),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedCategoryIds.add(id);
              } else {
                _selectedCategoryIds.remove(id);
              }
              _pruneUnavailableSubcategories();
            });
          },
          selectedColor: tone.containerStrong,
          backgroundColor: tone.container,
          side: BorderSide(color: isSelected ? tone.base : tone.border),
          labelStyle: TextStyle(
            color: tone.foreground,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubcategoryPicker() {
    if (_loadingCats) {
      return const SizedBox.shrink();
    }
    if (_selectedCategoryIds.isEmpty) {
      return Text(
        context.tr('filters_select_categories_for_subcategories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }
    final available = _availableSubcategories;
    if (available.isEmpty) {
      return Text(
        context.tr('filters_no_subcategories_for_categories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _openSubcategoryPicker,
          style: OutlinedButton.styleFrom(
            foregroundColor: ShellStyles.textPrimary(context),
            backgroundColor: ShellStyles.surface(context),
            side: BorderSide(color: ShellStyles.border(context)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(
            _selectedSubcategoryIds.isEmpty
                ? context.tr('filters_select_subcategories')
                : context.tr(
                    'filters_selected_count',
                    params: {
                      'count': _selectedSubcategoryIds.length.toString(),
                    },
                  ),
          ),
        ),
        if (_selectedSubcategoryIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available
                .where(
                  (subcat) => _selectedSubcategoryIds.contains(subcat['id']),
                )
                .map((subcat) {
                  final id = subcat['id'] as String;
                  final name = _localizedCategoryName(
                    subcat as Map<String, dynamic>,
                  );
                  return Chip(
                    label: Text(name),
                    onDeleted: () {
                      setState(() => _selectedSubcategoryIds.remove(id));
                    },
                  );
                })
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLabelChips() {
    if (_labels.isEmpty) {
      return Text(
        context.tr('filters_no_labels'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }

    final sortedLabels = [..._labels]
      ..sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sortedLabels.map((raw) {
        final label = raw as Map<String, dynamic>;
        final id = label['id']?.toString() ?? '';
        final name = label['name']?.toString() ?? context.tr('labels_title');
        final isSelected = _selectedLabelIds.contains(id);
        final tone = ShellStyles.labelTone(
          context,
          labelId: id,
          name: name,
          rawHex: label['color']?.toString(),
        );
        return FilterChip(
          label: Text(name),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedLabelIds.add(id);
              } else {
                _selectedLabelIds.remove(id);
              }
            });
          },
          selectedColor: tone.containerStrong,
          backgroundColor: tone.container,
          side: BorderSide(color: isSelected ? tone.base : tone.border),
          labelStyle: TextStyle(
            color: tone.foreground,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }
}
