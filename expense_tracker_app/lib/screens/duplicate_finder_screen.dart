import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/duplicate_comparison.dart';
import '../widgets/duplicate_details_comparison.dart';
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

Widget _purchaseSummary(
  BuildContext context,
  Map<String, dynamic> tx, {
  int? number,
}) => Padding(
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
        child: number != null
            ? Text(
                MaterialLocalizations.of(context).formatDecimal(number),
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : Icon(
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

  Future<void> _review(List<Map<String, dynamic>> pairs) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _DuplicateComparisonScreen(pairs: pairs),
      ),
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

  Widget _intro() => Container(
    margin: const EdgeInsets.only(top: 8, bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: ShellStyles.cardDecoration(
      context,
      radius: 18,
      withShadow: false,
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: ShellStyles.accentTone(context).container,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.content_copy_outlined,
            size: 22,
            color: ShellStyles.accentTone(context).foreground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.tr('duplicates_subtitle'),
            style: TextStyle(
              color: ShellStyles.textSecondary(context),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: Container(
      key: const ValueKey('duplicate-finder-status'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 22,
        withShadow: false,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: ShellStyles.accentTone(context).container,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _error == null
                    ? Icons.check_circle_outline
                    : Icons.cloud_off_outlined,
                size: 36,
                color: ShellStyles.accentTone(context).foreground,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error ?? context.tr('duplicates_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _load(reset: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                _error == null
                    ? MaterialLocalizations.of(
                        context,
                      ).refreshIndicatorSemanticLabel
                    : context.tr('common_retry'),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _reviewGroup(List<Map<String, dynamic>> pairs) async {
    final members = <String, int>{};
    for (final pair in pairs) {
      for (final side in ['first', 'second']) {
        final id = pair[side]['id'].toString();
        members.putIfAbsent(id, () => members.length + 1);
      }
    }
    final numbered = [
      for (final pair in pairs)
        {
          ...pair,
          'first_number': members[pair['first']['id'].toString()],
          'second_number': members[pair['second']['id'].toString()],
        },
    ];
    int strength(Map<String, dynamic> pair) => switch (pair['confidence']) {
      'exact' => 0,
      'high' => 1,
      _ => 2,
    };
    numbered.sort((a, b) => strength(a).compareTo(strength(b)));
    await _review(numbered);
  }

  Widget _groupCard(List<Map<String, dynamic>> pairs) {
    final members = <String, Map<String, dynamic>>{};
    for (final pair in pairs) {
      for (final side in ['first', 'second']) {
        final tx = Map<String, dynamic>.from(pair[side] as Map);
        members[tx['id'].toString()] = tx;
      }
    }
    final pair = {
      ...pairs.first,
      'confidence': pairs.every((p) => p['confidence'] == 'exact')
          ? 'exact'
          : pairs.every((p) => p['confidence'] != 'possible')
          ? 'high'
          : 'possible',
    };
    return Container(
      key: ValueKey('duplicate-group-${members.keys.toList()..sort()}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 16,
        withShadow: false,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey(
            'duplicate-${pair['first']['id']}-${pair['second']['id']}',
          ),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _reviewGroup(pairs),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                if (members.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.tr(
                        'duplicates_group_count',
                        params: {
                          'count': MaterialLocalizations.of(
                            context,
                          ).formatDecimal(members.length),
                        },
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: ShellStyles.border(context)),
                  _purchaseSummary(
                    context,
                    members.values.elementAt(i),
                    number: members.length > 2 ? i + 1 : null,
                  ),
                ],
                Text(
                  members.length > 2
                      ? context.tr('duplicates_review')
                      : _reasons(context, pair),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12,
                    height: 1.35,
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
  Widget build(BuildContext context) {
    final groups = duplicateGroups(_pairs);
    return PopScope<List<String>>(
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
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: CustomScrollView(
              key: const ValueKey('duplicate-finder-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(child: _intro()),
                ),
                if (groups.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: groups.length,
                      itemBuilder: (context, index) =>
                          _groupCard(groups[index]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(_error!, textAlign: TextAlign.center),
                            ),
                          if (!_loading && (_hasMore || _error != null))
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _load(),
                                icon: Icon(
                                  _error == null
                                      ? Icons.expand_more
                                      : Icons.refresh,
                                ),
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
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DuplicateComparisonScreen extends StatefulWidget {
  const _DuplicateComparisonScreen({required this.pairs});
  final List<Map<String, dynamic>> pairs;
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
  int _pairIndex = 0;
  int _request = 0;
  Map<String, dynamic> get _pair => widget.pairs[_pairIndex];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    final pair = _pair;
    setState(() {
      _transactions = [];
      _loading = true;
      _error = null;
      _keepId = null;
    });
    try {
      final rows = await Future.wait([
        ApiClient.getTransaction(pair['first']['id'].toString()),
        ApiClient.getTransaction(pair['second']['id'].toString()),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _transactions = rows;
        _loading = false;
      });
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      if (mounted && request == _request) {
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

  Widget _actions() => LayoutBuilder(
    builder: (context, constraints) {
      final selected = _transactions.indexWhere((tx) => tx['id'] == _keepId);
      final number = selected == 0
          ? _pair['first_number'] ?? 1
          : _pair['second_number'] ?? 2;
      final selectionLabel = selected < 0
          ? context.tr('duplicates_choose')
          : '${context.tr('duplicates_receipt_number', params: {'number': MaterialLocalizations.of(context).formatDecimal(number as int)})} · ${_money(_transactions[selected])}';
      final style = Theme.of(
        context,
      ).textTheme.labelLarge!.copyWith(fontSize: 13);
      double width(String key) {
        final painter = TextPainter(
          text: TextSpan(text: context.tr(key), style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final result = painter.width;
        painter.dispose();
        return result;
      }

      final primaryWidth = width('duplicates_keep_selected') + 60;
      final secondaryWidth = width('duplicates_keep_both') + 32;
      final primary = FilledButton.icon(
        onPressed: _busy || _keepId == null || _error != null
            ? null
            : _keepSelected,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          textStyle: style,
        ),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check, size: 20),
        label: Text(context.tr('duplicates_keep_selected')),
      );
      final secondary = OutlinedButton(
        onPressed: _busy || _transactions.length != 2 ? null : _keepBoth,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          textStyle: style,
        ),
        child: Text(context.tr('duplicates_keep_both')),
      );
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          border: Border(top: BorderSide(color: ShellStyles.border(context))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selectionLabel,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            if (primaryWidth + secondaryWidth + 8 <= constraints.maxWidth - 32)
              Row(
                children: [
                  Expanded(child: secondary),
                  const SizedBox(width: 8),
                  SizedBox(width: primaryWidth, child: primary),
                ],
              )
            else ...[
              primary,
              const SizedBox(height: 8),
              secondary,
            ],
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('duplicates_review')),
        bottom: widget.pairs.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('duplicate-previous-comparison'),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).previousPageTooltip,
                        onPressed: _busy || _pairIndex == 0
                            ? null
                            : () {
                                setState(() => _pairIndex--);
                                _load();
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          context.tr(
                            'duplicates_comparison_count',
                            params: {
                              'current': MaterialLocalizations.of(
                                context,
                              ).formatDecimal(_pairIndex + 1),
                              'count': MaterialLocalizations.of(
                                context,
                              ).formatDecimal(widget.pairs.length),
                            },
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('duplicate-next-comparison'),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).nextPageTooltip,
                        onPressed:
                            _busy || _pairIndex == widget.pairs.length - 1
                            ? null
                            : () {
                                setState(() => _pairIndex++);
                                _load();
                              },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      bottomNavigationBar: !_loading && _transactions.isNotEmpty
          ? SafeArea(top: false, child: _actions())
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
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _confidenceBadge(context, _pair),
                      const SizedBox(height: 12),
                      Text(
                        _reasons(context, _pair),
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
                if (_transactions.length == 2)
                  DuplicateDetailsComparison(
                    numbers: [
                      (_pair['first_number'] as int?) ?? 1,
                      (_pair['second_number'] as int?) ?? 2,
                    ],
                    transactions: _transactions,
                    selectedId: _keepId,
                    busy: _busy,
                    onSelect: (id) => setState(() => _keepId = id),
                    onPhoto: _photo,
                  ),
              ],
            ),
    ),
  );
}
