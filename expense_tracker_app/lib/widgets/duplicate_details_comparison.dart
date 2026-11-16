import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/duplicate_comparison.dart';
import '../core/localized_dates.dart';
import '../core/money_formatter.dart';
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

  String _amount(
    Map<String, dynamic>? item,
    String currency, {
    String field = 'amount',
  }) => item?[field] == null
      ? '—'
      : formatMoney(
          currency,
          num.tryParse(item![field].toString())?.toDouble() ?? 0,
        );

  String _quantity(Map<String, dynamic>? item) {
    final qty = num.tryParse(item?['qty']?.toString() ?? '');
    return qty == null
        ? '—'
        : '${NumberFormat.decimalPattern(Localizations.localeOf(context).languageCode).format(qty)} ${item?['unit'] ?? ''}'
              .trim();
  }

  Color _mark(bool same) => same
      ? (ShellStyles.isDark(context)
            ? Colors.green.shade200
            : Colors.green.shade800)
      : (ShellStyles.isDark(context)
            ? Colors.amber.shade200
            : Colors.brown.shade700);

  Widget _value(String text, {bool? same, bool strong = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: same == null ? Colors.transparent : _mark(same).withAlpha(18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: same == null ? ShellStyles.textPrimary(context) : _mark(same),
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
        height: 1.3,
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

  Widget _receiptHeader(int index) {
    final tx = widget.transactions[index],
        other = widget.transactions[1 - index];
    final selected = widget.selectedId == tx['id'];
    final tone = ShellStyles.accentTone(context);
    final sameCurrency = tx['currency'] == other['currency'];
    final totalMatches =
        sameCurrency &&
        num.tryParse(tx['amount_total'].toString()) ==
            num.tryParse(other['amount_total'].toString());
    final date = DateTime.tryParse(tx['occurred_at']?.toString() ?? '');
    final dateText = date == null
        ? '—'
        : formatLocalizedDayMonthYearTime(context, date.toLocal());
    return Material(
      color: selected
          ? tone.container.withAlpha(80)
          : ShellStyles.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? tone.base : ShellStyles.border(context),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('select-${tx['id']}'),
        borderRadius: BorderRadius.circular(12),
        onTap: widget.busy ? null : () => widget.onSelect(tx['id'].toString()),
        child: Semantics(
          selected: selected,
          button: true,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
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
                    if (tx['receipt_id'] != null)
                      IconButton(
                        tooltip: context.tr('duplicates_view_original'),
                        onPressed: widget.busy
                            ? null
                            : () => widget.onPhoto(tx),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      ),
                  ],
                ),
                _value(
                  tx['merchant_name']?.toString() ?? '—',
                  same: tx['merchant_name'] == other['merchant_name'],
                ),
                const SizedBox(height: 4),
                _value(
                  _amount({
                    'amount': tx['amount_total'],
                  }, tx['currency'].toString()),
                  same: totalMatches,
                  strong: true,
                ),
                const SizedBox(height: 4),
                _value(
                  dateText,
                  same: tx['occurred_at'] == other['occurred_at'],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(ComparedItem row, int index) {
    final a = row.first, b = row.second;
    final both = a != null && b != null;
    final firstCurrency = widget.transactions[0]['currency'].toString();
    final secondCurrency = widget.transactions[1]['currency'].toString();
    final sameCurrency = firstCurrency == secondCurrency;
    final identical = row.identical && sameCurrency;
    final title = (a ?? b)!['description']?.toString() ?? '';
    Widget priceLabel() => Text(
      context.tr('duplicates_unit_price'),
      style: TextStyle(fontSize: 11, color: ShellStyles.textMuted(context)),
    );

    return Container(
      key: ValueKey('compared-item-$index'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ShellStyles.surface(context),
        border: Border.all(color: ShellStyles.border(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                identical ? Icons.check_circle_outline : Icons.compare_arrows,
                size: 16,
                color: identical ? _mark(true) : ShellStyles.textMuted(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (!both)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                context.tr(
                  'duplicates_only_receipt',
                  params: {
                    'number': widget.numbers[a == null ? 1 : 0].toString(),
                  },
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: ShellStyles.textMuted(context),
                ),
              ),
            ),
          if (both && a['description'] != b['description'])
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                b['description']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: ShellStyles.textMuted(context),
                ),
              ),
            ),
          const SizedBox(height: 6),
          _cells(
            _value(
              _quantity(a),
              same: both ? row.same('qty') && row.same('unit') : null,
            ),
            _value(
              _quantity(b),
              same: both ? row.same('qty') && row.same('unit') : null,
            ),
          ),
          if (a?['unit_price'] != null || b?['unit_price'] != null) ...[
            const SizedBox(height: 3),
            _cells(priceLabel(), priceLabel()),
            _cells(
              _value(
                _amount(a, firstCurrency, field: 'unit_price'),
                same: both ? row.same('unit_price') && sameCurrency : null,
              ),
              _value(
                _amount(b, secondCurrency, field: 'unit_price'),
                same: both ? row.same('unit_price') && sameCurrency : null,
              ),
            ),
          ],
          const SizedBox(height: 3),
          _cells(
            _value(
              _amount(a, firstCurrency),
              same: both ? row.same('amount') && sameCurrency : null,
              strong: true,
            ),
            _value(
              _amount(b, secondCurrency),
              same: both ? row.same('amount') && sameCurrency : null,
              strong: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.length != 2) return const SizedBox.shrink();
    final a = widget.transactions[0], b = widget.transactions[1];
    final rows = _rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cells(_receiptHeader(0), _receiptHeader(1)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '✓ ${context.tr('duplicates_matches')}',
              style: TextStyle(fontSize: 12, color: _mark(true)),
            ),
            Text(
              '↔ ${context.tr('duplicates_differences')}',
              style: TextStyle(fontSize: 12, color: _mark(false)),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          context.tr('transaction_items_heading'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _differencesOnly,
          onChanged: (value) =>
              setState(() => _differencesOnly = value ?? false),
          title: Text(
            context.tr('duplicates_differences_only'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _cells(
          Text(_label(0), textAlign: TextAlign.center),
          Text(_label(1), textAlign: TextAlign.center),
        ),
        for (var i = 0; i < rows.length; i++)
          if (!_differencesOnly ||
              !rows[i].identical ||
              a['currency'] != b['currency'])
            _item(rows[i], i),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('—')),
      ],
    );
  }
}
