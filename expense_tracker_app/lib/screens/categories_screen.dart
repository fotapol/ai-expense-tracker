import 'package:flutter/material.dart';
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
  List<dynamic> _categories = [];
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
      final data = await ApiClient.listCategories();
      setState(() {
        _categories = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    final parentOptions = _categories
        .where((c) => c['parent_id'] == null)
        .toList();
    String? selectedParentId = parentOptions.isNotEmpty
        ? parentOptions.first['id'] as String
        : null;

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
                        value: parent['id'] as String,
                        child: Text(
                          localizeCategoryByCode(
                            context,
                            code: parent['code']?.toString(),
                            fallbackName: parent['name'] as String?,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedParentId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: context.tr('categories_subcategory_hint'),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
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

    if (result != null &&
        result['name'] != null &&
        result['parent_id'] != null) {
      try {
        await ApiClient.createCategory(
          result['name']!,
          parentId: result['parent_id'],
        );
        _fetchCategories();
        if (mounted) {
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
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'common_error_with_message',
                  params: {'message': e.toString()},
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('categories_delete_title')),
        content: Text(
          context.tr('categories_delete_confirm', params: {'name': name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient.deleteCategory(id);
        _fetchCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('categories_deleted', params: {'name': name}),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'common_error_with_message',
                  params: {'message': e.toString()},
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildCategoryItem(Map<String, dynamic> cat) {
    final code = cat['code'] as String? ?? '';
    final name = localizeCategoryByCode(
      context,
      code: code,
      fallbackName: cat['name'] as String?,
    );
    final isDefault = cat['is_default'] as bool? ?? false;
    final id = cat['id'] as String;

    final color = CategoryStyle.colorForCode(code);
    final icon = CategoryStyle.iconForCode(code);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SubcategoriesScreen(parentId: id, parentName: name),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDefault
                        ? context.tr('categories_built_in')
                        : context.tr('categories_custom'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            if (!isDefault)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () {
                  _deleteCategory(id, name);
                },
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
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCategoryDialog,
        icon: const Icon(Icons.add),
        label: Text(context.tr('categories_add_subcategory')),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_categories.isEmpty) {
      return Center(
        child: Text(
          context.tr('categories_not_found'),
          style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
        ),
      );
    }

    // Only show parent categories (those without a parent_id)
    final topLevelCats = _categories
        .where((c) => c['parent_id'] == null)
        .toList();

    return RefreshIndicator(
      onRefresh: _fetchCategories,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: topLevelCats.length,
        itemBuilder: (context, index) {
          final cat = topLevelCats[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildCategoryItem(cat),
          );
        },
      ),
    );
  }
}
