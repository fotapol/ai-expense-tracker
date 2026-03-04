import 'package:flutter/material.dart';
import '../core/api_client.dart';

class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key});

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  bool _isLoading = true;
  List<dynamic> _labels = [];
  String? _error;

  static const List<Color> _labelColors = [
    Color(0xFF26A69A),
    Color(0xFF5C6BC0),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF66BB6A),
    Color(0xFFFF7043),
    Color(0xFF42A5F5),
    Color(0xFFFFA726),
    Color(0xFFEC407A),
    Color(0xFF29B6F6),
  ];

  @override
  void initState() {
    super.initState();
    _fetchLabels();
  }

  Future<void> _fetchLabels() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await ApiClient.listLabels();
      setState(() { _labels = data; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _showAddLabelDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Label name (e.g., Business)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Create')),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      try {
        await ApiClient.createLabel(result.trim());
        _fetchLabels();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Label "$result" created!')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _deleteLabel(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Label'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        await ApiClient.deleteLabel(id);
        _fetchLabels();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$name" deleted.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Labels'), backgroundColor: Colors.transparent, elevation: 0),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLabelDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Label'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 16),
        Text('Error: $_error'),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _fetchLabels, child: const Text('Retry')),
      ]));
    }

    if (_labels.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.label_outline, size: 64, color: Colors.grey.shade600),
        const SizedBox(height: 16),
        Text('No labels yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
        const SizedBox(height: 8),
        Text('Create labels to tag your receipts', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _fetchLabels,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _labels.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final label = _labels[index];
          final name = label['name'] as String? ?? '';
          final color = _labelColors[index % _labelColors.length];

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.label, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () => _deleteLabel(label['id'], name),
              ),
            ]),
          );
        },
      ),
    );
  }
}
