import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/period_filter.dart';

/// Reusable filter bottom sheet matching the screenshot design.
/// Returns a Map of selected filters or null if cancelled.
class FilterBottomSheet extends StatefulWidget {
  final String selectedPeriod;
  final List<String>? selectedCategoryIds;
  final String? merchantSearch;

  const FilterBottomSheet({
    super.key,
    required this.selectedPeriod,
    this.selectedCategoryIds,
    this.merchantSearch,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String selectedPeriod,
    List<String>? selectedCategoryIds,
    String? merchantSearch,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FilterBottomSheet(
        selectedPeriod: selectedPeriod,
        selectedCategoryIds: selectedCategoryIds,
        merchantSearch: merchantSearch,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _selectedPeriod;
  late Set<String> _selectedCategoryIds;
  late TextEditingController _merchantController;
  List<dynamic> _categories = [];
  List<dynamic> _labels = [];
  bool _loadingCats = true;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.selectedPeriod;
    _selectedCategoryIds = Set.from(widget.selectedCategoryIds ?? []);
    _merchantController = TextEditingController(text: widget.merchantSearch ?? '');
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cats = await ApiClient.listCategories();
      List<dynamic> labels = [];
      try {
        labels = await ApiClient.listLabels();
      } catch (_) {}
      setState(() {
        _categories = cats;
        _labels = labels;
        _loadingCats = false;
      });
    } catch (e) {
      setState(() => _loadingCats = false);
    }
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedPeriod != PeriodFilter.last3Months) count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    if (_merchantController.text.trim().isNotEmpty) count++;
    return count;
  }

  void _clearAll() {
    setState(() {
      _selectedPeriod = PeriodFilter.last3Months;
      _selectedCategoryIds.clear();
      _merchantController.clear();
    });
  }

  void _apply() {
    Navigator.pop(context, {
      'period': _selectedPeriod,
      'category_ids': _selectedCategoryIds.toList(),
      'merchant_search': _merchantController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                  ),
                  Text(
                    'Filters${_activeFilterCount > 0 ? ' ($_activeFilterCount)' : ''}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _apply,
                    child: Text('Apply',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSectionTitle(Icons.calendar_today, 'Period'),
                  const SizedBox(height: 8),
                  _buildPeriodChips(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(Icons.store, 'Merchant'),
                  const SizedBox(height: 8),
                  _buildMerchantSearch(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(Icons.category, 'Category'),
                  const SizedBox(height: 8),
                  _buildCategoryChips(),
                  const SizedBox(height: 24),
                  if (_labels.isNotEmpty) ...[
                    _buildSectionTitle(Icons.label, 'Labels'),
                    const SizedBox(height: 8),
                    Text('Coming soon', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 24),
                  ],
                  // Clear all button
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: Icon(Icons.filter_alt_off, color: Colors.red.shade400),
                    label: Text('Clear All Filters',
                      style: TextStyle(color: Colors.red.shade400, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPeriodChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: PeriodFilter.values.map((period) {
        final isSelected = _selectedPeriod == period;
        return ChoiceChip(
          label: Text(period),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) setState(() => _selectedPeriod = period);
          },
          selectedColor: Theme.of(context).colorScheme.primary.withAlpha(40),
          side: BorderSide(
            color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade700,
          ),
          labelStyle: TextStyle(
            color: isSelected
              ? Theme.of(context).colorScheme.primary
              : null,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMerchantSearch() {
    return TextField(
      controller: _merchantController,
      decoration: InputDecoration(
        hintText: 'Search by store name...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildCategoryChips() {
    if (_loadingCats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return Text('No categories available', style: TextStyle(color: Colors.grey.shade500));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((cat) {
        final id = cat['id'] as String;
        final name = cat['name'] as String? ?? '';
        final isSelected = _selectedCategoryIds.contains(id);

        return FilterChip(
          label: Text(name),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedCategoryIds.add(id);
              } else {
                _selectedCategoryIds.remove(id);
              }
            });
          },
          selectedColor: Theme.of(context).colorScheme.primary.withAlpha(40),
          checkmarkColor: Theme.of(context).colorScheme.primary,
          side: BorderSide(
            color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade700,
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }
}
