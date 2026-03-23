import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class FeatureRequestScreen extends StatefulWidget {
  const FeatureRequestScreen({super.key});

  @override
  State<FeatureRequestScreen> createState() => _FeatureRequestScreenState();
}

class _FeatureRequestScreenState extends State<FeatureRequestScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<_RequestItem> _requests = [
    _RequestItem(
      title: 'Dark mode support',
      votes: 127,
      status: _RequestStatus.inProgress,
    ),
    _RequestItem(
      title: 'Export to Google Sheets',
      votes: 89,
      status: _RequestStatus.planned,
    ),
    _RequestItem(
      title: 'Recurring expenses tracker',
      votes: 76,
      status: _RequestStatus.underReview,
    ),
    _RequestItem(
      title: 'Multi-currency support',
      votes: 64,
      status: _RequestStatus.planned,
    ),
    _RequestItem(
      title: 'Widget for iOS home screen',
      votes: 52,
      status: _RequestStatus.underReview,
    ),
  ];

  bool _showComposer = false;
  String _selectedCategory = 'Analytics & Reports';

  static const List<String> _categories = [
    'Analytics & Reports',
    'Receipts & Scanning',
    'Budgets & Planning',
    'Household & Sharing',
    'Design & Accessibility',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _toggleComposer() {
    setState(() => _showComposer = !_showComposer);
  }

  void _submitRequest() {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete the title and description.'),
        ),
      );
      return;
    }
    setState(() {
      _requests.insert(
        0,
        _RequestItem(
          title: title,
          votes: 1,
          status: _RequestStatus.underReview,
          category: _selectedCategory,
        ),
      );
      _titleController.clear();
      _descriptionController.clear();
      _selectedCategory = _categories.first;
      _showComposer = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Feature request submitted.')));
  }

  void _upvote(int index) {
    setState(
      () => _requests[index] = _requests[index].copyWith(
        votes: _requests[index].votes + 1,
      ),
    );
  }

  Color _statusColor(_RequestStatus status) {
    switch (status) {
      case _RequestStatus.inProgress:
        return const Color(0xFF3D6CFF);
      case _RequestStatus.planned:
        return const Color(0xFFA04DF0);
      case _RequestStatus.underReview:
        return const Color(0xFFF5A313);
    }
  }

  String _statusLabel(_RequestStatus status) {
    switch (status) {
      case _RequestStatus.inProgress:
        return 'In Progress';
      case _RequestStatus.planned:
        return 'Planned';
      case _RequestStatus.underReview:
        return 'Under Review';
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
                'Submit Your Idea',
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Title',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Brief description of your idea...',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Category',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            items: _categories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCategory = value);
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Description',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionController,
            minLines: 5,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Describe your feature request in detail...',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitRequest,
              style: FilledButton.styleFrom(
                backgroundColor: ShellStyles.textPrimary(context),
                foregroundColor: ShellStyles.surface(context),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Submit Request'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsCard() {
    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        children: [
          for (var index = 0; index < _requests.length; index++) ...[
            InkWell(
              onTap: () => _upvote(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: ShellStyles.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ShellStyles.border(context)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.thumb_up_alt_outlined,
                            color: ShellStyles.textMuted(context),
                            size: 16,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_requests[index].votes}',
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
                            _requests[index].title,
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                                  color: _statusColor(
                                    _requests[index].status,
                                  ).withAlpha(18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(_requests[index].status),
                                  style: TextStyle(
                                    color: _statusColor(
                                      _requests[index].status,
                                    ),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_requests[index].category != null)
                                Text(
                                  _requests[index].category!,
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
            ),
            if (index != _requests.length - 1)
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
                backgroundColor: ShellStyles.textPrimary(context),
                foregroundColor: ShellStyles.surface(context),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(_showComposer ? 'Cancel' : 'New Idea'),
            ),
          ),
        ),
      ],
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share your ideas with us',
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 13,
                ),
              ),
              if (_showComposer) ...[
                const SizedBox(height: 16),
                _buildComposerCard(),
              ],
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'Popular Requests'),
              const SizedBox(height: 8),
              _buildRequestsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RequestStatus { inProgress, planned, underReview }

class _RequestItem {
  const _RequestItem({
    required this.title,
    required this.votes,
    required this.status,
    this.category,
  });

  final String title;
  final int votes;
  final _RequestStatus status;
  final String? category;

  _RequestItem copyWith({
    String? title,
    int? votes,
    _RequestStatus? status,
    String? category,
  }) {
    return _RequestItem(
      title: title ?? this.title,
      votes: votes ?? this.votes,
      status: status ?? this.status,
      category: category ?? this.category,
    );
  }
}
