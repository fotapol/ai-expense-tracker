// TODO(household): disabled for single-user launch

import 'package:flutter/material.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/money_formatter.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'household_screen.dart';
import 'subscription_screen.dart';

class AnalyticsHouseholdTab extends StatefulWidget {
  const AnalyticsHouseholdTab({
    super.key,
    required this.filters,
    required this.currentHousehold,
    required this.hasFamilyPlan,
    required this.onHouseholdUpdated,
  });

  final AnalyticsFilters filters;
  final Map<String, dynamic>? currentHousehold;
  final bool hasFamilyPlan;
  final Future<void> Function() onHouseholdUpdated;

  @override
  State<AnalyticsHouseholdTab> createState() => _AnalyticsHouseholdTabState();
}

class _AnalyticsHouseholdTabState extends State<AnalyticsHouseholdTab> {
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didUpdateWidget(covariant AnalyticsHouseholdTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters ||
        oldWidget.currentHousehold?['id']?.toString() !=
            widget.currentHousehold?['id']?.toString() ||
        oldWidget.hasFamilyPlan != widget.hasFamilyPlan) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    if (widget.currentHousehold == null) {
      setState(() {
        _data = null;
        _error = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.getHouseholdAnalyticsSummary(
        fromDate: PeriodFilter.getStartDate(widget.filters.period),
        toDate: PeriodFilter.getEndDate(widget.filters.period),
        categoryIds: widget.filters.categoryIds.isNotEmpty
            ? widget.filters.categoryIds
            : null,
        subcategoryIds: widget.filters.subcategoryIds.isNotEmpty
            ? widget.filters.subcategoryIds
            : null,
        labelIds: widget.filters.labelIds.isNotEmpty
            ? widget.filters.labelIds
            : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentHousehold == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildEmptyState(context),
        ],
      );
    }

    if (_isLoading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: ShellColors.softRed,
                size: 42,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? context.tr('common_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: ShellStyles.textMuted(context)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _fetchData,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data ?? const <String, dynamic>{};
    final currency = (data['currency']?.toString() ?? 'EUR').toUpperCase();
    final totalAmount = _parseDouble(data['total_amount']);
    final totalTransactions = (data['total_transactions'] as num?)?.toInt() ?? 0;
    final members = data['members'] as List<dynamic>? ?? const <dynamic>[];

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildHeaderCard(
            context,
            currency: currency,
            totalAmount: totalAmount,
            totalTransactions: totalTransactions,
          ),
          const SizedBox(height: 16),
          if (members.isEmpty)
            _buildNoDataCard(context)
          else
            ...members.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: entry.key == members.length - 1 ? 0 : 14),
                child: _buildMemberCard(
                  context,
                  rank: entry.key + 1,
                  currency: currency,
                  member: entry.value as Map<String, dynamic>,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: ShellStyles.cardDecoration(context, radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.group_outlined, color: ShellColors.softGreen),
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('analytics_household_empty_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('analytics_household_empty_subtitle'),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                  );
                  await widget.onHouseholdUpdated();
                },
                child: Text(context.tr('household_open_screen')),
              ),
              if (!widget.hasFamilyPlan)
                OutlinedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                    );
                    await widget.onHouseholdUpdated();
                  },
                  child: Text(context.tr('household_upgrade_cta')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: ShellStyles.cardDecoration(context, radius: 24),
      child: Column(
        children: [
          Icon(Icons.insert_chart_outlined, color: ShellStyles.textMuted(context)),
          const SizedBox(height: 12),
          Text(
            context.tr('analytics_household_no_data'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('analytics_household_no_data_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: ShellStyles.textMuted(context)),
          ),
        ],
      ),
    );
  }

  double _parseDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String currency,
    required double totalAmount,
    required int totalTransactions,
  }) {
    final householdName =
        widget.currentHousehold?['name']?.toString() ??
        context.tr('analytics_tab_households');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E5B4E), Color(0xFF1F433A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  householdName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                  );
                  await widget.onHouseholdUpdated();
                },
                icon: const Icon(Icons.open_in_new, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(currency, totalAmount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
              'analytics_household_total_transactions',
              params: {'count': totalTransactions.toString()},
            ),
            style: TextStyle(
              color: Colors.white.withAlpha(190),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context, {
    required int rank,
    required String currency,
    required Map<String, dynamic> member,
  }) {
    final displayName = member['user']?['display_name']?.toString().trim();
    final email = member['user']?['email']?.toString().trim();
    final label = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (email != null && email.isNotEmpty)
              ? email
              : context.tr('home_default_user');
    final totalAmount = _parseDouble(member['total_amount']);
    final percentage = _parseDouble(member['percentage']);
    final transactionCount =
        (member['transaction_count'] as num?)?.toInt() ?? 0;
    final topCategory = member['top_category'] as Map<String, dynamic>?;
    final topCategoryName =
        topCategory?['name']?.toString() ??
        context.tr('analytics_household_top_category_unknown');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: ShellStyles.cardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ShellStyles.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatMoney(currency, totalAmount),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: (percentage / 100).clamp(0.0, 1.0),
              backgroundColor: ShellStyles.surfaceAlt(context),
              valueColor: const AlwaysStoppedAnimation<Color>(ShellColors.softGreen),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr(
                  'analytics_household_member_transactions',
                  params: {'count': transactionCount.toString()},
                ),
                style: TextStyle(color: ShellStyles.textMuted(context)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
              'analytics_household_top_category',
              params: {'category': topCategoryName},
            ),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
