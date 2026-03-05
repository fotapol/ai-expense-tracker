import 'package:flutter/material.dart';
import '../core/api_client.dart';
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

  Color _getCategoryColor(int index) {
    const colors = [
      Color(0xFFFF7043), // Deep Orange
      Color(0xFFAB47BC), // Purple
      Color(0xFF29B6F6), // Light Blue
      Color(0xFFFFCA28), // Amber
      Color(0xFF66BB6A), // Green
      Color(0xFFEC407A), // Pink
      Color(0xFF8D6E63), // Brown
      Color(0xFF26A69A), // Teal
      Color(0xFF5C6BC0), // Indigo
      Color(0xFFEF5350), // Red
      Color(0xFF42A5F5), // Blue
      Color(0xFFFFA726), // Orange
    ];
    return colors[index % colors.length];
  }

  IconData _getCategoryIcon(String code) {
    switch (code) {
      case 'FOOD':
        return Icons.restaurant;
      case 'CLOTHING':
        return Icons.checkroom;
      case 'TRANSPORT':
        return Icons.directions_car;
      case 'UTILITIES':
        return Icons.bolt;
      case 'HEALTH':
        return Icons.favorite;
      case 'ENTERTAINMENT':
        return Icons.movie;
      case 'HOME':
        return Icons.home;
      case 'ELECTRONICS':
        return Icons.devices;
      case 'EDUCATION':
        return Icons.school;
      case 'PERSONAL_CARE':
        return Icons.spa;
      case 'OTHER':
        return Icons.more_horiz;
      default:
        return Icons.label;
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
          title: const Text('New Subcategory'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedParentId,
                decoration: const InputDecoration(
                  labelText: 'Parent category',
                  border: OutlineInputBorder(),
                ),
                items: parentOptions
                    .map(
                      (parent) => DropdownMenuItem<String>(
                        value: parent['id'] as String,
                        child: Text(parent['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedParentId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Subcategory name (e.g., Coffee)',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
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
              child: const Text('Create'),
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
            SnackBar(content: Text('Subcategory "${result['name']}" created!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteCategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiClient.deleteCategory(id);
        _fetchCategories();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('"$name" deleted.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildCategoryItem(Map<String, dynamic> cat, int index) {
    final code = cat['code'] as String? ?? '';
    final name = cat['name'] as String? ?? '';
    final isDefault = cat['is_default'] as bool? ?? false;
    final id = cat['id'] as String;

    final color = _getCategoryColor(index);
    final icon = _getCategoryIcon(code);

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
                    isDefault ? 'Built-in' : 'Custom',
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
        title: const Text('Categories'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCategoryDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Subcategory'),
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
          'No categories found.',
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
            child: _buildCategoryItem(cat, index),
          );
        },
      ),
    );
  }
}
