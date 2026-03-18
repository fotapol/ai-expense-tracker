import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import 'subcategories_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _categories = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.listCategories(includeDisabled: true);
      final categories = data.whereType<Map<String, dynamic>>().toList();
      await _pruneSavedFilterSelections(categories);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoading = false;
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
        .where((category) =>
            category['parent_id'] == null && category['is_disabled'] != true)
        .map((category) => category['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final activeSubcategoryIds = categories
        .where((category) =>
            category['parent_id'] != null && category['is_disabled'] != true)
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

  List<Map<String, dynamic>> get _activeTopLevelCategories => _categories
      .where((category) =>
          category['parent_id'] == null && category['is_disabled'] != true)
      .toList()
    ..sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));

  List<Map<String, dynamic>> get _disabledTopLevelCategories => _categories
      .where((category) =>
          category['parent_id'] == null &&
          category['is_disabled'] == true &&
          category['is_default'] == true)
      .toList()
    ..sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));

  String _localizedName(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  Future<void> _showAddChooser() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(context.tr('categories_add_category')),
              onTap: () => Navigator.pop(context, 'category'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(context.tr('categories_add_subcategory')),
              onTap: () => Navigator.pop(context, 'subcategory'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'category') {
      await _showAddCategoryDialog();
      return;
    }
    await _showAddSubcategoryDialog();
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('categories_new_category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: context.tr('categories_category_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.tr('common_create')),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    try {
      await ApiClient.createCategory(name);
      await _fetchCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('categories_category_created', params: {'name': name}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _showAddSubcategoryDialog() async {
    final controller = TextEditingController();
    final parentOptions = _activeTopLevelCategories;
    if (parentOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('categories_no_parent_categories')),
        ),
      );
      return;
    }

    String? selectedParentId = parentOptions.first['id']?.toString();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('categories_new_subcategory')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedParentId,
                decoration: InputDecoration(
                  labelText: context.tr('categories_parent_category'),
                  border: const OutlineInputBorder(),
                ),
                items: parentOptions
                    .map(
                      (parent) => DropdownMenuItem<String>(
                        value: parent['id']?.toString(),
                        child: Text(_localizedName(parent)),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedParentId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: context.tr('categories_subcategory_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('common_cancel')),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty || selectedParentId == null) {
                  Navigator.pop(context);
                  return;
                }
                Navigator.pop(context, {
                  'name': name,
                  'parent_id': selectedParentId!,
                });
              },
              child: Text(context.tr('common_create')),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    try {
      await ApiClient.createCategory(
        result['name']!,
        parentId: result['parent_id'],
      );
      await _fetchCategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'categories_subcategory_created',
              params: {'name': result['name']!},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
      builder: (context) => AlertDialog(
        title: Text(context.tr(titleKey)),
        content: Text(context.tr(messageKey, params: {'name': name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              context.tr(isBuiltIn ? 'categories_disable_action' : 'common_delete'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ApiClient.deleteCategory(category['id']!.toString());
      await _fetchCategories();
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
      await _fetchCategories();
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

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'common_error_with_message',
            params: {'message': error.toString()},
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildCategoryTile(
    Map<String, dynamic> category, {
    required bool disabled,
  }) {
    final name = _localizedName(category);
    final code = category['code']?.toString() ?? '';
    final color = CategoryStyle.colorForCode(code);
    final icon = CategoryStyle.iconForCode(code);
    final isBuiltIn = category['is_default'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        enabled: !disabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: disabled
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SubcategoriesScreen(
                      parentId: category['id']!.toString(),
                      parentName: name,
                    ),
                  ),
                ).then((_) => _fetchCategories());
              },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withAlpha(disabled ? 12 : 28),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: disabled ? Colors.grey : color),
        ),
        title: Text(name),
        subtitle: Text(
          context.tr(
            disabled
                ? 'categories_disabled_state'
                : isBuiltIn
                ? 'categories_built_in'
                : 'categories_custom',
          ),
        ),
        trailing: disabled
            ? TextButton(
                onPressed: () => _restoreCategory(category),
                child: Text(context.tr('categories_restore_action')),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _deleteOrDisableCategory(category),
                    icon: Icon(
                      isBuiltIn ? Icons.block_outlined : Icons.delete_outline,
                      color: isBuiltIn ? Colors.orangeAccent : Colors.redAccent,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('categories_title')),
        actions: [
          IconButton(
            onPressed: _showAddChooser,
            icon: const Icon(Icons.add),
            tooltip: context.tr('categories_add_action'),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    final bottomPadding = MediaQuery.of(context).padding.bottom + 32;
    return RefreshIndicator(
      onRefresh: _fetchCategories,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: [
          Text(
            context.tr('categories_active_section'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_activeTopLevelCategories.isEmpty)
            Text(
              context.tr('categories_not_found'),
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ..._activeTopLevelCategories.map(
            (category) => _buildCategoryTile(category, disabled: false),
          ),
          if (_disabledTopLevelCategories.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              context.tr('categories_disabled_section'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ..._disabledTopLevelCategories.map(
              (category) => _buildCategoryTile(category, disabled: true),
            ),
          ],
        ],
      ),
    );
  }
}
