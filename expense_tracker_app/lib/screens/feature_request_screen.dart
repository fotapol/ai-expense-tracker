import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class FeatureRequestScreen extends StatefulWidget {
  const FeatureRequestScreen({super.key});

  @override
  State<FeatureRequestScreen> createState() => _FeatureRequestScreenState();
}

class _FeatureRequestScreenState extends State<FeatureRequestScreen> {
  static const List<String> _categories = [
    'analytics_reports',
    'receipts_scanning',
    'budgets_planning',
    'household_sharing',
    'design_accessibility',
    'other',
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showComposer = false;
  String? _error;
  String _selectedCategory = _categories.first;
  List<_FeatureRequestItem> _publicRequests = const [];
  List<_FeatureRequestItem> _myRequests = const [];
  Set<String> _voteLoadingIds = const {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([
        ApiClient.listFeatureRequests(),
        ApiClient.listMyFeatureRequests(),
      ]);
      final publicResults = results[0];
      final myResults = results[1];
      if (!mounted) return;
      setState(() {
        _publicRequests = publicResults
            .whereType<Map<String, dynamic>>()
            .map(_FeatureRequestItem.fromPublicJson)
            .toList(growable: false);
        _myRequests = myResults
            .whereType<Map<String, dynamic>>()
            .map(_FeatureRequestItem.fromMineJson)
            .toList(growable: false);
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString();
      });
    }
  }

  void _toggleComposer() {
    setState(() => _showComposer = !_showComposer);
  }

  String _normalizeTitle(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeDescription(String value) {
    final normalizedLines = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
    return normalizedLines.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  Future<void> _submitRequest() async {
    final normalizedTitle = _normalizeTitle(_titleController.text);
    final normalizedDescription = _normalizeDescription(
      _descriptionController.text,
    );

    if (normalizedTitle.length < 3 || normalizedTitle.length > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('feature_request_title_length_error')),
        ),
      );
      return;
    }
    if (normalizedDescription.length < 10 ||
        normalizedDescription.length > 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('feature_request_description_length_error')),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final created = await ApiClient.createFeatureRequest(
        title: normalizedTitle,
        category: _selectedCategory,
        description: normalizedDescription,
      );
      if (!mounted) return;

      final item = _FeatureRequestItem.fromMineJson(created);
      setState(() {
        _myRequests = [item, ..._myRequests];
        _titleController.clear();
        _descriptionController.clear();
        _selectedCategory = _categories.first;
        _showComposer = false;
        _isSubmitting = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('feature_request_submit_success'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
          backgroundColor: ShellColors.softRed,
        ),
      );
    }
  }

  List<_FeatureRequestItem> _replaceItem(
    List<_FeatureRequestItem> items,
    _FeatureRequestItem replacement,
  ) {
    var found = false;
    final updated = items
        .map((item) {
          if (item.id != replacement.id) return item;
          found = true;
          return replacement;
        })
        .toList(growable: false);
    return found ? updated : items;
  }

  void _applyItemUpdate(_FeatureRequestItem item) {
    setState(() {
      _publicRequests = _replaceItem(_publicRequests, item);
      _myRequests = _replaceItem(_myRequests, item);
    });
  }

  Future<void> _toggleVote(_FeatureRequestItem item) async {
    if (_voteLoadingIds.contains(item.id)) return;

    final targetVoted = !item.viewerHasVoted;
    final previous = item;
    final optimistic = item.copyWith(
      voteCount: math.max(0, item.voteCount + (targetVoted ? 1 : -1)),
      viewerHasVoted: targetVoted,
    );

    setState(() {
      _voteLoadingIds = {..._voteLoadingIds, item.id};
      _publicRequests = _replaceItem(_publicRequests, optimistic);
      _myRequests = _replaceItem(_myRequests, optimistic);
    });

    try {
      final payload = await ApiClient.updateFeatureRequestVote(
        featureRequestId: item.id,
        voted: targetVoted,
      );
      if (!mounted) return;
      _applyItemUpdate(
        optimistic.copyWith(
          voteCount:
              int.tryParse(payload['vote_count']?.toString() ?? '') ??
              optimistic.voteCount,
          viewerHasVoted: payload['viewer_has_voted'] as bool? ?? targetVoted,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _applyItemUpdate(previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
          backgroundColor: ShellColors.softRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _voteLoadingIds = _voteLoadingIds
              .where((requestId) => requestId != item.id)
              .toSet();
        });
      }
    }
  }

  String _categoryLabel(String category) {
    return context.tr('feature_request_category_$category');
  }

  Color _statusColor(_FeatureRequestItem item) {
    switch (item.displayState) {
      case 'in_progress':
        return const Color(0xFF3D6CFF);
      case 'planned':
        return const Color(0xFFA04DF0);
      case 'completed':
        return ShellColors.softGreen;
      case 'rejected':
        return ShellColors.softRed;
      case 'pending':
      case 'under_review':
      default:
        return const Color(0xFFF5A313);
    }
  }

  String _statusLabel(_FeatureRequestItem item) {
    switch (item.displayState) {
      case 'in_progress':
        return context.tr('feature_request_status_in_progress');
      case 'planned':
        return context.tr('feature_request_status_planned');
      case 'completed':
        return context.tr('feature_request_status_completed');
      case 'rejected':
        return context.tr('feature_request_status_rejected');
      case 'pending':
        return context.tr('feature_request_status_pending');
      case 'under_review':
      default:
        return context.tr('feature_request_status_under_review');
    }
  }

  String _groupTitle(String moderationState) {
    switch (moderationState) {
      case 'approved':
        return context.tr('feature_request_group_approved');
      case 'rejected':
        return context.tr('feature_request_group_rejected');
      case 'pending':
      default:
        return context.tr('feature_request_group_pending');
    }
  }

  Widget _buildComposerCard() {
    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: ShellStyles.iconBadgeDecoration(
                  context,
                  radius: 11,
                ),
                child: Icon(
                  AppIcons.feature,
                  color: ShellStyles.textPrimary(context),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('feature_request_submit_title'),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _fieldLabel(context.tr('feature_request_title_label')),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: context.tr('feature_request_title_hint'),
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel(context.tr('feature_request_category_label')),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            items: _categories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(_categoryLabel(category)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCategory = value);
            },
          ),
          const SizedBox(height: 12),
          _fieldLabel(context.tr('feature_request_description_label')),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionController,
            minLines: 5,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: context.tr('feature_request_description_hint'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ShellStyles.surface(context),
                      ),
                    )
                  : Text(context.tr('feature_request_submit_action')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard({required String title, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: ShellStyles.iconBadgeDecoration(context, radius: 14),
            child: Icon(
              AppIcons.feature,
              size: 18,
              color: ShellStyles.textMuted(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 18,
        color: ShellStyles.surface(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('feature_request_load_error_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? context.tr('common_error'),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _loadData,
            child: Text(context.tr('common_retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList(List<_FeatureRequestItem> items) {
    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _buildRequestRow(items[index]),
            if (index != items.length - 1)
              Divider(
                height: 1,
                color: ShellStyles.border(context),
                indent: 14,
                endIndent: 14,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestRow(_FeatureRequestItem item) {
    final isVoteLoading = _voteLoadingIds.contains(item.id);
    final badgeColor = _statusColor(item);

    return InkWell(
      onTap: isVoteLoading ? null : () => _toggleVote(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: item.viewerHasVoted
                    ? ShellStyles.textPrimary(context).withAlpha(14)
                    : ShellStyles.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: item.viewerHasVoted
                      ? ShellStyles.textPrimary(context)
                      : ShellStyles.border(context),
                ),
              ),
              child: Column(
                children: [
                  isVoteLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ShellStyles.textPrimary(context),
                          ),
                        )
                      : Icon(
                          item.viewerHasVoted
                              ? Icons.thumb_up_alt
                              : Icons.thumb_up_alt_outlined,
                          color: item.viewerHasVoted
                              ? ShellStyles.textPrimary(context)
                              : ShellStyles.textMuted(context),
                          size: 16,
                        ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.voteCount}',
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withAlpha(18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusLabel(item),
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _categoryLabel(item.category),
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: ShellStyles.textPrimary(context),
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildMyIdeasSection() {
    if (_myRequests.isEmpty) {
      return _buildEmptyCard(
        title: context.tr('feature_request_your_ideas_empty_title'),
        subtitle: context.tr('feature_request_your_ideas_empty_subtitle'),
      );
    }

    const order = ['pending', 'approved', 'rejected'];
    final groups = order
        .map(
          (state) => MapEntry(
            state,
            _myRequests
                .where((item) => item.moderationState == state)
                .toList(growable: false),
          ),
        )
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          Text(
            _groupTitle(groups[index].key),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _buildRequestList(groups[index].value),
          if (index != groups.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_feature_request'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: FilledButton(
              onPressed: _toggleComposer,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                _showComposer
                    ? context.tr('common_cancel')
                    : context.tr('feature_request_new_idea'),
              ),
            ),
          ),
        ),
      ],
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            RefreshIndicator(
              onRefresh: () => _loadData(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  Text(
                    context.tr('feature_request_subtitle'),
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 13,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(),
                  ],
                  if (_showComposer) ...[
                    const SizedBox(height: 16),
                    _buildComposerCard(),
                  ],
                  const SizedBox(height: 16),
                  ShellStyles.sectionLabel(
                    context,
                    context.tr('feature_request_your_ideas'),
                  ),
                  const SizedBox(height: 8),
                  _buildMyIdeasSection(),
                  const SizedBox(height: 16),
                  ShellStyles.sectionLabel(
                    context,
                    context.tr('feature_request_popular_requests'),
                  ),
                  const SizedBox(height: 8),
                  if (_publicRequests.isEmpty)
                    _buildEmptyCard(
                      title: context.tr(
                        'feature_request_popular_requests_empty_title',
                      ),
                      subtitle: context.tr(
                        'feature_request_popular_requests_empty_subtitle',
                      ),
                    )
                  else
                    _buildRequestList(_publicRequests),
                ],
              ),
            ),
          if (_voteLoadingIds.isNotEmpty)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

class _FeatureRequestItem {
  const _FeatureRequestItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.moderationState,
    required this.publicStatus,
    required this.voteCount,
    required this.viewerHasVoted,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _FeatureRequestItem.fromPublicJson(Map<String, dynamic> json) {
    return _FeatureRequestItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: '',
      category: json['category']?.toString() ?? 'other',
      moderationState: 'approved',
      publicStatus: json['public_status']?.toString() ?? 'under_review',
      voteCount: int.tryParse(json['vote_count']?.toString() ?? '') ?? 0,
      viewerHasVoted: json['viewer_has_voted'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  factory _FeatureRequestItem.fromMineJson(Map<String, dynamic> json) {
    return _FeatureRequestItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? 'other',
      moderationState: json['moderation_state']?.toString() ?? 'pending',
      publicStatus: json['public_status']?.toString(),
      voteCount: int.tryParse(json['vote_count']?.toString() ?? '') ?? 0,
      viewerHasVoted: json['viewer_has_voted'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String title;
  final String description;
  final String category;
  final String moderationState;
  final String? publicStatus;
  final int voteCount;
  final bool viewerHasVoted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayState {
    if (moderationState == 'approved') {
      return publicStatus ?? 'under_review';
    }
    return moderationState;
  }

  _FeatureRequestItem copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    String? moderationState,
    String? publicStatus,
    int? voteCount,
    bool? viewerHasVoted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return _FeatureRequestItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      moderationState: moderationState ?? this.moderationState,
      publicStatus: publicStatus ?? this.publicStatus,
      voteCount: voteCount ?? this.voteCount,
      viewerHasVoted: viewerHasVoted ?? this.viewerHasVoted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
