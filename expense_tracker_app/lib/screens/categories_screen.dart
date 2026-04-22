import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/app_color_semantics.dart';
import '../core/category_icon_registry.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'subcategories_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final GlobalKey _createFormKey = GlobalKey();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showCreateForm = false;
  List<Map<String, dynamic>> _categories = [];
  String? _error;
  String _selectedIconKey = CategoryIconRegistry.options.first.key;
  String _selectedColorHex = AppSemanticColors.defaultCategoryColorHex;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiClient.listCategories(includeDisabled: true);
      final categories = data.whereType<Map<String, dynamic>>().toList();
      await _pruneSavedFilterSelections(categories);
      if (!mounted) return;
      setState(() {
        _categories = categories;
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
    List<Map<String, dynamic>> categories,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final activeTopLevelIds = categories
        .where(
          (category) =>
              category['parent_id'] == null && category['is_disabled'] != true,
        )
        .map((category) => category['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final activeSubcategoryIds = categories
        .where(
          (category) =>
              category['parent_id'] != null && category['is_disabled'] != true,
        )
        .map((category) => category['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final savedCategoryIds =
        prefs.getStringList('analytics_category_ids') ?? const <String>[];
    final savedSubcategoryIds =
        prefs.getStringList('analytics_subcategory_ids') ?? const <String>[];
    await prefs.setStringList(
      'analytics_category_ids',
      savedCategoryIds.where(activeTopLevelIds.contains).toList(),
    );
    await prefs.setStringList(
      'analytics_subcategory_ids',
      savedSubcategoryIds.where(activeSubcategoryIds.contains).toList(),
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

  List<Map<String, dynamic>> get _topLevelCategories =>
      _categories.where((category) => category['parent_id'] == null).toList();

  List<Map<String, dynamic>> get _builtInCategories => _sorted(
    _topLevelCategories.where((category) => category['is_default'] == true),
  );

  List<Map<String, dynamic>> get _customCategories => _sorted(
    _topLevelCategories.where(
      (category) =>
          category['is_default'] != true && category['is_disabled'] != true,
    ),
  );

  String _countLabel() {
    final count = _topLevelCategories
        .where((category) => category['is_disabled'] != true)
        .length;
    return '$count active categories';
  }

  void _openCreateForm() {
    if (!_showCreateForm) {
      setState(() {
        _showCreateForm = true;
        _selectedIconKey = CategoryIconRegistry.options.first.key;
        _selectedColorHex = AppSemanticColors.defaultCategoryColorHex;
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
      _selectedColorHex = AppSemanticColors.defaultCategoryColorHex;
    });
  }

  Future<void> _createCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('please_enter_a_category_name'))),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final created = await ApiClient.createCategory(
        name,
        icon: _selectedIconKey,
        color: _selectedColorHex,
      );
      if (!mounted) return;
      setState(() {
        _categories = [..._categories, created];
        _showCreateForm = false;
        _isSubmitting = false;
        _nameController.clear();
        _selectedIconKey = CategoryIconRegistry.options.first.key;
        _selectedColorHex = AppSemanticColors.defaultCategoryColorHex;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('categories_category_created', params: {'name': name}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showError(e);
    }
  }

  Future<void> _deleteOrDisableCategory(Map<String, dynamic> category) async {
    final name = _localizedName(category);
    final isBuiltIn = category['is_default'] == true;
    final titleKey = isBuiltIn
        ? 'categories_disable_title'
        : 'categories_delete_title';
    final messageKey = isBuiltIn
        ? 'categories_disable_confirm'
        : 'categories_delete_confirm';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(titleKey)),
        content: Text(context.tr(messageKey, params: {'name': name})),
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
      await _fetchCategories(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              isBuiltIn ? 'categories_disabled' : 'categories_deleted',
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

  Future<void> _restoreCategory(Map<String, dynamic> category) async {
    final name = _localizedName(category);
    try {
      await ApiClient.restoreCategory(category['id']!.toString());
      await _fetchCategories(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('categories_restored', params: {'name': name}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _openSubcategories(Map<String, dynamic> category) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubcategoriesScreen(
          parentId: category['id']!.toString(),
          parentName: _localizedName(category),
        ),
      ),
    );
    if (!mounted) return;
    await _fetchCategories(showLoading: false);
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

  List<AppColorPickerOption> _categoryColorOptions() {
    return AppSemanticColors.categoryColorOptions(
      accentId: ShellStyles.accentId(context),
      brightness: Theme.of(context).brightness,
      labelColorMode: ShellStyles.labelColorMode(context),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _categoryColorOptions().map((option) {
        final selected = option.storedHex == _selectedColorHex;
        return GestureDetector(
          onTap: () => setState(() => _selectedColorHex = option.storedHex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? ShellStyles.sectionBackground(context)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? ShellStyles.border(context)
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withAlpha(
                          ShellStyles.isDark(context) ? 20 : 12,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: option.previewColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionPill({
    required String label,
    required VoidCallback onTap,
    required bool emphasized,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ShellStyles.scaled(context, 10, min: 9, max: 12),
          vertical: ShellStyles.scaled(context, 7, min: 6, max: 8),
        ),
        decoration: BoxDecoration(
          color: emphasized
              ? ShellStyles.textPrimary(context)
              : ShellStyles.surfaceAlt(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ShellStyles.border(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: emphasized
                ? ShellStyles.surface(context)
                : ShellStyles.textMuted(context),
            fontSize: ShellStyles.scaled(context, 11.5, min: 11, max: 12.5),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryRow(
    Map<String, dynamic> category, {
    required bool disabled,
  }) {
    final name = _localizedName(category);
    final tone = ShellStyles.categoryTone(
      context,
      code: category['code']?.toString(),
      name: category['name']?.toString(),
      rawHex: category['color']?.toString(),
    );
    final icon = CategoryIconRegistry.resolve(
      category['icon']?.toString(),
      code: category['code']?.toString(),
    );
    final isBuiltIn = category['is_default'] == true;

    return InkWell(
      onTap: () => _openSubcategories(category),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ShellStyles.scaled(context, 14, min: 12, max: 16),
          vertical: ShellStyles.scaled(context, 12, min: 10, max: 14),
        ),
        child: Row(
          children: [
            Container(
              width: ShellStyles.scaled(context, 36, min: 34, max: 40),
              height: ShellStyles.scaled(context, 36, min: 34, max: 40),
              decoration: ShellStyles.semanticBadgeDecoration(
                context,
                tone: tone,
                radius: ShellStyles.scaled(context, 12, min: 10, max: 14),
              ),
              child: Icon(
                icon,
                size: ShellStyles.scaled(context, 18, min: 16, max: 20),
                color: disabled
                    ? ShellStyles.textMuted(context)
                    : tone.foreground,
              ),
            ),
            SizedBox(width: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: disabled
                      ? ShellStyles.textMuted(context)
                      : ShellStyles.textPrimary(context),
                  fontSize: ShellStyles.scaled(context, 14, min: 13, max: 15),
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
                  ? () => _restoreCategory(category)
                  : () => _deleteOrDisableCategory(category),
              emphasized: disabled,
            ),
            const SizedBox(width: 8),
            Icon(
              AppIcons.chevronRight,
              size: 16,
              color: ShellStyles.textMuted(context),
            ),
          ],
        ),
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
              _buildCategoryRow(
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

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not load categories',
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
            onPressed: () => _fetchCategories(),
            style: FilledButton.styleFrom(
              backgroundColor: ShellStyles.accent(context),
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
            'Create Custom Category',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Category Name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(context, hintText: 'e.g., Pet Care'),
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
                        ? ShellStyles.accentTone(context).container
                        : ShellStyles.surfaceAlt(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? ShellStyles.accentTone(context).border
                          : ShellStyles.border(context),
                    ),
                  ),
                  child: Icon(
                    option.icon,
                    size: 20,
                    color: selected
                        ? ShellStyles.accentTone(context).foreground
                        : ShellStyles.textPrimary(context),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Color'),
          const SizedBox(height: 10),
          _buildColorPicker(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _createCategory,
                  style: FilledButton.styleFrom(
                    backgroundColor: ShellStyles.accent(context),
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(context.tr('create_category')),
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
        'Tip: Disabled categories won\'t appear when categorizing expenses. You can re-enable them anytime.',
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
              context.tr('categories_title'),
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
                backgroundColor: ShellStyles.accent(context),
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
              onRefresh: () => _fetchCategories(showLoading: false),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  18,
                  16,
                  MediaQuery.of(context).padding.bottom + 32,
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
                    ShellStyles.sectionLabel(context, 'Default Categories'),
                    const SizedBox(height: 12),
                    _buildCardList(
                      _builtInCategories,
                      emptyText: context.tr('categories_not_found'),
                    ),
                    if (_customCategories.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      ShellStyles.sectionLabel(context, 'Custom Categories'),
                      const SizedBox(height: 12),
                      _buildCardList(
                        _customCategories,
                        emptyText: 'No custom categories yet.',
                      ),
                    ],
                    const SizedBox(height: 22),
                    _buildInfoCard(),
                  ],
                ),
              ),
            ),
    );
  }
}
