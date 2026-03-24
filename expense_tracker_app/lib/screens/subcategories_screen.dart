import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/category_icon_registry.dart';
import '../core/category_style.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'receipt_upload_screen.dart';

class SubcategoriesScreen extends StatefulWidget {
  const SubcategoriesScreen({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  final String parentId;
  final String parentName;

  @override
  State<SubcategoriesScreen> createState() => _SubcategoriesScreenState();
}

class _SubcategoriesScreenState extends State<SubcategoriesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final GlobalKey _createFormKey = GlobalKey();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showCreateForm = false;
  String? _error;
  List<Map<String, dynamic>> _subcategories = [];
  String _selectedIconKey = CategoryIconRegistry.options.first.key;

  @override
  void initState() {
    super.initState();
    _fetchSubcategories();
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

  Future<void> _fetchSubcategories({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final categories = await ApiClient.listCategories(includeDisabled: true);
      final subcategories =
          categories
              .whereType<Map<String, dynamic>>()
              .where(
                (category) =>
                    category['parent_id']?.toString() == widget.parentId,
              )
              .toList()
            ..sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));
      await _pruneSavedFilterSelections(subcategories);
      if (!mounted) return;
      setState(() {
        _subcategories = subcategories;
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

  Future<void> _pruneSavedFilterSelections(
    List<Map<String, dynamic>> subcategories,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final activeIds = subcategories
        .where((category) => category['is_disabled'] != true)
        .map((category) => category['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final saved =
        prefs.getStringList('analytics_subcategory_ids') ?? const <String>[];
    await prefs.setStringList(
      'analytics_subcategory_ids',
      saved.where(activeIds.contains).toList(),
    );
  }

  String _localizedName(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  List<Map<String, dynamic>> _sorted(
    Iterable<Map<String, dynamic>> categories,
  ) {
    final result = categories.toList();
    result.sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));
    return result;
  }

  List<Map<String, dynamic>> get _builtInSubcategories => _sorted(
    _subcategories.where((category) => category['is_default'] == true),
  );

  List<Map<String, dynamic>> get _customSubcategories => _sorted(
    _subcategories.where(
      (category) =>
          category['is_default'] != true && category['is_disabled'] != true,
    ),
  );

  String _countLabel() {
    final count = _subcategories
        .where((category) => category['is_disabled'] != true)
        .length;
    return '$count active subcategories';
  }

  void _openCreateForm() {
    if (!_showCreateForm) {
      setState(() {
        _showCreateForm = true;
        _selectedIconKey = CategoryIconRegistry.options.first.key;
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
      _selectedIconKey = CategoryIconRegistry.options.first.key;
    });
  }

  Future<void> _createSubcategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a subcategory name.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final created = await ApiClient.createCategory(
        name,
        parentId: widget.parentId,
        icon: _selectedIconKey,
      );
      if (!mounted) return;
      setState(() {
        _subcategories = [..._subcategories, created]
          ..sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));
        _showCreateForm = false;
        _isSubmitting = false;
        _nameController.clear();
        _selectedIconKey = CategoryIconRegistry.options.first.key;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('subcategories_created', params: {'name': name}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(e);
    }
  }

  Future<void> _deleteOrDisable(Map<String, dynamic> category) async {
    final name = _localizedName(category);
    final isBuiltIn = category['is_default'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(
            isBuiltIn
                ? 'subcategories_disable_title'
                : 'subcategories_delete_title',
          ),
        ),
        content: Text(
          context.tr(
            isBuiltIn
                ? 'subcategories_disable_confirm'
                : 'subcategories_delete_confirm',
            params: {'name': name},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: ShellColors.softRed),
            child: Text(
              context.tr(
                isBuiltIn ? 'categories_disable_action' : 'common_delete',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.deleteCategory(category['id']!.toString());
      await _fetchSubcategories(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              isBuiltIn ? 'subcategories_disabled' : 'subcategories_deleted',
              params: {'name': name},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _restore(Map<String, dynamic> category) async {
    try {
      await ApiClient.restoreCategory(category['id']!.toString());
      await _fetchSubcategories(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'subcategories_restored',
              params: {'name': _localizedName(category)},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  void _showError(Object error) {
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

  Color _iconColor(Map<String, dynamic> category) {
    final colorValue = category['color']?.toString();
    if (colorValue != null && colorValue.isNotEmpty) {
      final hex = colorValue.replaceFirst('#', '');
      final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      if (value != null) return Color(value);
    }
    final code = category['code']?.toString();
    if (code != null && code.isNotEmpty) {
      return CategoryStyle.colorForCode(code);
    }
    return CategoryStyle.colorForSeed(category['name']?.toString());
  }

  Widget _buildActionPill({
    required String label,
    required VoidCallback onTap,
    required bool emphasized,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: emphasized
              ? const Color(0xFFA6A6A6)
              : ShellStyles.surfaceAlt(context),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: emphasized ? Colors.white : ShellStyles.textPrimary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSubcategoryRow(
    Map<String, dynamic> category, {
    required bool disabled,
  }) {
    final name = _localizedName(category);
    final accent = _iconColor(category);
    final icon = CategoryIconRegistry.resolve(
      category['icon']?.toString(),
      code: category['code']?.toString(),
    );
    final isBuiltIn = category['is_default'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withAlpha(disabled ? 18 : 28),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: disabled ? ShellStyles.textMuted(context) : accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: disabled
                    ? ShellStyles.textMuted(context)
                    : ShellStyles.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildActionPill(
            label: disabled
                ? 'Enable'
                : isBuiltIn
                ? 'Disable'
                : 'Delete',
            onTap: disabled
                ? () => _restore(category)
                : () => _deleteOrDisable(category),
            emphasized: disabled,
          ),
        ],
      ),
    );
  }

  Widget _buildCardList(
    List<Map<String, dynamic>> categories, {
    required String emptyText,
  }) {
    if (categories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: ShellStyles.cardDecoration(context, radius: 20),
        child: Text(
          emptyText,
          style: TextStyle(color: ShellStyles.textMuted(context), fontSize: 13),
        ),
      );
    }

    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 20),
      child: Column(
        children: List.generate(categories.length, (index) {
          final category = categories[index];
          return Column(
            children: [
              _buildSubcategoryRow(
                category,
                disabled: category['is_disabled'] == true,
              ),
              if (index != categories.length - 1)
                Divider(height: 1, color: ShellStyles.border(context)),
            ],
          );
        }),
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
            'Create Subcategory',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Subcategory Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(context, hintText: 'e.g., Pet Food'),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Icon'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: CategoryIconRegistry.options.map((option) {
              final selected = option.key == _selectedIconKey;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selectedIconKey = option.key),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? ShellStyles.textPrimary(context)
                        : ShellStyles.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ShellStyles.border(context)),
                  ),
                  child: Icon(
                    option.icon,
                    size: 20,
                    color: selected
                        ? ShellStyles.surface(context)
                        : ShellStyles.textPrimary(context),
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
                  onPressed: _isSubmitting ? null : _createSubcategory,
                  style: FilledButton.styleFrom(
                    backgroundColor: ShellStyles.textPrimary(context),
                    foregroundColor: ShellStyles.surface(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                      : const Text('Create Subcategory'),
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
                ),
                child: Text(context.tr('common_cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not load subcategories',
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
            onPressed: () => _fetchSubcategories(),
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 18,
        color: ShellStyles.surfaceAlt(context),
        withShadow: false,
      ),
      child: Text(
        'Tip: Disabled subcategories won\'t appear when categorizing items. You can re-enable them anytime.',
        style: TextStyle(
          color: ShellStyles.textMuted(context),
          fontSize: 13,
          height: 1.55,
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
              widget.parentName,
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
              onRefresh: () => _fetchSubcategories(showLoading: false),
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
                    ShellStyles.sectionLabel(context, 'Built-In Subcategories'),
                    const SizedBox(height: 12),
                    _buildCardList(
                      _builtInSubcategories,
                      emptyText: context.tr(
                        'subcategories_not_found_for_parent',
                        params: {'name': widget.parentName},
                      ),
                    ),
                    if (_customSubcategories.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      ShellStyles.sectionLabel(context, 'Custom Subcategories'),
                      const SizedBox(height: 12),
                      _buildCardList(
                        _customSubcategories,
                        emptyText: 'No custom subcategories yet.',
                      ),
                    ],
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
}
