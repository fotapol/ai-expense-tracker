import 'package:flutter/material.dart';

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
  return date == null ? '—' : formatLocalizedDayMonthTime(context, date);
}

String _confidence(BuildContext context, Map<String, dynamic> pair) =>
    context.tr(switch (pair['confidence']) {
      'exact' => 'duplicates_exact',
      'high' => 'duplicates_high',
      _ => 'duplicates_possible',
    });

String _reasons(BuildContext context, Map<String, dynamic> pair) {
  const labels = {
    'same_image': 'duplicates_reason_image',
    'same_total': 'duplicates_reason_total',
    'same_date': 'duplicates_reason_date',
    'nearby_dates': 'duplicates_reason_nearby',
    'similar_merchant': 'duplicates_reason_merchant',
    'matching_items': 'duplicates_reason_items',
  };
  return (pair['reasons'] as List? ?? [])
      .where(labels.containsKey)
      .map(
        (reason) => context.tr(
          labels[reason]!,
          params: {'count': '${pair['matching_item_count'] ?? 0}'},
        ),
      )
      .join(' · ');
}

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
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null) ...[
                    Text(_error!, textAlign: TextAlign.center),
                    TextButton(
                      onPressed: () => _load(reset: true),
                      child: Text(context.tr('common_retry')),
                    ),
                  ] else ...[
                    const Icon(Icons.check_circle_outline, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('duplicates_empty'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _pairs.length + 1,
                itemBuilder: (context, index) {
                  if (index == _pairs.length) {
                    return Column(
                      children: [
                        if (_error != null) Text(_error!),
                        if (_loading)
                          const Center(child: CircularProgressIndicator())
                        else if (_hasMore || _error != null)
                          TextButton(
                            onPressed: () => _load(),
                            child: Text(
                              context.tr(
                                _error == null
                                    ? 'receipts_load_more'
                                    : 'common_retry',
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                  final pair = _pairs[index];
                  final first = pair['first'] as Map<String, dynamic>;
                  final second = pair['second'] as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      key: ValueKey('duplicate-${first['id']}-${second['id']}'),
                      contentPadding: const EdgeInsets.all(16),
                      leading: const Icon(Icons.content_copy_outlined),
                      title: Text(_confidence(context, pair)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${_merchant(context, first)} · ${_money(first)}\n${_date(context, first)}\n'
                          '${_merchant(context, second)} · ${_money(second)}\n${_date(context, second)}\n\n${_reasons(context, pair)}',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _review(pair),
                    ),
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

  Widget _card(Map<String, dynamic> tx) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: ValueKey('select-${tx['id']}'),
          selected: tx['id'] == _keepId,
          leading: Icon(
            tx['id'] == _keepId
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          title: Text(_merchant(context, tx)),
          subtitle: Text('${_money(tx)}\n${_date(context, tx)}'),
          onTap: _busy
              ? null
              : () => setState(() => _keepId = tx['id'].toString()),
        ),
        if (tx['receipt_id'] != null)
          TextButton.icon(
            onPressed: _busy ? null : () => _photo(tx),
            icon: const Icon(Icons.receipt_long),
            label: Text(context.tr('duplicates_view_original')),
          ),
        ExpansionTile(
          title: Text(
            '${context.tr('transaction_items_heading')} (${(tx['items'] as List? ?? []).length})',
          ),
          children: [
            for (final item in tx['items'] as List? ?? [])
              ListTile(
                dense: true,
                title: Text(item['description']?.toString() ?? ''),
                subtitle: item['qty'] == null
                    ? null
                    : Text('${item['qty']} ${item['unit'] ?? ''}'),
                trailing: Text(
                  formatMoney(
                    tx['currency'].toString(),
                    double.tryParse(item['amount'].toString()) ?? 0,
                  ),
                ),
              ),
          ],
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const ValueKey('duplicate-comparison-list'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _confidence(context, widget.pair),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(_reasons(context, widget.pair)),
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
                const SizedBox(height: 16),
                Text(context.tr('duplicates_choose')),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy || _keepId == null || _error != null
                      ? null
                      : _keepSelected,
                  child: Text(context.tr('duplicates_keep_selected')),
                ),
                OutlinedButton(
                  onPressed: _busy || _transactions.length != 2
                      ? null
                      : _keepBoth,
                  child: Text(context.tr('duplicates_keep_both')),
                ),
                if (_busy) const Center(child: CircularProgressIndicator()),
              ],
            ),
    ),
  );
}
