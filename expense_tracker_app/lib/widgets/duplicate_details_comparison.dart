import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/duplicate_comparison.dart';
import '../core/localized_dates.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class DuplicateDetailsComparison extends StatefulWidget {
  const DuplicateDetailsComparison({
    super.key,
    required this.transactions,
    required this.selectedId,
    required this.onSelect,
    required this.onPhoto,
    required this.busy,
    this.numbers = const [1, 2],
  });
  final List<Map<String, dynamic>> transactions;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<Map<String, dynamic>> onPhoto;
  final bool busy;
  final List<int> numbers;
  @override
  State<DuplicateDetailsComparison> createState() => _ComparisonState();
}

class _ComparisonState extends State<DuplicateDetailsComparison> {
  bool _differencesOnly = false;
  late List<ComparedItem> _rows;
  void _alignItems() => _rows = compareItems(
    widget.transactions[0]['items'] as List? ?? [],
    widget.transactions[1]['items'] as List? ?? [],
  );
  @override
  void initState() {
    super.initState();
    _alignItems();
  }

  @override
  void didUpdateWidget(DuplicateDetailsComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.transactions, widget.transactions)) _alignItems();
  }

  String _label(int index) => context.tr(
    'duplicates_receipt_number',
    params: {
      'number': MaterialLocalizations.of(
        context,
      ).formatDecimal(widget.numbers[index]),
    },
  );

  String _amount(Object? value, String currency, {bool unitPrice = false}) {
    final amount = num.tryParse(value?.toString() ?? '');
    if (amount == null || !amount.isFinite) return '—';
    // Comparison always shows financial precision, even with rounded totals enabled.
    final format = NumberFormat(
      unitPrice ? '#,##0.00##' : '#,##0.00',
      Localizations.localeOf(context).languageCode,
    );
    return '${currency.trim().toUpperCase()} ${format.format(amount)}';
  }

  String _quantity(Map<String, dynamic>? item) {
    final qty = num.tryParse(item?['qty']?.toString() ?? '');
    if (qty == null) return '—';
    final format = NumberFormat(
      '#,##0.###',
      Localizations.localeOf(context).languageCode,
    );
    return '${format.format(qty)} ${comparisonUnit(item?['unit'])}'.trim();
  }

  Color get _differenceColor => ShellStyles.isDark(context)
      ? Colors.amber.shade200
      : Colors.brown.shade700;

  Widget _value(
    String text, {
    bool different = false,
    bool strong = false,
  }) => Container(
    key: different ? const ValueKey('comparison-difference') : null,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: different ? _differenceColor.withAlpha(20) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      border: different
          ? Border.all(color: _differenceColor.withAlpha(80))
          : null,
    ),
    child: Text(
      text,
      style: TextStyle(
        color: different ? _differenceColor : ShellStyles.textPrimary(context),
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
        height: 1.35,
      ),
    ),
  );

  Widget _cells(Widget first, Widget second) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: 8),
      Expanded(child: second),
    ],
  );

  String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? '—'
        : formatLocalizedDayMonthYearTime(context, date.toLocal());
  }

  Widget _receiptHeader(int index) {
    final tx = widget.transactions[index],
        other = widget.transactions[1 - index];
    final selected = widget.selectedId == tx['id'];
    final tone = ShellStyles.accentTone(context);
    final totalMatches =
        comparisonText(tx['currency']) == comparisonText(other['currency']) &&
        comparisonNumberSame(tx['amount_total'], other['amount_total']);
    return Material(
      color: selected
          ? tone.container.withAlpha(80)
          : ShellStyles.surface(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? tone.base : ShellStyles.border(context),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('select-${tx['id']}'),
        borderRadius: BorderRadius.circular(14),
        onTap: widget.busy ? null : () => widget.onSelect(tx['id'].toString()),
        child: Semantics(
          selected: selected,
          button: true,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      selected ? AppIcons.circleCheck : AppIcons.circle,
                      size: 20,
                      color: selected
                          ? tone.base
                          : ShellStyles.textMuted(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _label(index),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _value(
                  tx['merchant_name']?.toString() ?? '—',
                  different:
                      comparisonText(tx['merchant_name']) !=
                      comparisonText(other['merchant_name']),
                ),
                _value(
                  _amount(tx['amount_total'], tx['currency'].toString()),
                  different: !totalMatches,
                  strong: true,
                ),
                _value(
                  _date(tx['occurred_at']),
                  different: !samePurchaseMinute(
                    tx['occurred_at'],
                    other['occurred_at'],
                  ),
                ),
                if (tx['created_at'] != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Text(
                      context.tr(
                        'duplicates_added_at',
                        params: {'date': _date(tx['created_at'])},
                      ),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: ShellStyles.textMuted(context),
                      ),
                    ),
                  ),
                if (tx['receipt_id'] != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: IconButton(
                      tooltip: context.tr('duplicates_view_original'),
                      onPressed: widget.busy ? null : () => widget.onPhoto(tx),
                      icon: const Icon(AppIcons.receiptText, size: 20),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String first,
    String second, {
    required bool different,
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ShellStyles.textMuted(context),
          ),
        ),
        const SizedBox(height: 3),
        _cells(
          _value(first, different: different, strong: strong),
          _value(second, different: different, strong: strong),
        ),
      ],
    ),
  );

  Widget _item(ComparedItem row, int index) {
    final a = row.first, b = row.second;
    final both = a != null && b != null;
    final currencies = [
      for (final tx in widget.transactions) tx['currency']?.toString() ?? '',
    ];
    final sameCurrency =
        comparisonText(currencies[0]) == comparisonText(currencies[1]);
    final differentName = both && !row.same('description');
    final prices = [comparisonUnitPrice(a), comparisonUnitPrice(b)];
    final showUnitPrice =
        prices.any((price) => price != null) &&
        !(comparisonNumberSame(a?['qty'], 1, decimals: 3) &&
            comparisonNumberSame(b?['qty'], 1, decimals: 3) &&
            comparisonNumberSame(prices[0], a?['amount'], decimals: 4) &&
            comparisonNumberSame(prices[1], b?['amount'], decimals: 4));
    return Container(
      key: ValueKey('compared-item-$index'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 14,
        withShadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (differentName)
            _cells(
              _value(
                a['description']?.toString() ?? '—',
                different: true,
                strong: true,
              ),
              _value(
                b['description']?.toString() ?? '—',
                different: true,
                strong: true,
              ),
            )
          else
            Text(
              (a ?? b)!['description']?.toString() ?? '—',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          if (!both)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr(
                  'duplicates_only_receipt',
                  params: {
                    'number': widget.numbers[a == null ? 1 : 0].toString(),
                  },
                ),
                style: TextStyle(fontSize: 11, color: _differenceColor),
              ),
            ),
          _field(
            context.tr('duplicates_quantity'),
            _quantity(a),
            _quantity(b),
            different: !both || !row.same('qty') || !row.same('unit'),
          ),
          if (showUnitPrice)
            _field(
              context.tr('duplicates_unit_price'),
              _amount(prices[0], currencies[0], unitPrice: true),
              _amount(prices[1], currencies[1], unitPrice: true),
              different: !both || !sameCurrency || !row.same('unit_price'),
            ),
          if ((comparisonDiscount(a) ?? 0) != 0 ||
              (comparisonDiscount(b) ?? 0) != 0)
            _field(
              context.tr('duplicates_discount'),
              _amount(comparisonDiscount(a), currencies[0]),
              _amount(comparisonDiscount(b), currencies[1]),
              different: !both || !sameCurrency || !row.same('discount_amount'),
            ),
          _field(
            context.tr('duplicates_line_total'),
            _amount(a?['amount'], currencies[0]),
            _amount(b?['amount'], currencies[1]),
            different: !both || !sameCurrency || !row.same('amount'),
            strong: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.length != 2) return const SizedBox.shrink();
    final sameCurrency =
        comparisonText(widget.transactions[0]['currency']) ==
        comparisonText(widget.transactions[1]['currency']);
    final visibleRows = [
      for (var i = 0; i < _rows.length; i++)
        if (!_differencesOnly || !_rows[i].identical || !sameCurrency) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cells(_receiptHeader(0), _receiptHeader(1)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(AppIcons.diff, color: _differenceColor, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.tr('duplicates_highlight_hint'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: ShellStyles.textMuted(context),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          context.tr('transaction_items_heading'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        CheckboxListTile(
          key: const ValueKey('duplicate-differences-only'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          value: _differencesOnly,
          onChanged: (value) =>
              setState(() => _differencesOnly = value ?? false),
          title: Text(
            context.tr('duplicates_differences_only'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (visibleRows.isNotEmpty)
          _cells(
            Text(_label(0), textAlign: TextAlign.center),
            Text(_label(1), textAlign: TextAlign.center),
          ),
        for (final i in visibleRows) _item(_rows[i], i),
        if (visibleRows.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(16),
            decoration: ShellStyles.cardDecoration(
              context,
              radius: 14,
              withShadow: false,
            ),
            child: Text(
              _differencesOnly
                  ? context.tr('duplicates_no_item_differences')
                  : '—',
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}
