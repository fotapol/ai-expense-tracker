import 'package:flutter/material.dart';
import '../core/api_client.dart';

class SubcategoriesScreen extends StatefulWidget {
  final String parentId;
  final String parentName;

  const SubcategoriesScreen({super.key, required this.parentId, required this.parentName});

  @override
  State<SubcategoriesScreen> createState() => _SubcategoriesScreenState();
}

class _SubcategoriesScreenState extends State<SubcategoriesScreen> {
  bool _isLoading = true;
  List<dynamic> _subcategories = [];
  String? _error;

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
      final data = await ApiClient.listCategories();
      final subs = data.where((c) => c['parent_id'] == widget.parentId).toList();
      setState(() {
        _subcategories = subs;
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
      Color(0xFFFF7043),
      Color(0xFFAB47BC),
      Color(0xFF29B6F6),
      Color(0xFFFFCA28),
      Color(0xFF66BB6A),
    ];
    return colors[index % colors.length];
  }

  Future<void> _showAddSubcategoryDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New Subcategory for ${widget.parentName}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Subcategory name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      try {
        await ApiClient.createCategory(result.trim(), parentId: widget.parentId);
        _fetchSubcategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Subcategory "$result" created!')),
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

  Future<void> _deleteSubcategory(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subcategory'),
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
        _fetchSubcategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$name" deleted.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.parentName} Subcategories'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _subcategories.isEmpty
                  ? Center(
                      child: Text(
                        'No subcategories found for ${widget.parentName}.',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _subcategories.length,
                      itemBuilder: (context, index) {
                        final cat = _subcategories[index];
                        final name = cat['name'] as String;
                        final id = cat['id'] as String;
                        final color = _getCategoryColor(index);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
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
                                child: Icon(Icons.subdirectory_arrow_right, color: color, size: 22),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _deleteSubcategory(id, name),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSubcategoryDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Subcategory'),
      ),
    );
  }
}
