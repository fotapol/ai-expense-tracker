import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'receipt_upload_screen.dart';

class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  static const List<String> _colorOptions = [
    '#4D7BF3',
    '#A347F5',
    '#EC2D91',
    '#FF3838',
    '#FF6B00',
    '#F2B900',
    '#17C653',
    '#19BFB4',
    '#24B7D9',
    '#6F5CF4',
  ];

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final GlobalKey _createFormKey = GlobalKey();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showCreateForm = false;
  List<dynamic> _labels = [];
  String? _error;
  String _selectedColorHex = _colorOptions.first;

  @override
  void initState() {
    super.initState();
    _fetchLabels();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _openScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptUploadScreen()),
    );
  }

  Future<void> _fetchLabels({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiClient.listLabels();
      if (!mounted) return;
      setState(() {
        _labels = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openCreateForm() {
    if (!_showCreateForm) {
      setState(() {
        _showCreateForm = true;
        _selectedColorHex = _colorOptions.first;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
      final currentContext = _createFormKey.currentContext;
      if (currentContext != null) {
        Scrollable.ensureVisible(
          currentContext,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelCreateForm() {
    setState(() {
      _showCreateForm = false;
      _isSubmitting = false;
      _nameController.clear();
      _selectedColorHex = _colorOptions.first;
    });
  }

  Future<void> _createLabel() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a label name.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final created = await ApiClient.createLabel(
        name,
        color: _selectedColorHex,
      );
      if (!mounted) return;

      setState(() {
        _labels = [..._labels, created]
          ..sort((a, b) {
            final left = a['name']?.toString().toLowerCase() ?? '';
            final right = b['name']?.toString().toLowerCase() ?? '';
            return left.compareTo(right);
          });
        _showCreateForm = false;
        _isSubmitting = false;
        _nameController.clear();
        _selectedColorHex = _colorOptions.first;
        _error = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('labels_created', params: {'name': name})),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: ShellColors.softRed,
        ),
      );
    }
  }

  Future<void> _deleteLabel(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('labels_delete_title')),
        content: Text(
          context.tr('labels_delete_confirm', params: {'name': name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: ShellColors.softRed),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.deleteLabel(id);
      if (!mounted) return;
      setState(() {
        _labels.removeWhere((label) => label['id']?.toString() == id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('labels_deleted', params: {'name': name})),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: ShellColors.softRed,
        ),
      );
    }
  }

  Color _colorFromHex(String? rawHex, int fallbackIndex) {
    final normalized = (rawHex ?? '').trim();
    final source = normalized.isEmpty
        ? _colorOptions[fallbackIndex % _colorOptions.length]
        : normalized;
    final hex = source.replaceFirst('#', '');
    final expanded = hex.length == 6 ? 'FF$hex' : hex;
    final value = int.tryParse(expanded, radix: 16);
    if (value == null) {
      return _colorFromHex(null, fallbackIndex);
    }
    return Color(value);
  }

  String _countLabel() {
    final count = _labels.length;
    return '$count custom label${count == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        backgroundColor: ShellStyles.background(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: ShellStyles.textPrimary(context)),
        titleSpacing: 0,
        toolbarHeight: 74,
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('labels_title'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _countLabel(),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _openCreateForm,
              icon: const Icon(AppIcons.add, size: 15),
              label: Text(context.tr('common_new')),
              style: FilledButton.styleFrom(
                backgroundColor: ShellStyles.textPrimary(context),
                foregroundColor: ShellStyles.surface(context),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _fetchLabels(showLoading: false),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  18,
                  16,
                  MediaQuery.of(context).padding.bottom + 120,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      _buildErrorCard(),
                      const SizedBox(height: 18),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _showCreateForm
                          ? Column(
                              key: const ValueKey('create-form'),
                              children: [
                                _buildCreateCard(),
                                const SizedBox(height: 18),
                              ],
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('create-form-hidden'),
                            ),
                    ),
                    ShellStyles.sectionLabel(context, 'Your Labels'),
                    const SizedBox(height: 12),
                    _buildLabelsList(),
                    const SizedBox(height: 22),
                    _buildInfoCard(),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openScan,
        backgroundColor: ShellStyles.textPrimary(context),
        foregroundColor: ShellStyles.surface(context),
        shape: const CircleBorder(),
        child: const Icon(AppIcons.scanFab),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
          Row(
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not load labels',
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
            onPressed: () => _fetchLabels(),
            style: FilledButton.styleFrom(
              backgroundColor: ShellStyles.textPrimary(context),
              foregroundColor: ShellStyles.surface(context),
            ),
            child: Text(context.tr('common_retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateCard() {
    return Container(
      key: _createFormKey,
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Custom Label',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Label Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(
              context,
              hintText: 'e.g., Business Expense',
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Color'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _colorOptions.map((hex) {
              final selected = hex == _selectedColorHex;
              final color = _colorFromHex(hex, 0);
              return GestureDetector(
                onTap: () => setState(() => _selectedColorHex = hex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? Colors.white : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? ShellStyles.border(context)
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withAlpha(12),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : const [],
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _createLabel,
                  style: FilledButton.styleFrom(
                    backgroundColor: ShellStyles.textPrimary(context),
                    foregroundColor: ShellStyles.surface(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
                      : const Text('Create Label'),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _isSubmitting ? null : _cancelCreateForm,
                style: TextButton.styleFrom(
                  backgroundColor: ShellStyles.surfaceAlt(context),
                  foregroundColor: ShellStyles.textPrimary(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(context.tr('common_cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabelsList() {
    if (_labels.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: ShellStyles.cardDecoration(context, radius: 20),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: ShellStyles.iconBadgeDecoration(context, radius: 14),
              child: Icon(
                AppIcons.labels,
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
                    context.tr('labels_empty_title'),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('labels_empty_subtitle'),
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 20),
      child: Column(
        children: List.generate(_labels.length, (index) {
          final label = _labels[index] as Map<String, dynamic>;
          final id = label['id']?.toString() ?? '';
          final name = label['name']?.toString() ?? '';
          final color = _colorFromHex(label['color']?.toString(), index);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.tag,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _deleteLabel(id, name),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: ShellColors.softRed,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (index != _labels.length - 1)
                Divider(height: 1, color: ShellStyles.border(context)),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 18,
        color: ShellStyles.surfaceAlt(context),
        withShadow: false,
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 13,
            height: 1.55,
          ),
          children: [
            TextSpan(
              text: 'About Labels: ',
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(
              text:
                  'Use labels to add custom tags to your transactions. Labels are different from categories - you can add multiple labels to a single expense for more flexible organization.',
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
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hintText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: ShellStyles.textMuted(context)),
      filled: true,
      fillColor: ShellStyles.surface(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: ShellStyles.border(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: ShellStyles.border(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: ShellStyles.textPrimary(context)),
      ),
    );
  }
}
