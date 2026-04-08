import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/auto_refresh_state_mixin.dart';
import '../core/launch_error_copy.dart';
import '../core/money_formatter.dart';
import '../core/money_format_preferences.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/subscription_confirmation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'analytics_screen.dart';
import 'receipt_manager_screen.dart';
import 'receipt_upload_screen.dart';
import 'subscription_screen.dart';
import 'transaction_edit_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab>
    with WidgetsBindingObserver, AutoRefreshStateMixin<HomeTab> {
  bool _isLoading = true;
  String? _error;
  String _preferredCurrency = 'EUR';
  Map<String, dynamic>? _monthlySummary;
  List<Map<String, dynamic>> _currentMonthTransactions = [];
  List<Map<String, dynamic>> _previousMonthTransactions = [];
  bool _isRefreshingHome = false;
  bool _hasPremiumAccess = false;
  int? _receiptUploadRemaining;
  int? _receiptUploadLimit;

  @override
  Duration get autoRefreshInterval => const Duration(minutes: 1);

  @override
  Future<void> performAutoRefresh() => _loadHomeData(showLoader: false);

  @override
  void initState() {
    super.initState();
    moneyFormatSettings.addListener(_handleDisplayPreferencesChanged);
    _loadHomeData();
  }

  @override
  void dispose() {
    moneyFormatSettings.removeListener(_handleDisplayPreferencesChanged);
    super.dispose();
  }

  void _handleDisplayPreferencesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  DateTime get _currentMonthStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime get _previousMonthStart {
    final monthStart = _currentMonthStart;
    return DateTime(monthStart.year, monthStart.month - 1, 1);
  }

  Future<void> _loadHomeData({bool showLoader = true}) async {
    if (_isRefreshingHome) return;
    _isRefreshingHome = true;
    if (!mounted) {
      _isRefreshingHome = false;
      return;
    }

    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final subscriptionFuture = ApiClient.getMeSubscription().catchError(
        (_) => <String, dynamic>{},
      );
      final results = await Future.wait([
        ApiClient.getMe(),
        ApiClient.getTransactionsSummary(fromDate: _currentMonthStart),
        ApiClient.listTransactions(fromDate: _previousMonthStart),
        subscriptionFuture,
      ]);

      final me = results[0] as Map<String, dynamic>;
      final summary = results[1] as Map<String, dynamic>;
      final rawTransactions = results[2] as List<dynamic>;
      final subscriptionPayload = results[3] as Map<String, dynamic>;
      final allTransactions = rawTransactions.whereType<Map<String, dynamic>>();

      final currentTransactions = <Map<String, dynamic>>[];
      final previousTransactions = <Map<String, dynamic>>[];
      for (final transaction in allTransactions) {
        final occurredAt = _parseOccurredAt(transaction);
        if (occurredAt == null) continue;
        if (_isSameMonth(occurredAt, _currentMonthStart)) {
          currentTransactions.add(transaction);
        } else if (_isSameMonth(occurredAt, _previousMonthStart)) {
          previousTransactions.add(transaction);
        }
      }

      final usageRaw = subscriptionPayload['receipt_scan_usage'];
      final usage = usageRaw is Map<String, dynamic>
          ? usageRaw
          : const <String, dynamic>{};
      final optimisticPremium = await hasOptimisticPremiumAccess();
      final hasPremiumAccess =
          subscriptionPayload['has_active_subscription'] == true ||
          usage['is_unlimited'] == true ||
          optimisticPremium;
      final defaultCurrency = me['default_currency']?.toString().trim();
      if (!mounted) return;
      setState(() {
        _preferredCurrency =
            (defaultCurrency == null || defaultCurrency.isEmpty)
            ? _preferredCurrency
            : defaultCurrency.toUpperCase();
        _monthlySummary = summary;
        _currentMonthTransactions = currentTransactions;
        _previousMonthTransactions = previousTransactions;
        _hasPremiumAccess = hasPremiumAccess;
        _receiptUploadLimit = int.tryParse((usage['limit'] ?? '').toString());
        _receiptUploadRemaining = optimisticPremium
            ? null
            : int.tryParse((usage['remaining'] ?? '').toString());
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback: 'Home could not refresh just now. Please try again.',
        );
        _isLoading = false;
      });
    } finally {
      _isRefreshingHome = false;
    }
  }

  bool _isSameMonth(DateTime value, DateTime reference) {
    return value.year == reference.year && value.month == reference.month;
  }

  DateTime? _parseOccurredAt(Map<String, dynamic> transaction) {
    final raw =
        transaction['occurred_at']?.toString() ??
        transaction['created_at']?.toString() ??
        '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _resolveDisplayName(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();
    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) {
        return localPart;
      }
    }

    return context.tr('home_default_user');
  }

  String _greetingLabel(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.tr('home_greeting_morning');
    if (hour < 18) return context.tr('home_greeting_afternoon');
    return context.tr('home_greeting_evening');
  }

  bool _needsReview(Map<String, dynamic> transaction) {
    final status = transaction['status']?.toString().toUpperCase();
    return status == 'DRAFT' || transaction['has_extraction_warnings'] == true;
  }

  int get _reviewCount => _currentMonthTransactions.where(_needsReview).length;

  String _reviewSubtitle(BuildContext context) {
    if (_currentMonthTransactions.isEmpty &&
        _previousMonthTransactions.isEmpty) {
      return 'Scan a receipt or add an expense to get started.';
    }
    if (_reviewCount == 0) {
      return context.tr('home_all_reviewed');
    }
    if (_reviewCount == 1) {
      return context.tr('home_review_count_single');
    }
    return context.tr(
      'home_review_count_plural',
      params: {'count': _reviewCount.toString()},
    );
  }

  double _displayAmountOf(Map<String, dynamic> transaction) {
    final raw =
        transaction['display_amount_total'] ?? transaction['amount_total'];
    return double.tryParse(raw?.toString() ?? '0') ?? 0;
  }

  double get _currentMonthTotal =>
      (_monthlySummary?['total_amount'] as num?)?.toDouble() ??
      _currentMonthTransactions.fold<double>(
        0,
        (sum, transaction) => sum + _displayAmountOf(transaction),
      );

  double get _previousMonthTotal => _previousMonthTransactions.fold<double>(
    0,
    (sum, transaction) => sum + _displayAmountOf(transaction),
  );

  String get _currency =>
      (_monthlySummary?['currency']?.toString() ?? _preferredCurrency)
          .toUpperCase();

  String _formatMoney(String currency, double amount, {int decimals = 0}) {
    return formatMoney(currency, amount, decimals: decimals);
  }

  double? get _changeRatio {
    if (_previousMonthTotal <= 0) return null;
    return (_currentMonthTotal - _previousMonthTotal) / _previousMonthTotal;
  }

  String _changeLabel(BuildContext context) {
    final ratio = _changeRatio;
    if (ratio == null) return '';
    final percent = (ratio.abs() * 100).round();
    if (percent == 0) return context.tr('home_change_flat');
    if (ratio < 0) {
      return context.tr(
        'home_change_less',
        params: {'percent': percent.toString()},
      );
    }
    return context.tr(
      'home_change_more',
      params: {'percent': percent.toString()},
    );
  }

  List<_OverviewSlice> _overviewSlices(BuildContext context) {
    final rawBreakdown = _monthlySummary?['breakdown'] as List<dynamic>? ?? [];
    final slices = <_OverviewSlice>[];
    for (final raw in rawBreakdown.whereType<Map<String, dynamic>>()) {
      final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final code = raw['code']?.toString() ?? '';
      final name = localizeCategoryByCode(
        context,
        code: code,
        fallbackName: raw['name']?.toString(),
      );
      slices.add(
        _OverviewSlice(
          name: name,
          amount: amount,
          percentage: (raw['percentage'] as num?)?.toDouble() ?? 0,
          color: Colors.transparent, // Assigned after sorting
        ),
      );
    }

    slices.sort((left, right) => right.amount.compareTo(left.amount));

    final palette = [
      ShellStyles.textPrimary(context),
      ShellStyles.textPrimary(context).withAlpha(150),
      ShellStyles.textPrimary(context).withAlpha(80),
      ShellStyles.border(context), // Used for 'Other'
    ];

    if (slices.length <= 3) {
      for (int i = 0; i < slices.length; i++) {
        slices[i] = _OverviewSlice(
          name: slices[i].name,
          amount: slices[i].amount,
          percentage: slices[i].percentage,
          color: palette[i % palette.length],
        );
      }
      return slices;
    }

    final visible = slices.take(3).toList();
    final hidden = slices.skip(3);
    final otherAmount = hidden.fold<double>(
      0,
      (sum, slice) => sum + slice.amount,
    );
    final otherPercentage = hidden.fold<double>(
      0,
      (sum, slice) => sum + slice.percentage,
    );

    for (int i = 0; i < visible.length; i++) {
      visible[i] = _OverviewSlice(
        name: visible[i].name,
        amount: visible[i].amount,
        percentage: visible[i].percentage,
        color: palette[i],
      );
    }

    if (otherAmount > 0) {
      visible.add(
        _OverviewSlice(
          name: context.tr('taxonomy_other'),
          amount: otherAmount,
          percentage: otherPercentage,
          color: palette[3],
        ),
      );
    }
    return visible;
  }

  List<String> _buildInsights(BuildContext context) {
    final insights = <String>[];
    if (_currentMonthTransactions.isEmpty &&
        _previousMonthTransactions.isEmpty &&
        (_monthlySummary?['breakdown'] as List<dynamic>? ?? const []).isEmpty) {
      return insights;
    }
    final ratio = _changeRatio;
    if (ratio != null) {
      final previousMonthLabel = DateFormat('MMMM').format(_previousMonthStart);
      final percent = (ratio.abs() * 100).round();
      if (percent > 0) {
        insights.add(
          context.tr(
            ratio < 0
                ? 'home_insight_less_than_last_month'
                : 'home_insight_more_than_last_month',
            params: {
              'percent': percent.toString(),
              'month': previousMonthLabel,
            },
          ),
        );
      }
    }

    final slices = _overviewSlices(context);
    if (insights.isEmpty && slices.isNotEmpty) {
      final topSlice = slices.first;
      insights.add(
        context.tr(
          'home_insight_top_category',
          params: {
            'category': topSlice.name,
            'percent': topSlice.percentage.round().toString(),
          },
        ),
      );
    }

    if (_reviewCount > 0) {
      insights.add(
        context.tr(
          'home_insight_review_count',
          params: {'count': _reviewCount.toString()},
        ),
      );
    } else {
      insights.add(context.tr('home_insight_all_caught_up'));
    }

    return insights.take(2).toList();
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openSubscriptionScreen(BuildContext context) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
    );
    if (!mounted) return;
    if (changed == true) {
      await _loadHomeData(showLoader: false);
    }
  }

  String _uploadCounterLabel() {
    final remaining = _receiptUploadRemaining;
    final limit = (_receiptUploadLimit != null && _receiptUploadLimit! > 0)
        ? _receiptUploadLimit!
        : 10;
    final safeRemaining = remaining == null ? limit : remaining.clamp(0, limit);
    return '$safeRemaining/$limit';
  }

  @override
  Widget build(BuildContext context) {
    final hasData =
        _monthlySummary != null || _currentMonthTransactions.isNotEmpty;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 152;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadHomeData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPadding),
          children: [
            _buildHeader(context),
            const SizedBox(height: 18),
            if (_isLoading && !hasData)
              _buildLoadingState(context)
            else if (_error != null && !hasData)
              _buildErrorState(context)
            else ...[
              _buildMonthlySummaryCard(context),
              const SizedBox(height: 14),
              _buildScanCard(context),
              const SizedBox(height: 16),
              _buildQuickActions(context),
              const SizedBox(height: 14),
              _buildOverviewCard(context),
              if (_buildInsights(context).isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildInsightsCard(context),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _buildInlineWarning(context),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greetingLabel(context)}, ${_resolveDisplayName(context)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _reviewSubtitle(context),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _hasPremiumAccess
            ? _buildHeaderAction(
                context,
                child: CrownIcon(
                  color: ShellColors.gold,
                  size: ShellStyles.scaled(context, 17, min: 15, max: 18),
                  strokeWidth: 1.7,
                ),
                onTap: () => _openSubscriptionScreen(context),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => _openSubscriptionScreen(context),
                child: Builder(
                  builder: (context) {
                    final counterSize = ShellStyles.scaled(
                      context,
                      42,
                      min: 36,
                      max: 46,
                    );
                    return Container(
                      width: counterSize,
                      height: counterSize,
                      decoration: ShellStyles.cardDecoration(
                        context,
                        radius: counterSize / 2,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _uploadCounterLabel(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: ShellStyles.scaled(
                            context,
                            10.5,
                            min: 9.5,
                            max: 11,
                          ),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },
                ),
              ),
        const SizedBox(width: 8),
        // TODO(household): restore household button on home screen when feature ships
        /*
        _buildHeaderAction(
          context,
          icon: AppIcons.group,
          iconColor: const Color(0xFFB173D1),
          onTap: () => _open(context, const HouseholdScreen()),
        ),
        */
      ],
    );
  }

  Widget _buildHeaderAction(
    BuildContext context, {
    Widget? child,
    IconData? icon,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final buttonSize = ShellStyles.scaled(context, 38, min: 34, max: 42);
    final iconSize = ShellStyles.scaled(context, 16, min: 14, max: 18);
    return InkWell(
      borderRadius: BorderRadius.circular(buttonSize / 2),
      onTap: onTap,
      child: Container(
        width: buttonSize,
        height: buttonSize,
        alignment: Alignment.center,
        decoration: ShellStyles.iconBadgeDecoration(
          context,
          color: ShellStyles.surface(context),
          radius: buttonSize / 2,
        ),
        child: child ?? Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }

  Widget _buildMonthlySummaryCard(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonthStart);
    final ratio = _changeRatio;
    final positiveDelta = ratio != null && ratio < 0;
    final transactionCount = _currentMonthTransactions.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                monthLabel.toUpperCase(),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (ratio != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (positiveDelta
                                ? ShellColors.softGreen
                                : ShellColors.softRed)
                            .withAlpha(25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        positiveDelta
                            ? CupertinoIcons.arrow_down_right
                            : CupertinoIcons.arrow_up_right,
                        size: 12,
                        color: positiveDelta
                            ? ShellColors.softGreen
                            : ShellColors.softRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _changeLabel(context),
                        style: TextStyle(
                          color: positiveDelta
                              ? ShellColors.softGreen
                              : ShellColors.softRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _formatMoney(_currency, _currentMonthTotal),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 46,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                context.tr('home_total_spending_month'),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr(
                  'receipts_count',
                  params: {'count': transactionCount.toString()},
                ),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _open(context, const ReceiptUploadScreen()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        decoration: BoxDecoration(
          color: ShellStyles.textPrimary(context),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                AppIcons.scan,
                color: ShellStyles.surface(context),
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Primary action',
                    style: TextStyle(
                      color: ShellStyles.surface(context).withAlpha(170),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('tools_scan_receipt'),
                    style: TextStyle(
                      color: ShellStyles.surface(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('home_scan_receipt_subtitle'),
                    style: TextStyle(
                      color: ShellStyles.surface(context).withAlpha(160),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.chevronRight,
                color: ShellStyles.surface(context),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    final slices = _overviewSlices(context);
    final hasChartData = slices.isNotEmpty && _currentMonthTotal > 0;

    final pieSections = hasChartData
        ? slices
              .map(
                (slice) => PieChartSectionData(
                  value: slice.amount,
                  color: slice.color,
                  title: '',
                  radius: 20,
                ),
              )
              .toList()
        : [
            PieChartSectionData(
              value: 1,
              color: ShellStyles.border(context),
              title: '',
              radius: 20,
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr('home_spending_overview'),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                context.tr('period_this_month'),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 65,
                    startDegreeOffset: -90,
                    sections: pieSections,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('analytics_total_spent').toUpperCase(),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatMoney(_currency, _currentMonthTotal),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (hasChartData) ...[
            for (final slice in slices.where(
              (s) => s.name != context.tr('taxonomy_other'),
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Text(
                        slice.name,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${slice.percentage.round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatMoney(_currency, slice.amount),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  context.tr('home_no_spending_data'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              onTap: () => _open(context, const AnalyticsScreen()),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('home_view_all'),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      AppIcons.chevronRight,
                      size: 12,
                      color: ShellStyles.textMuted(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsCard(BuildContext context) {
    final insights = _buildInsights(context);
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 20,
        color: ShellStyles.surfaceAlt(context),
        withShadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.insight,
                size: 18,
                color: ShellStyles.textMuted(context),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('home_smart_insights'),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 10),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ShellStyles.textMuted(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      insight,
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(
        icon: AppIcons.add,
        label: context.tr('home_add_expense'),
        onTap: () => _open(context, const TransactionEditScreen.create()),
      ),
      _QuickAction(
        icon: AppIcons.receipt,
        label: context.tr('nav_receipts'),
        onTap: () => _open(context, const ReceiptManagerScreen()),
      ),
      _QuickAction(
        icon: AppIcons.analytics,
        label: context.tr('tools_analytics'),
        onTap: () => _open(context, const AnalyticsScreen()),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              SizedBox(
                width: cardWidth,
                child: _buildQuickActionCard(context, action),
              ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActionCard(BuildContext context, _QuickAction action) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: action.onTap,
      child: Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: ShellStyles.cardDecoration(context, radius: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ShellStyles.surfaceAlt(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                action.icon,
                color: ShellStyles.textMuted(context),
                size: 15,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Column(
      children: [
        _buildSkeletonCard(context, height: 128),
        const SizedBox(height: 14),
        _buildSkeletonCard(context, height: 84),
        const SizedBox(height: 14),
        _buildSkeletonCard(context, height: 360),
      ],
    );
  }

  Widget _buildSkeletonCard(BuildContext context, {required double height}) {
    return Container(
      height: height,
      decoration: ShellStyles.cardDecoration(
        context,
        color: ShellStyles.surface(context),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.cardDecoration(context),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            color: ShellColors.softRed,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            _error ?? 'Home could not refresh just now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ShellStyles.textPrimary(context)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadHomeData,
            child: Text(context.tr('common_retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineWarning(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShellColors.softRed.withAlpha(22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShellColors.softRed.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.info, color: ShellColors.softRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error ?? context.tr('common_error'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSlice {
  const _OverviewSlice({
    required this.name,
    required this.amount,
    required this.percentage,
    required this.color,
  });

  final String name;
  final double amount;
  final double percentage;
  final Color color;
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
