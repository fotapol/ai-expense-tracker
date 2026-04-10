import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/auto_refresh_state_mixin.dart';
import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../core/period_filter.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'receipt_upload_screen.dart';
import 'transaction_edit_screen.dart';

class ReceiptsTab extends StatefulWidget {
  final bool showTopBar;
  final bool includeTopSafeArea;

  const ReceiptsTab({
    super.key,
    this.showTopBar = true,
    this.includeTopSafeArea = true,
  });

  @override
  State<ReceiptsTab> createState() => _ReceiptsTabState();
}

class _ReceiptsTabState extends State<ReceiptsTab>
    with WidgetsBindingObserver, AutoRefreshStateMixin<ReceiptsTab> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _transactions = [];
  bool _hasAnyReceipts = false;
  String _preferredCurrency = 'EUR';
  String _selectedPeriod = PeriodFilter.allTime;
  String _merchantSearch = '';
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];
  List<String> _selectedLabelIds = [];
  final TextEditingController _searchController = TextEditingController();
  Map<String, Map<String, dynamic>> _categoriesById = {};
  bool _isFetchingTransactions = false;

  bool get _hasScopedFilters =>
      _selectedPeriod != PeriodFilter.allTime ||
      _merchantSearch.isNotEmpty ||
      _selectedCategoryIds.isNotEmpty ||
      _selectedSubcategoryIds.isNotEmpty ||
      _selectedLabelIds.isNotEmpty;

  int get _activeFilterCount {
    var count = 0;
    if (_selectedPeriod != PeriodFilter.allTime) count++;
    if (_merchantSearch.isNotEmpty) count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    if (_selectedSubcategoryIds.isNotEmpty) count++;
    if (_selectedLabelIds.isNotEmpty) count++;
    return count;
  }

  @override
  Duration get autoRefreshInterval => const Duration(minutes: 1);

  @override
  Future<void> performAutoRefresh() => _fetchTransactions(showLoader: false);

  @override
  void initState() {
    super.initState();
    _loadPreferredCurrency();
    _loadCategories();
    _fetchTransactions();
  }

  Future<void> _loadPreferredCurrency() async {
    try {
      final me = await ApiClient.getMe();
      final currency = me['default_currency']?.toString().trim();
      if (!mounted || currency == null || currency.isEmpty) return;
      setState(() => _preferredCurrency = currency.toUpperCase());
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiClient.listCategories();
      if (!mounted) return;
      setState(() {
        _categoriesById = {
          for (final raw in categories)
            if ((raw as Map<String, dynamic>)['id'] != null)
              raw['id'].toString(): raw,
        };
      });
    } catch (_) {}
  }

  Map<String, dynamic>? _findCategoryById(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return null;
    return _categoriesById[categoryId];
  }

  String? _categoryPathLabel(String? categoryId) {
    final category = _findCategoryById(categoryId);
    if (category == null) return null;
    final childName = localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
    if (childName.isEmpty) return null;
    final parentId = category['parent_id']?.toString();
    if (parentId == null || parentId.isEmpty) {
      return childName;
    }
    final parent = _findCategoryById(parentId);
    final parentName = localizeCategoryByCode(
      context,
      code: parent?['code']?.toString(),
      fallbackName: parent?['name']?.toString(),
    );
    if (parentName.isEmpty) {
      return childName;
    }
    return '$parentName • $childName';
  }

  Color _parseHexColor(String? raw, Color fallback) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return fallback;

    var hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    if (hex.length != 8) return fallback;

    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
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

  double _displayAmountOf(Map<String, dynamic> tx) {
    final raw = tx['display_amount_total'] ?? tx['amount_total'] ?? 0;
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _displayCurrencyOf(Map<String, dynamic> tx) {
    final hasConvertedValue = tx['display_amount_total'] != null;
    final raw = hasConvertedValue
        ? (tx['display_currency'] ?? tx['currency'] ?? _preferredCurrency)
        : (tx['currency'] ?? _preferredCurrency);
    return raw.toString().toUpperCase();
  }

  Future<void> _fetchTransactions({bool showLoader = true}) async {
    if (_isFetchingTransactions) return;
    _isFetchingTransactions = true;
    if (!mounted) {
      _isFetchingTransactions = false;
      return;
    }
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final startDate = PeriodFilter.getStartDate(_selectedPeriod);
      final searchText = _searchController.text.trim();
      final data = await ApiClient.listTransactions(
        fromDate: startDate,
        merchantNameSearch: searchText.isNotEmpty
            ? searchText
            : _merchantSearch.isNotEmpty
            ? _merchantSearch
            : null,
        categoryIds: _selectedCategoryIds.isNotEmpty
            ? _selectedCategoryIds
            : null,
        subcategoryIds: _selectedSubcategoryIds.isNotEmpty
            ? _selectedSubcategoryIds
            : null,
        labelIds: _selectedLabelIds.isNotEmpty ? _selectedLabelIds : null,
      );
      var hasAnyReceipts = _hasAnyReceipts;
      if (data.isNotEmpty) {
        hasAnyReceipts = true;
      } else {
        final baseline = await ApiClient.listTransactions();
        hasAnyReceipts = baseline.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _transactions = data;
        _hasAnyReceipts = hasAnyReceipts;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      if (!mounted) return;
      if (showLoader || _transactions.isEmpty) {
        setState(() {
          _error = friendlyLaunchErrorMessage(
            e,
            fallback:
                'Your history could not load right now. Please try again.',
          );
          _isLoading = false;
        });
      }
    } finally {
      _isFetchingTransactions = false;
    }
  }

  Future<void> _clearAllFilters() async {
    _searchController.clear();
    setState(() {
      _merchantSearch = '';
      _selectedPeriod = PeriodFilter.allTime;
      _selectedCategoryIds = <String>[];
      _selectedSubcategoryIds = <String>[];
      _selectedLabelIds = <String>[];
    });
    await _fetchTransactions();
  }

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _selectedPeriod,
      selectedCategoryIds: _selectedCategoryIds,
      selectedSubcategoryIds: _selectedSubcategoryIds,
      selectedLabelIds: _selectedLabelIds,
    );

    if (result != null) {
      setState(() {
        _selectedPeriod = result['period'] as String;
        _selectedCategoryIds = List<String>.from(result['category_ids'] ?? []);
        _selectedSubcategoryIds = List<String>.from(
          result['subcategory_ids'] ?? [],
        );
        _selectedLabelIds = List<String>.from(result['label_ids'] ?? []);
      });
      _fetchTransactions();
    }
  }

  Future<void> _deleteTransaction(Map<String, dynamic> tx) async {
    final receiptId = tx['receipt_id'] as String?;
    final transactionId = tx['id']?.toString();
    final source = tx['source']?.toString().toUpperCase();
    final isManual = source == 'MANUAL' || receiptId == null;
    final missingManualIdMessage = context.tr(
      'manual_transaction_delete_missing_id',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('receipts_delete_title')),
        content: Text(context.tr('receipts_delete_confirm')),
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

    if (confirmed == true) {
      try {
        if (isManual) {
          if (transactionId == null || transactionId.isEmpty) {
            throw Exception(missingManualIdMessage);
          }
          await ApiClient.deleteTransaction(transactionId);
        } else {
          await ApiClient.deleteReceipt(receiptId);
        }
        _fetchTransactions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isManual
                    ? context.tr('manual_transaction_deleted')
                    : context.tr('receipts_deleted'),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyLaunchErrorMessage(
                  e,
                  fallback: 'We could not remove that entry. Please try again.',
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: widget.includeTopSafeArea,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showTopBar) _buildTopBar(),
          if (_hasScopedFilters) _buildActiveFilterChips(),
          Expanded(child: _buildTransactionList()),
          _buildBottomSummary(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ShellStyles.scaled(context, 16, min: 14, max: 18),
        ShellStyles.scaled(context, 12, min: 10, max: 14),
        ShellStyles.scaled(context, 16, min: 14, max: 18),
        ShellStyles.scaled(context, 12, min: 10, max: 14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: ShellStyles.minTapTarget(context, base: 48),
              decoration: ShellStyles.cardDecoration(
                context,
                radius: ShellStyles.scaled(context, 18, min: 16, max: 20),
                color: ShellStyles.surface(context),
                withShadow: false,
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: context.tr('receipts_search_hint'),
                  prefixIcon: Icon(
                    Icons.search,
                    color: ShellStyles.textMuted(context),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: ShellStyles.scaled(context, 12, min: 10, max: 14),
                  ),
                ),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: ShellStyles.scaled(context, 14, min: 13, max: 15),
                ),
                onChanged: (value) {
                  if (value.trim().isEmpty && _merchantSearch.isNotEmpty) {
                    setState(() => _merchantSearch = '');
                    _fetchTransactions();
                  }
                },
                onSubmitted: (_) {
                  setState(
                    () => _merchantSearch = _searchController.text.trim(),
                  );
                  _fetchTransactions();
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          _buildTopActionButton(
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.tune),
            ),
            onTap: _openFilters,
            tooltip: context.tr('common_filter'),
          ),
          const SizedBox(width: 8),
          _buildTopActionButton(
            icon: const Icon(Icons.add_circle_outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransactionEditScreen.create(),
                ),
              ).then((_) => _fetchTransactions());
            },
            tooltip: context.tr('home_add_expense'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionButton({
    required Widget icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(
          ShellStyles.scaled(context, 16, min: 14, max: 18),
        ),
        onTap: onTap,
        child: Container(
          width: ShellStyles.minTapTarget(context),
          height: ShellStyles.minTapTarget(context),
          decoration: ShellStyles.cardDecoration(
            context,
            radius: ShellStyles.scaled(context, 16, min: 14, max: 18),
            color: ShellStyles.surface(context),
            withShadow: false,
          ),
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                size: ShellStyles.scaled(context, 20, min: 18, max: 22),
                color: ShellStyles.textPrimary(context),
              ),
              child: icon,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[
      if (_selectedPeriod != PeriodFilter.allTime)
        _buildFilterChip(
          context.tr(PeriodFilter.localizationKey(_selectedPeriod)),
          icon: Icons.calendar_today_outlined,
          onDeleted: () {
            setState(() => _selectedPeriod = PeriodFilter.allTime);
            _fetchTransactions();
          },
        ),
      if (_merchantSearch.isNotEmpty)
        _buildFilterChip(
          _merchantSearch,
          icon: Icons.storefront_outlined,
          onDeleted: () {
            _searchController.clear();
            setState(() => _merchantSearch = '');
            _fetchTransactions();
          },
        ),
      if (_selectedCategoryIds.isNotEmpty)
        _buildFilterChip(
          context.tr(
            'filters_categories_count',
            params: {'count': _selectedCategoryIds.length.toString()},
          ),
          icon: Icons.category_outlined,
          onDeleted: () {
            setState(() {
              _selectedCategoryIds.clear();
              _selectedSubcategoryIds.clear();
            });
            _fetchTransactions();
          },
        ),
      if (_selectedSubcategoryIds.isNotEmpty)
        _buildFilterChip(
          context.tr(
            'filters_subcategories_count',
            params: {'count': _selectedSubcategoryIds.length.toString()},
          ),
          icon: Icons.account_tree_outlined,
          onDeleted: () {
            setState(() => _selectedSubcategoryIds.clear());
            _fetchTransactions();
          },
        ),
      if (_selectedLabelIds.isNotEmpty)
        _buildFilterChip(
          context.tr(
            'filters_labels_count',
            params: {'count': _selectedLabelIds.length.toString()},
          ),
          icon: Icons.label_outline,
          onDeleted: () {
            setState(() => _selectedLabelIds.clear());
            _fetchTransactions();
          },
        ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ShellStyles.scaled(context, 16, min: 14, max: 18),
        0,
        ShellStyles.scaled(context, 16, min: 14, max: 18),
        ShellStyles.scaled(context, 12, min: 10, max: 14),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(
          ShellStyles.scaled(context, 14, min: 12, max: 16),
        ),
        decoration: ShellStyles.cardDecoration(
          context,
          radius: ShellStyles.scaled(context, 20, min: 18, max: 22),
          color: ShellStyles.surfaceAlt(context),
          withShadow: false,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('analytics_active_filters'),
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearAllFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: ShellStyles.textPrimary(context),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  child: Text(context.tr('analytics_clear_all_filters')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label, {
    required IconData icon,
    required VoidCallback onDeleted,
  }) {
    final tone = ShellStyles.accentTone(context);
    return InputChip(
      avatar: Icon(icon, size: 16, color: tone.foreground),
      label: Text(
        label,
        style: TextStyle(
          color: tone.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: tone.container,
      side: BorderSide(color: tone.border),
      deleteIconColor: tone.foreground,
      onDeleted: onDeleted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildTransactionList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Your history could not load right now.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _fetchTransactions,
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty && !_hasAnyReceipts) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(
            ShellStyles.scaled(context, 24, min: 20, max: 28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: ShellStyles.scaled(context, 72, min: 64, max: 80),
                height: ShellStyles.scaled(context, 72, min: 64, max: 80),
                alignment: Alignment.center,
                decoration: ShellStyles.iconBadgeDecoration(
                  context,
                  color: ShellStyles.surfaceAlt(context),
                  radius: ShellStyles.scaled(context, 22, min: 20, max: 24),
                ),
                child: Icon(
                  Icons.receipt_long,
                  size: ShellStyles.scaled(context, 32, min: 28, max: 36),
                  color: ShellStyles.textMuted(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('receipts_no_data'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: ShellStyles.scaled(context, 16, min: 15, max: 17),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan your first receipt to start building a history you can review and filter.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: ShellStyles.scaled(context, 13, min: 12, max: 14),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReceiptUploadScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan your first receipt'),
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(
            ShellStyles.scaled(context, 24, min: 20, max: 28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: ShellStyles.scaled(context, 72, min: 64, max: 80),
                height: ShellStyles.scaled(context, 72, min: 64, max: 80),
                alignment: Alignment.center,
                decoration: ShellStyles.iconBadgeDecoration(
                  context,
                  color: ShellStyles.surfaceAlt(context),
                  radius: ShellStyles.scaled(context, 22, min: 20, max: 24),
                ),
                child: Icon(
                  Icons.filter_alt_off_outlined,
                  size: ShellStyles.scaled(context, 30, min: 26, max: 34),
                  color: ShellStyles.textMuted(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No receipts match the current filters.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: ShellStyles.scaled(context, 16, min: 15, max: 17),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try another period, merchant search, or clear the active filters.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: ShellStyles.scaled(context, 13, min: 12, max: 14),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: _clearAllFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ),
      );
    }

    // Group transactions by month
    final localeTag = Localizations.localeOf(context).toString();
    final groupedTransactions = <String, List<dynamic>>{};
    for (var tx in _transactions) {
      final occurredAtStr = tx['occurred_at'] as String?;
      if (occurredAtStr == null) continue;
      final date = DateTime.tryParse(occurredAtStr);
      if (date == null) continue;
      final monthKey = DateFormat('MMMM yyyy', localeTag).format(date);
      groupedTransactions.putIfAbsent(monthKey, () => []).add(tx);
    }

    return RefreshIndicator(
      onRefresh: _fetchTransactions,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          ShellStyles.scaled(context, 16, min: 14, max: 18),
          ShellStyles.scaled(context, 4, min: 2, max: 8),
          ShellStyles.scaled(context, 16, min: 14, max: 18),
          ShellStyles.scaled(context, 16, min: 14, max: 18),
        ),
        itemCount: groupedTransactions.length,
        itemBuilder: (context, index) {
          final monthKey = groupedTransactions.keys.elementAt(index);
          final txsForMonth = groupedTransactions[monthKey]!;
          double monthTotal = 0;
          String monthCurrency = _preferredCurrency;
          for (var tx in txsForMonth) {
            final txMap = tx as Map<String, dynamic>;
            monthTotal += _displayAmountOf(txMap);
            monthCurrency = _displayCurrencyOf(txMap);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  bottom: ShellStyles.scaled(context, 10, min: 8, max: 12),
                  top: ShellStyles.scaled(context, 6, min: 4, max: 8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      monthKey,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontWeight: FontWeight.bold,
                        fontSize: ShellStyles.scaled(
                          context,
                          16,
                          min: 15,
                          max: 17,
                        ),
                      ),
                    ),
                    Text(
                      _formatMoney(monthCurrency, monthTotal),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: ShellStyles.scaled(
                          context,
                          13,
                          min: 12,
                          max: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...txsForMonth.map((tx) => _buildTransactionCard(tx)),
              SizedBox(
                height: ShellStyles.scaled(context, 12, min: 10, max: 14),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final storeName =
        tx['merchant_name'] ?? context.tr('receipts_unknown_store');
    final displayAmount = _displayAmountOf(tx);
    final displayCurrency = _displayCurrencyOf(tx);
    final sourceAmount =
        double.tryParse((tx['amount_total'] ?? '0').toString()) ?? 0;
    final sourceCurrency = (tx['currency'] ?? displayCurrency)
        .toString()
        .toUpperCase();
    final showOriginal =
        tx['display_amount_total'] != null &&
        (displayCurrency != sourceCurrency ||
            (displayAmount - sourceAmount).abs() > 0.00001);
    String formattedTime = '';
    final localeTag = Localizations.localeOf(context).toString();
    final occurredAtStr = tx['occurred_at'] as String?;
    if (occurredAtStr != null) {
      final date = DateTime.tryParse(occurredAtStr);
      if (date != null) {
        formattedTime = DateFormat('d MMM, HH:mm', localeTag).format(date);
      }
    }

    final txCategoryId = tx['category_id']?.toString();
    final txCategory = _findCategoryById(txCategoryId);
    final txCategoryNameRaw = tx['category_name']?.toString().trim();
    String? txCategoryLabel = _categoryPathLabel(txCategoryId);
    final categoryCode =
        txCategory?['code']?.toString() ?? tx['category_code']?.toString();
    final hasCategoryHint =
        (categoryCode != null && categoryCode.isNotEmpty) ||
        (txCategoryNameRaw != null && txCategoryNameRaw.isNotEmpty);
    if ((txCategoryLabel == null || txCategoryLabel.isEmpty) &&
        hasCategoryHint) {
      txCategoryLabel = localizeCategoryByCode(
        context,
        code: categoryCode,
        fallbackName: txCategoryNameRaw,
      );
    }
    final txCategoryCode = txCategory?['code']?.toString() ?? '';
    final categoryTone = hasCategoryHint
        ? ShellStyles.categoryTone(
            context,
            code: categoryCode,
            parentCode: txCategory?['parent_category_code']?.toString(),
            name: txCategoryLabel ?? txCategoryNameRaw,
          )
        : ShellStyles.accentTone(context);
    final iconColor = categoryTone.base;
    final iconData = hasCategoryHint
        ? CategoryStyle.iconForCode(categoryCode)
        : Icons.shopping_bag;

    final allLabelsRaw = tx['labels'];
    final allLabels = allLabelsRaw is List
        ? allLabelsRaw.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final pinnedLabels = allLabels
        .where((label) => label['is_pinned'] == true)
        .toList();
    final labelsToRender = (pinnedLabels.isNotEmpty ? pinnedLabels : allLabels)
        .take(3)
        .toList();
    final hasMetaRow =
        (txCategoryLabel != null && txCategoryLabel.isNotEmpty) ||
        labelsToRender.isNotEmpty;

    double receiptSavingsSource = 0;
    final itemsRaw = tx['items'];
    if (itemsRaw is List) {
      for (var rawItem in itemsRaw) {
        if (rawItem is Map<String, dynamic>) {
          var discountRaw =
              double.tryParse(rawItem['discount_amount']?.toString() ?? '0') ??
              0;
          if (discountRaw == 0) {
            final amountBefore =
                double.tryParse(
                  rawItem['amount_before_discount']?.toString() ?? '0',
                ) ??
                0;
            final amountLine =
                double.tryParse(rawItem['amount']?.toString() ?? '0') ?? 0;
            if (amountBefore > 0 &&
                amountLine > 0 &&
                amountBefore > amountLine) {
              discountRaw = amountBefore - amountLine;
            }
          }
          if (discountRaw > 0) {
            receiptSavingsSource += discountRaw;
          }
        }
      }
    }
    final rate = sourceAmount > 0 ? displayAmount / sourceAmount : 1.0;
    final receiptSavings = receiptSavingsSource * rate;

    return Dismissible(
      key: Key(tx['id'] ?? ''),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteTransaction(tx);
        return false; // We handle deletion ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: EdgeInsets.only(
          bottom: ShellStyles.scaled(context, 10, min: 8, max: 12),
        ),
        decoration: BoxDecoration(
          color: Colors.red.shade800,
          borderRadius: BorderRadius.circular(
            ShellStyles.scaled(context, 16, min: 14, max: 18),
          ),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  TransactionEditScreen(transactionId: tx['id']),
            ),
          ).then((_) => _fetchTransactions());
        },
        child: Container(
          margin: EdgeInsets.only(
            bottom: ShellStyles.scaled(context, 10, min: 8, max: 12),
          ),
          padding: EdgeInsets.all(
            ShellStyles.scaled(context, 14, min: 12, max: 16),
          ),
          decoration: ShellStyles.cardDecoration(
            context,
            radius: ShellStyles.scaled(context, 18, min: 16, max: 20),
            color: ShellStyles.surface(context),
            withShadow: false,
          ),
          child: Row(
            children: [
              Container(
                width: ShellStyles.scaled(context, 44, min: 40, max: 48),
                height: ShellStyles.scaled(context, 44, min: 40, max: 48),
                decoration: ShellStyles.semanticBadgeDecoration(
                  context,
                  tone: categoryTone,
                  radius: ShellStyles.scaled(context, 14, min: 12, max: 16),
                ),
                child: Icon(iconData, color: categoryTone.foreground),
              ),
              SizedBox(
                width: ShellStyles.scaled(context, 12, min: 10, max: 14),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontWeight: FontWeight.w500,
                        fontSize: ShellStyles.scaled(
                          context,
                          15,
                          min: 14,
                          max: 16,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (formattedTime.isNotEmpty)
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: ShellStyles.scaled(
                            context,
                            11.5,
                            min: 11,
                            max: 12.5,
                          ),
                        ),
                      ),
                    if (hasMetaRow) ...[
                      SizedBox(
                        height: ShellStyles.scaled(context, 8, min: 6, max: 10),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (txCategoryLabel != null &&
                              txCategoryLabel.isNotEmpty)
                            _buildMetaChip(
                              label: txCategoryLabel,
                              icon: Icons.category_outlined,
                              color: iconColor,
                            ),
                          ...labelsToRender.map((label) {
                            final labelName = label['name']?.toString() ?? '';
                            if (labelName.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final labelTone = ShellStyles.labelTone(
                              context,
                              labelId: label['id']?.toString(),
                              name: labelName,
                              rawHex: label['color']?.toString(),
                            );
                            return _buildMetaChip(
                              label: labelName,
                              icon: Icons.push_pin_outlined,
                              color: labelTone.base,
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatMoney(displayCurrency, displayAmount),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontWeight: FontWeight.bold,
                      fontSize: ShellStyles.scaled(
                        context,
                        15,
                        min: 14,
                        max: 16,
                      ),
                    ),
                  ),
                  if (showOriginal)
                    Text(
                      _formatMoney(sourceCurrency, sourceAmount),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: ShellStyles.scaled(
                          context,
                          11.5,
                          min: 11,
                          max: 12.5,
                        ),
                      ),
                    ),
                  if (receiptSavings > 0)
                    Text(
                      '- ${_formatMoney(displayCurrency, receiptSavings)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: ShellStyles.scaled(
                          context,
                          11.5,
                          min: 11,
                          max: 12.5,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ShellStyles.scaled(context, 8, min: 7, max: 10),
        vertical: ShellStyles.scaled(context, 4, min: 3, max: 5),
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(56)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummary() {
    double totalPeriodExpense = 0;
    double totalPeriodSavings = 0;
    String totalCurrency = _preferredCurrency;

    for (var tx in _transactions) {
      final txMap = tx as Map<String, dynamic>;
      totalPeriodExpense += _displayAmountOf(txMap);
      totalCurrency = _displayCurrencyOf(txMap);

      final itemsRaw = txMap['items'];
      if (itemsRaw is List) {
        final amountTotal =
            double.tryParse(txMap['amount_total']?.toString() ?? '0') ?? 0;
        final displayAmountTotal =
            double.tryParse(txMap['display_amount_total']?.toString() ?? '0') ??
            0;
        final rate = amountTotal > 0 ? displayAmountTotal / amountTotal : 1.0;

        double receiptSourceSavings = 0;

        for (var rawItem in itemsRaw) {
          if (rawItem is Map<String, dynamic>) {
            var discountRaw =
                double.tryParse(
                  rawItem['discount_amount']?.toString() ?? '0',
                ) ??
                0;
            if (discountRaw == 0) {
              final amountBefore =
                  double.tryParse(
                    rawItem['amount_before_discount']?.toString() ?? '0',
                  ) ??
                  0;
              final amountLine =
                  double.tryParse(rawItem['amount']?.toString() ?? '0') ?? 0;
              if (amountBefore > 0 &&
                  amountLine > 0 &&
                  amountBefore > amountLine) {
                discountRaw = amountBefore - amountLine;
              }
            }
            if (discountRaw > 0) {
              receiptSourceSavings += discountRaw;
            }
          }
        }

        if (receiptSourceSavings > 0) {
          totalPeriodSavings += receiptSourceSavings * rate;
        }
      }
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final mutedColor = ShellStyles.textMuted(context);
    final savingsLabel = context
        .tr('transaction_total_savings')
        .replaceFirst(RegExp(r'[:：]\s*$'), '');

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          ShellStyles.scaled(context, 16, min: 14, max: 18),
          ShellStyles.scaled(context, 10, min: 8, max: 12),
          ShellStyles.scaled(context, 16, min: 14, max: 18),
          ShellStyles.scaled(context, 12, min: 10, max: 14),
        ),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          border: Border(top: BorderSide(color: ShellStyles.border(context))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedPeriod == PeriodFilter.allTime
                        ? 'Receipt history total'
                        : context.tr('receipts_total_for_period'),
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: ShellStyles.scaled(
                        context,
                        11.5,
                        min: 11,
                        max: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatMoney(totalCurrency, totalPeriodExpense),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: ShellStyles.scaled(
                        context,
                        17,
                        min: 16,
                        max: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr(
                    'receipts_count',
                    params: {'count': _transactions.length.toString()},
                  ),
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: ShellStyles.scaled(
                      context,
                      12,
                      min: 11.5,
                      max: 13,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (totalPeriodSavings > 0)
                  Text(
                    '$savingsLabel: ${_formatMoney(totalCurrency, totalPeriodSavings)}',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: ShellStyles.scaled(
                        context,
                        11.5,
                        min: 11,
                        max: 12.5,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    context.tr('receipts_no_discounts'),
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: ShellStyles.scaled(
                        context,
                        11.5,
                        min: 11,
                        max: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
