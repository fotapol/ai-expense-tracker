import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import 'transaction_edit_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _isLoading = true;
  String? _error;
  String _preferredCurrency = 'RSD';
  List<Map<String, dynamic>> _transactions = [];
  late List<DateTime> _last7Days;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _initializeDateRange();
    _loadHomeData();
  }

  void _initializeDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _last7Days = List.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
    _selectedDay = _last7Days.last;
  }

  Future<void> _loadHomeData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fromDate = _last7Days.first;
      final results = await Future.wait([
        ApiClient.getMe(),
        ApiClient.listTransactions(fromDate: fromDate),
      ]);

      final me = results[0] as Map<String, dynamic>;
      final rawTransactions = results[1] as List<dynamic>;
      final defaultCurrency = me['default_currency']?.toString().trim();
      final txs = rawTransactions.whereType<Map<String, dynamic>>().toList();

      txs.sort((a, b) {
        final aDate =
            _parseOccurredAt(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            _parseOccurredAt(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        if (defaultCurrency != null && defaultCurrency.isNotEmpty) {
          _preferredCurrency = defaultCurrency.toUpperCase();
        }
        _transactions = txs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _resolveDisplayName(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = user?.email?.trim();
    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) return localPart;
    }

    return context.tr('home_default_user');
  }

  DateTime? _parseOccurredAt(Map<String, dynamic> tx) {
    final raw =
        tx['occurred_at']?.toString() ?? tx['created_at']?.toString() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed?.toLocal();
  }

  DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _transactionsForDay(DateTime day) {
    return _transactions.where((tx) {
      final occurred = _parseOccurredAt(tx);
      if (occurred == null) return false;
      return _isSameDay(_dayOnly(occurred), day);
    }).toList();
  }

  int _daysWithData() =>
      _last7Days.where((day) => _transactionsForDay(day).isNotEmpty).length;

  String _currencySymbol(String code) {
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
    final symbol = _currencySymbol(currency);
    if (symbol.trim().length == 1 || symbol == 'RSD ') {
      final sign = amount < 0 ? '-' : '';
      return '$sign$symbol${amount.abs().toStringAsFixed(2)}';
    }
    return '${currency.toUpperCase()} ${amount.toStringAsFixed(2)}';
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

  double _dailyTotal(DateTime day) {
    final txs = _transactionsForDay(day);
    return txs.fold<double>(0, (sum, tx) => sum + _displayAmountOf(tx));
  }

  String _dailyCurrency(DateTime day) {
    final txs = _transactionsForDay(day);
    if (txs.isEmpty) return _preferredCurrency;
    return _displayCurrencyOf(txs.first);
  }

  @override
  Widget build(BuildContext context) {
    final selectedTransactions = _transactionsForDay(_selectedDay);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHomeData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildDailySpendingCard(context),
              const SizedBox(height: 20),
              _buildDateScroller(context),
              const SizedBox(height: 24),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _buildErrorState(context)
              else if (selectedTransactions.isEmpty)
                _buildEmptyState(context)
              else
                ...selectedTransactions.map(
                  (tx) => _buildReceiptCard(context, tx),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('home_welcome'),
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 4),
            Text(
              _resolveDisplayName(context),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        // Container(
        //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        //   decoration: BoxDecoration(
        //     color: Theme.of(context).colorScheme.surface,
        //     borderRadius: BorderRadius.circular(20),
        //     border: Border.all(color: Colors.grey.shade800),
        //   ),
        //   child: Text(
        //     '${_daysWithData()}/7',
        //     style: const TextStyle(fontSize: 12),
        //   ),
        // ),
      ],
    );
  }

  Widget _buildDailySpendingCard(BuildContext context) {
    final total = _dailyTotal(_selectedDay);
    final currency = _dailyCurrency(_selectedDay);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A148C), Color(0xFF311B92)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('home_daily_spending'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            _formatMoney(currency, total),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(height: 70, child: _buildSpendingChart()),
        ],
      ),
    );
  }

  Widget _buildSpendingChart() {
    final totals = _last7Days.map(_dailyTotal).toList();
    final maxTotal = totals.fold<double>(0, math.max);
    final maxY = maxTotal <= 0 ? 1.0 : maxTotal * 1.15;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (_last7Days.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 0,
              color: Colors.white.withAlpha(70),
              strokeWidth: 2,
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              totals.length,
              (index) => FlSpot(index.toDouble(), totals[index]),
            ),
            isCurved: true,
            barWidth: 3,
            color: const Color(0xFFE040FB),
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.white.withAlpha(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateScroller(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _last7Days.map((date) {
          final isSelected = _isSameDay(date, _selectedDay);
          final hasData = _transactionsForDay(date).isNotEmpty;
          final label = DateFormat('d MMM', locale).format(date);

          return GestureDetector(
            onTap: () => setState(() => _selectedDay = date),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2D124D)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (hasData) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'common_error_with_message',
                params: {'message': _error ?? context.tr('common_error')},
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadHomeData,
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> tx) {
    final storeName = tx['merchant_name']?.toString().trim().isNotEmpty == true
        ? tx['merchant_name'].toString()
        : context.tr('receipts_unknown_store');
    final occurredAt = _parseOccurredAt(tx);
    final locale = Localizations.localeOf(context).toLanguageTag();
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
    final dateText = occurredAt == null
        ? ''
        : DateFormat('d MMM, HH:mm', locale).format(occurredAt);

    return GestureDetector(
      onTap: () {
        final id = tx['id']?.toString();
        if (id == null || id.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TransactionEditScreen(transactionId: id),
          ),
        ).then((_) => _loadHomeData());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.receipt_long,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateText,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatMoney(displayCurrency, displayAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (showOriginal)
                  Text(
                    _formatMoney(sourceCurrency, sourceAmount),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.receipt_long, size: 80, color: Colors.grey.shade800),
                Positioned(
                  top: 10,
                  child: Container(
                    width: 40,
                    height: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Positioned(
                  bottom: 25,
                  right: 15,
                  child: Container(
                    width: 20,
                    height: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('home_no_receipts'),
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade300,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('home_no_receipts_for_day'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
