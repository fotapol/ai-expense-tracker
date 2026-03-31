import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/planning_logic.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class BudgetCalculatorScreen extends StatefulWidget {
  const BudgetCalculatorScreen({super.key});

  @override
  State<BudgetCalculatorScreen> createState() => _BudgetCalculatorScreenState();
}

class _BudgetCalculatorScreenState extends State<BudgetCalculatorScreen> {
  final TextEditingController _incomeController = TextEditingController();
  final Map<String, TextEditingController> _limitControllers =
      <String, TextEditingController>{};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String _currency = 'EUR';
  double _totalSpent = 0;
  List<Map<String, dynamic>> _topLevelCategories = <Map<String, dynamic>>[];
  Map<String, double> _spentByCode = <String, double>{};
  Set<String> _selectedCategoryIds = <String>{};

  DateTime get _currentMonthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _incomeController.dispose();
    for (final controller in _limitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final budgetRaw = await ApiClient.getBudgetPlan();
      final budgetPlan = BudgetPlanRecord.fromJson(budgetRaw);
      final categoriesRaw = await ApiClient.listCategories();
      final categories = categoriesRaw
          .whereType<Map<String, dynamic>>()
          .where(
            (category) =>
                category['parent_id'] == null &&
                category['is_disabled'] != true,
          )
          .toList();
      final categoryById = <String, Map<String, dynamic>>{
        for (final category in categories)
          category['id']?.toString() ?? '': category,
      }..remove('');

      final summary = await ApiClient.getTransactionsSummary(
        fromDate: _currentMonthStart,
        targetCurrency: budgetPlan.currency,
      );

      final breakdown = summary['breakdown'] as List<dynamic>? ?? const [];
      final spentByCode = <String, double>{};
      for (final entry in breakdown.whereType<Map<String, dynamic>>()) {
        final code = entry['code']?.toString() ?? '';
        if (code.isEmpty) continue;
        spentByCode[code] = _parseDouble(entry['amount']);
      }

      final selectedIds = budgetPlan.categoryLimits
          .map((limit) => limit.categoryId)
          .where(categoryById.containsKey)
          .toSet();
      _replaceLimitControllers(
        selectedIds: selectedIds,
        initialValues: {
          for (final limit in budgetPlan.categoryLimits)
            if (categoryById.containsKey(limit.categoryId))
              limit.categoryId: limit.limitAmount,
        },
      );

      if (!mounted) return;
      setState(() {
        _currency = budgetPlan.currency;
        _topLevelCategories = categories;
        _spentByCode = spentByCode;
        _totalSpent = _parseDouble(summary['total_amount']);
        _selectedCategoryIds = selectedIds;
        _incomeController.text = budgetPlan.monthlyIncome == null
            ? ''
            : _formatEditableNumber(budgetPlan.monthlyIncome!);
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _replaceLimitControllers({
    required Set<String> selectedIds,
    required Map<String, double> initialValues,
  }) {
    for (final controller in _limitControllers.values) {
      controller.dispose();
    }
    _limitControllers
      ..clear()
      ..addEntries(
        selectedIds.map(
          (id) => MapEntry(
            id,
            TextEditingController(
              text: initialValues[id] == null
                  ? ''
                  : _formatEditableNumber(initialValues[id]!),
            ),
          ),
        ),
      );
  }

  Future<void> _addCategory() async {
    final available =
        _topLevelCategories.where((category) {
          final id = category['id']?.toString() ?? '';
          return id.isNotEmpty && !_selectedCategoryIds.contains(id);
        }).toList()..sort(
          (left, right) =>
              _localizedCategory(left).compareTo(_localizedCategory(right)),
        );

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('budget_all_categories_added'))),
      );
      return;
    }

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ShellStyles.surface(context),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('budget_add_category'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: available.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: ShellStyles.border(context), height: 1),
                    itemBuilder: (context, index) {
                      final category = available[index];
                      final id = category['id']?.toString() ?? '';
                      return ListTile(
                        title: Text(_localizedCategory(category)),
                        onTap: () => Navigator.of(sheetContext).pop(id),
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

    if (selectedId == null || selectedId.isEmpty) return;
    setState(() {
      _selectedCategoryIds = {..._selectedCategoryIds, selectedId};
      _limitControllers[selectedId] = TextEditingController();
    });
  }

  void _removeCategory(String categoryId) {
    setState(() {
      _selectedCategoryIds = Set<String>.from(_selectedCategoryIds)
        ..remove(categoryId);
      _limitControllers.remove(categoryId)?.dispose();
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final monthlyIncome = _parseOptionalAmount(_incomeController.text);
    if (_incomeController.text.trim().isNotEmpty && monthlyIncome == null) {
      _showMessage(context.tr('budget_invalid_amount'), isError: true);
      return;
    }

    final categoryLimits = <Map<String, dynamic>>[];
    for (final categoryId in _selectedCategoryIds) {
      final rawValue = _limitControllers[categoryId]?.text ?? '';
      if (rawValue.trim().isEmpty) continue;
      final parsed = _parseOptionalAmount(rawValue);
      if (parsed == null) {
        _showMessage(context.tr('budget_invalid_amount'), isError: true);
        return;
      }
      if (parsed <= 0) continue;
      categoryLimits.add(<String, dynamic>{
        'category_id': categoryId,
        'limit_amount': parsed,
      });
    }

    setState(() => _isSaving = true);
    try {
      await ApiClient.updateBudgetPlan(
        currency: _currency,
        monthlyIncome: monthlyIncome,
        categoryLimits: categoryLimits,
      );
      await _loadData(showLoader: false);
      if (!mounted) return;
      _showMessage(context.tr('budget_saved'));
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? ShellColors.softRed : null,
      ),
    );
  }

  String _localizedCategory(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  List<BudgetCategoryProgress> _categoryProgresses() {
    final categoryById = <String, Map<String, dynamic>>{
      for (final category in _topLevelCategories)
        category['id']?.toString() ?? '': category,
    }..remove('');
    final categories = _selectedCategoryIds
        .map((id) => categoryById[id])
        .whereType<Map<String, dynamic>>()
        .map((category) {
          final id = category['id']?.toString() ?? '';
          final code = category['code']?.toString() ?? '';
          final spentAmount = _spentByCode[code] ?? 0;
          final limitAmount =
              _parseOptionalAmount(_limitControllers[id]?.text ?? '') ?? 0;
          return BudgetCategoryProgress(
            categoryId: id,
            categoryCode: code,
            categoryName: _localizedCategory(category),
            limitAmount: limitAmount,
            spentAmount: spentAmount,
          );
        })
        .toList();
    categories.sort(
      (left, right) => left.categoryName.compareTo(right.categoryName),
    );
    return categories;
  }

  String _formatEditableNumber(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  double _parseDouble(Object? value) {
    if (value == null) return 0;
    return double.tryParse(value.toString()) ?? 0;
  }

  double? _parseOptionalAmount(String text) {
    final normalized = text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String _formatCurrency(double amount, {bool allowNegative = true}) {
    final symbol = CurrencyDisplay.symbolForCode(_currency);
    final absolute = amount.abs();
    final decimals = absolute % 1 == 0 ? 0 : 2;
    final formatted = absolute.toStringAsFixed(decimals);
    final prefix = symbol == _currency
        ? '${_currency.toUpperCase()} '
        : '$symbol ';
    final sign = amount < 0 && allowNegative ? '-' : '';
    return '$sign$prefix$formatted';
  }

  Widget _buildSummaryCard(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? ShellStyles.textPrimary(context),
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(
    BudgetOverview overview,
    List<BudgetCategoryProgress> categories,
  ) {
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ShellStyles.border(context)),
        ),
        child: Text(
          context.tr('budget_empty_state'),
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 13,
            height: 1.35,
          ),
        ),
      );
    }

    final hasExceededCategory = categories.any(
      (category) => category.isExceeded,
    );
    if (overview.isOverBudget || hasExceededCategory) {
      final overAmount = overview.remaining.abs();
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShellColors.softRed.withAlpha(16),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ShellColors.softRed.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('budget_status_over_title'),
              style: const TextStyle(
                color: ShellColors.softRed,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'budget_status_over_body',
                params: {'amount': _formatCurrency(overAmount)},
              ),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShellColors.softGreen.withAlpha(16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShellColors.softGreen.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('budget_status_on_track_title'),
            style: const TextStyle(
              color: ShellColors.softGreen,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'budget_status_on_track_body',
              params: {'amount': _formatCurrency(overview.savingsGoal)},
            ),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(BudgetCategoryProgress category) {
    final controller = _limitControllers[category.categoryId]!;
    final borderColor = category.isExceeded
        ? ShellColors.softRed.withAlpha(90)
        : ShellStyles.border(context);
    final progressColor = category.isExceeded
        ? ShellColors.softRed
        : ShellStyles.textPrimary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: ShellStyles.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.categoryName,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatCurrency(category.spentAmount)} / ${_formatCurrency(category.limitAmount)}',
                style: TextStyle(
                  color: category.isExceeded
                      ? ShellColors.softRed
                      : ShellStyles.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: () => _removeCategory(category.categoryId),
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: ShellStyles.textMuted(context),
                ),
                tooltip: context.tr('budget_remove_category'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: category.limitAmount <= 0 ? 0 : category.progress,
              minHeight: 8,
              backgroundColor: ShellStyles.surfaceAlt(context),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              category.isExceeded
                  ? context.tr(
                      'budget_category_exceeded',
                      params: {
                        'amount': _formatCurrency(
                          category.spentAmount - category.limitAmount,
                        ),
                      },
                    )
                  : context.tr(
                      'budget_category_remaining',
                      params: {
                        'amount': _formatCurrency(
                          category.remainingAmount.clamp(0, double.infinity),
                        ),
                      },
                    ),
              style: TextStyle(
                color: category.isExceeded
                    ? ShellColors.softRed
                    : ShellStyles.textMuted(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('budget_limit_label'),
              prefixText: '${CurrencyDisplay.symbolForCode(_currency)} ',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categoryProgresses();
    final overview = buildBudgetOverview(
      monthlyIncome: _parseOptionalAmount(_incomeController.text) ?? 0,
      categories: categories,
      totalSpent: _totalSpent,
    );

    return SettingsDetailScaffold(
      title: context.tr('tools_budget_calculator'),
      body: _isLoading
          ? const SafeArea(
              top: false,
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
          ? SafeArea(
              top: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ShellStyles.textPrimary(context)),
                  ),
                ),
              ),
    final bottomPadding = MediaQuery.of(context).padding.bottom + 32;
            )
          : SafeArea(
              top: false,
              child: RefreshIndicator(
                onRefresh: () => _loadData(showLoader: false),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                  children: [
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('budget_income_label'),
                    ),
                    const SizedBox(height: 8),
                    SettingsDetailCard(
                      child: TextField(
                        controller: _incomeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          prefixText:
                              '${CurrencyDisplay.symbolForCode(_currency)} ',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _buildSummaryCard(
                                context.tr('budget_total_budget'),
                                _formatCurrency(overview.totalBudget),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildSummaryCard(
                                context.tr('budget_total_spent'),
                                _formatCurrency(overview.totalSpent),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildSummaryCard(
                                context.tr('budget_remaining'),
                                _formatCurrency(overview.remaining),
                                valueColor: overview.remaining < 0
                                    ? ShellColors.softRed
                                    : ShellColors.softGreen,
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _buildSummaryCard(
                                context.tr('budget_savings_goal'),
                                _formatCurrency(overview.savingsGoal),
                                valueColor: ShellColors.softGreen,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ShellStyles.sectionLabel(
                            context,
                            context.tr('budget_category_budgets'),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addCategory,
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(context.tr('budget_add_category')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (categories.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: ShellStyles.cardDecoration(
                          context,
                          radius: 18,
                          withShadow: false,
                        ),
                        child: Text(
                          context.tr('budget_empty_state'),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    else
                      ...categories.map((category) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildCategoryCard(category),
                        );
                      }),
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildStatusBanner(overview, categories),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: ShellStyles.textPrimary(context),
                          foregroundColor: ShellStyles.surface(context),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(context.tr('budget_save_action')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
