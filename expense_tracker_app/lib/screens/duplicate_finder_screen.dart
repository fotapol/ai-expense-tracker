import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/localized_dates.dart';
import '../core/money_formatter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';
import 'receipt_photo_view_screen.dart';

String _merchant(BuildContext context, Map<String, dynamic> tx) {
  final name = tx['merchant_name']?.toString().trim() ?? '';
  return name.isEmpty ? context.tr('receipts_unknown_store') : name;
}

String _money(Map<String, dynamic> tx) => tx['amount_total'] == null
    ? '— ${tx['currency'] ?? ''}'
    : formatMoney(
        tx['currency']?.toString() ?? '',
        double.tryParse(tx['amount_total']?.toString() ?? '') ?? 0,
      );

String _date(BuildContext context, Map<String, dynamic> tx) {
  final date = DateTime.tryParse((tx['occurred_at'] ?? '').toString());
  return date == null
      ? '—'
      : formatLocalizedDayMonthYearTime(context, date.toLocal());
}

String _confidence(BuildContext context, Map<String, dynamic> pair) =>
    context.tr(switch (pair['confidence']) {
      'exact' => 'duplicates_exact',
      'high' => 'duplicates_high',
      _ => 'duplicates_possible',
    });

String _reasons(BuildContext context, Map<String, dynamic> pair) {
  final labels = {
    'same_image': 'duplicates_reason_image',
    'same_total': 'duplicates_reason_total',
    'same_date': 'duplicates_reason_date',
    'nearby_dates': 'duplicates_reason_nearby',
    'similar_merchant': 'duplicates_reason_merchant',
    'matching_items': pair['matching_item_count'] == 1
        ? 'duplicates_reason_item_single'
        : 'duplicates_reason_items',
  };
  return (pair['reasons'] as List? ?? [])
      .where(labels.containsKey)
      .map(
        (reason) => context.tr(
          labels[reason]!,
          params: {
            'count': MaterialLocalizations.of(
              context,
            ).formatDecimal((pair['matching_item_count'] as num? ?? 0).toInt()),
          },
        ),
      )
      .join(' · ');
}

Widget _confidenceBadge(BuildContext context, Map<String, dynamic> pair) {
  final tone = ShellStyles.accentTone(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: tone.container,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          pair['confidence'] == 'exact'
              ? Icons.verified_outlined
              : Icons.content_copy_outlined,
          size: 16,
          color: tone.foreground,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            _confidence(context, pair),
            style: TextStyle(
              color: tone.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _purchaseSummary(BuildContext context, Map<String, dynamic> tx) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: ShellStyles.textMuted(context),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _merchant(context, tx),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _money(tx),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _date(context, tx),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key, this.transactionId});
  final String? transactionId;

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  List<Map<String, dynamic>> _pairs = [];
  final _deletedIds = <String>{};
  int _page = 1;
  int _request = 0;
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final request = reset ? ++_request : _request;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _pairs = [];
      }
    });
    try {
      final data = await ApiClient.listDuplicates(
        page: _page,
        transactionId: widget.transactionId,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _pairs = [
          ..._pairs,
          ...List<Map<String, dynamic>>.from(data['items'] ?? []),
        ];
        _page++;
        _hasMore = data['has_more'] == true;
        _loading = false;
      });
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = context.tr('duplicates_error');
      });
    }
  }

  void _finish() => Navigator.pop(context, _deletedIds.toList());

  Future<void> _review(Map<String, dynamic> pair) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _DuplicateComparisonScreen(pair: pair)),
    );
    if (!mounted || result == null) return;
    if (result.isNotEmpty) _deletedIds.add(result);
    if (_deletedIds.contains(widget.transactionId)) {
      _finish();
    } else {
      // Removal changes offsets. Refresh from page one so no remaining match is skipped.
      await _load(reset: true);
    }
  }

  Widget _intro() => Padding(
    padding: const EdgeInsets.only(bottom: 20, top: 4),
    child: Text(
      context.tr('duplicates_subtitle'),
      style: TextStyle(
        color: ShellStyles.textMuted(context),
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );

  Widget _pairCard(Map<String, dynamic> pair) {
    final first = pair['first'] as Map<String, dynamic>;
    final second = pair['second'] as Map<String, dynamic>;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 20,
        withShadow: false,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('duplicate-${first['id']}-${second['id']}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _review(pair),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _confidenceBadge(context, pair),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: ShellStyles.textMuted(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _purchaseSummary(context, first),
                Divider(height: 1, color: ShellStyles.border(context)),
                _purchaseSummary(context, second),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ShellStyles.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _reasons(context, pair),
                    style: TextStyle(
                      color: ShellStyles.textSecondary(context),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<List<String>>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _finish();
    },
    child: Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('duplicates_title')),
        leading: BackButton(onPressed: _finish),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _pairs.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    _intro(),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 150).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_loading)
                              const CircularProgressIndicator()
                            else ...[
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: ShellStyles.iconBadgeDecoration(
                                  context,
                                  color: ShellStyles.surfaceAlt(context),
                                  radius: 28,
                                ),
                                child: Icon(
                                  _error == null
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.error_outline_rounded,
                                  size: 40,
                                  color: ShellStyles.textMuted(context),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _error ?? context.tr('duplicates_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () => _load(reset: true),
                                  child: Text(context.tr('common_retry')),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _pairs.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) return _intro();
                  if (index <= _pairs.length) {
                    return _pairCard(_pairs[index - 1]);
                  }
                  return Column(
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else if (_hasMore || _error != null)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _load(),
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              context.tr(
                                _error == null
                                    ? 'receipts_load_more'
                                    : 'common_retry',
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    ),
  );
}

class _DuplicateComparisonScreen extends StatefulWidget {
  const _DuplicateComparisonScreen({required this.pair});
  final Map<String, dynamic> pair;
  @override
  State<_DuplicateComparisonScreen> createState() =>
      _DuplicateComparisonScreenState();
}

class _DuplicateComparisonScreenState
    extends State<_DuplicateComparisonScreen> {
  List<Map<String, dynamic>> _transactions = [];
  String? _keepId;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _keepId = null;
    });
    try {
      final rows = await Future.wait([
        ApiClient.getTransaction(widget.pair['first']['id'].toString()),
        ApiClient.getTransaction(widget.pair['second']['id'].toString()),
      ]);
      if (!mounted) return;
      setState(() {
        _transactions = rows;
        _loading = false;
      });
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      if (mounted) {
        setState(() {
          _error = context.tr('duplicates_error');
          _loading = false;
        });
      }
    }
  }

  Future<void> _photo(Map<String, dynamic> tx) async {
    setState(() => _busy = true);
    try {
      final photo = await ApiClient.getReceiptViewUrl(
        tx['receipt_id'].toString(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPhotoViewScreen(
            title: _merchant(context, tx),
            viewUrl: photo['view_url'].toString(),
            mimeType: photo['mime_type'].toString(),
          ),
        ),
      );
    } catch (e) {
      await _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showError(Object error) async {
    if (await maybeHandleExpiredSession(error)) return;
    if (!mounted) return;
    setState(
      () => _error = context.tr(
        error is DuplicateConflictException
            ? 'duplicates_stale'
            : 'duplicates_error',
      ),
    );
  }

  Future<void> _keepBoth() async {
    setState(() => _busy = true);
    try {
      await ApiClient.dismissDuplicate(
        _transactions[0]['id'].toString(),
        _transactions[1]['id'].toString(),
      );
      if (mounted) Navigator.pop(context, '');
    } catch (e) {
      await _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _keepSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('duplicates_keep_selected')),
        content: Text(context.tr('duplicates_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final keep = _transactions.firstWhere((tx) => tx['id'] == _keepId);
    final discard = _transactions.firstWhere((tx) => tx['id'] != _keepId);
    setState(() => _busy = true);
    try {
      final result = await ApiClient.resolveDuplicate(
        keepId: keep['id'].toString(),
        discardId: discard['id'].toString(),
        keepUpdatedAt: keep['updated_at'].toString(),
        discardUpdatedAt: discard['updated_at'].toString(),
      );
      if (mounted) {
        Navigator.pop(context, result['deleted_transaction_id'].toString());
      }
    } catch (e) {
      await _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(Map<String, dynamic> tx) {
    final selected = tx['id'] == _keepId;
    final tone = ShellStyles.accentTone(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: selected
            ? tone.container.withAlpha(90)
            : ShellStyles.surface(context),
        border: Border.all(
          color: selected ? tone.base : ShellStyles.border(context),
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              key: ValueKey('select-${tx['id']}'),
              borderRadius: BorderRadius.circular(20),
              onTap: _busy
                  ? null
                  : () => setState(() => _keepId = tx['id'].toString()),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? tone.base
                          : ShellStyles.textMuted(context),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _merchant(context, tx),
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _money(tx),
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _date(context, tx),
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (tx['receipt_id'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _photo(tx),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(context.tr('duplicates_view_original')),
                ),
              ),
            ),
          ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              '${context.tr('transaction_items_heading')} (${MaterialLocalizations.of(context).formatDecimal((tx['items'] as List? ?? []).length)})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            children: [
              for (final item in tx['items'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(item['description']?.toString() ?? ''),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (item['qty'] != null)
                            Text(
                              '${NumberFormat.decimalPattern(Localizations.localeOf(context).languageCode).format(num.tryParse(item['qty'].toString()) ?? 0)} ${item['unit'] ?? ''}',
                              style: TextStyle(
                                color: ShellStyles.textMuted(context),
                              ),
                            ),
                          Text(
                            formatMoney(
                              tx['currency'].toString(),
                              double.tryParse(item['amount'].toString()) ?? 0,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions() => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: BoxDecoration(
      color: ShellStyles.surface(context),
      border: Border(top: BorderSide(color: ShellStyles.border(context))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('duplicates_choose'),
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy || _keepId == null || _error != null
              ? null
              : _keepSelected,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 20),
          label: Text(context.tr('duplicates_keep_selected')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy || _transactions.length != 2 ? null : _keepBoth,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(context.tr('duplicates_keep_both')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(title: Text(context.tr('duplicates_review'))),
      bottomNavigationBar: !_loading && _transactions.isNotEmpty
          ? _actions()
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const ValueKey('duplicate-comparison-list'),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: ShellStyles.cardDecoration(
                    context,
                    radius: 18,
                    withShadow: false,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _confidenceBadge(context, widget.pair),
                      const SizedBox(height: 12),
                      Text(
                        _reasons(context, widget.pair),
                        style: TextStyle(
                          color: ShellStyles.textSecondary(context),
                          height: 1.5,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: Text(context.tr('common_retry')),
                  ),
                ],
                ..._transactions.map(_card),
              ],
            ),
    ),
  );
}
