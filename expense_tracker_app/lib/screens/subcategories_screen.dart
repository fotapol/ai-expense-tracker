import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/category_style.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';

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
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _subcategories = [];

  @override
  void initState() {
    super.initState();
    _fetchSubcategories();
  }

  Future<void> _fetchSubcategories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final categories = await ApiClient.listCategories(includeDisabled: true);
      final subcategories = categories
          .whereType<Map<String, dynamic>>()
          .where((category) => category['parent_id']?.toString() == widget.parentId)
          .toList()
        ..sort((a, b) => _localizedName(a).compareTo(_localizedName(b)));
      await _pruneSavedFilterSelections(subcategories);
      if (!mounted) return;
      setState(() {
        _subcategories = subcategories;
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

  List<Map<String, dynamic>> get _activeSubcategories => _subcategories
      .where((category) => category['is_disabled'] != true)
      .toList();

  List<Map<String, dynamic>> get _disabledSubcategories => _subcategories
      .where((category) =>
          category['is_disabled'] == true && category['is_default'] == true)
      .toList();

  Future<void> _showAddSubcategoryDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.tr(
            'subcategories_new_for_parent',
            params: {'name': widget.parentName},
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: context.tr('subcategories_name_hint'),
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
      await ApiClient.createCategory(name, parentId: widget.parentId);
      await _fetchSubcategories();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('subcategories_created', params: {'name': name}),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    }
  }

  Future<void> _deleteOrDisable(Map<String, dynamic> category) async {
    final name = _localizedName(category);
    final isBuiltIn = category['is_default'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      await _fetchSubcategories();
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
      await _fetchSubcategories();
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
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> category, {required bool disabled}) {
    final name = _localizedName(category);
    final code = category['code']?.toString() ?? '';
    final color = CategoryStyle.colorForCode(code);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withAlpha(disabled ? 12 : 28),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.account_tree_outlined,
            color: disabled ? Colors.grey : color,
          ),
        ),
        title: Text(name),
        subtitle: Text(
          context.tr(
            disabled ? 'categories_disabled_state' : 'subcategories_active_state',
          ),
        ),
        trailing: disabled
            ? TextButton(
                onPressed: () => _restore(category),
                child: Text(context.tr('categories_restore_action')),
              )
            : IconButton(
                icon: Icon(
                  category['is_default'] == true
                      ? Icons.block_outlined
                      : Icons.delete_outline,
                  color: category['is_default'] == true
                      ? Colors.orangeAccent
                      : Colors.redAccent,
                ),
                onPressed: () => _deleteOrDisable(category),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            'subcategories_title_for_parent',
            params: {'name': widget.parentName},
          ),
        ),
        actions: [
          IconButton(
            onPressed: _showAddSubcategoryDialog,
            icon: const Icon(Icons.add),
            tooltip: context.tr('categories_add_subcategory'),
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
      onRefresh: _fetchSubcategories,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        children: [
          if (_activeSubcategories.isEmpty && _disabledSubcategories.isEmpty)
            Text(
              context.tr(
                'subcategories_not_found_for_parent',
                params: {'name': widget.parentName},
              ),
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ..._activeSubcategories.map(
            (category) => _buildRow(category, disabled: false),
          ),
          if (_disabledSubcategories.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              context.tr('categories_disabled_section'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ..._disabledSubcategories.map(
              (category) => _buildRow(category, disabled: true),
            ),
          ],
        ],
      ),
    );
  }
}
