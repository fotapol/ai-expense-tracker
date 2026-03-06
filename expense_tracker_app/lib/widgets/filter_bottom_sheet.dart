import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/period_filter.dart';

/// Reusable filter bottom sheet matching the screenshot design.
/// Returns a Map of selected filters or null if cancelled.
class FilterBottomSheet extends StatefulWidget {
  final String selectedPeriod;
  final List<String>? selectedCategoryIds;
  final List<String>? selectedSubcategoryIds;
  final List<String>? selectedLabelIds;

  const FilterBottomSheet({
    super.key,
    required this.selectedPeriod,
    this.selectedCategoryIds,
    this.selectedSubcategoryIds,
    this.selectedLabelIds,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String selectedPeriod,
    List<String>? selectedCategoryIds,
    List<String>? selectedSubcategoryIds,
    List<String>? selectedLabelIds,
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
        selectedSubcategoryIds: selectedSubcategoryIds,
        selectedLabelIds: selectedLabelIds,
      ),
    );
  }

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _selectedPeriod;
  late Set<String> _selectedCategoryIds;
  late Set<String> _selectedSubcategoryIds;
  late Set<String> _selectedLabelIds;
  List<dynamic> _categories = [];
  List<dynamic> _labels = [];
  bool _loadingCats = true;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.selectedPeriod;
    _selectedCategoryIds = Set.from(widget.selectedCategoryIds ?? []);
    _selectedSubcategoryIds = Set.from(widget.selectedSubcategoryIds ?? []);
    _selectedLabelIds = Set.from(widget.selectedLabelIds ?? []);
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
        _pruneUnavailableSubcategories();
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
    if (_selectedSubcategoryIds.isNotEmpty) count++;
    if (_selectedLabelIds.isNotEmpty) count++;
    return count;
  }

  List<dynamic> get _topLevelCategories {
    return _categories.where((c) => c['parent_id'] == null).toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  List<dynamic> get _availableSubcategories {
    if (_selectedCategoryIds.isEmpty) return [];
    return _categories.where((c) {
        final parentId = c['parent_id'] as String?;
        return parentId != null && _selectedCategoryIds.contains(parentId);
      }).toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
  }

  void _pruneUnavailableSubcategories() {
    final availableIds = _availableSubcategories
        .map((c) => c['id'] as String)
        .toSet();
    _selectedSubcategoryIds.removeWhere((id) => !availableIds.contains(id));
  }

  void _clearAll() {
    setState(() {
      _selectedPeriod = PeriodFilter.last3Months;
      _selectedCategoryIds.clear();
      _selectedSubcategoryIds.clear();
      _selectedLabelIds.clear();
    });
  }

  void _apply() {
    Navigator.pop(context, {
      'period': _selectedPeriod,
      'category_ids': _selectedCategoryIds.toList(),
      'subcategory_ids': _selectedSubcategoryIds.toList(),
      'label_ids': _selectedLabelIds.toList(),
    });
  }

  Future<void> _openSubcategoryPicker() async {
    final available = _availableSubcategories;
    if (available.isEmpty) return;

    final initialSelected = Set<String>.from(_selectedSubcategoryIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String search = '';
        final selected = Set<String>.from(initialSelected);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = available.where((subcat) {
              final name = (subcat['name'] as String).toLowerCase();
              return name.contains(search.toLowerCase());
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select Subcategories',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search subcategory...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setModalState(() => search = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No matching subcategories'),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final subcat = filtered[index];
                                final id = subcat['id'] as String;
                                final name = subcat['name'] as String;
                                final checked = selected.contains(id);
                                return CheckboxListTile(
                                  value: checked,
                                  title: Text(name),
                                  onChanged: (value) {
                                    setModalState(() {
                                      if (value == true) {
                                        selected.add(id);
                                      } else {
                                        selected.remove(id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedSubcategoryIds = result;
      });
    }
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: _apply,
                    child: Text(
                      'Apply',
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
                  _buildSectionTitle(Icons.category, 'Category'),
                  const SizedBox(height: 8),
                  _buildCategoryChips(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(Icons.account_tree, 'Subcategory'),
                  const SizedBox(height: 8),
                  _buildSubcategoryPicker(),
                  const SizedBox(height: 24),
                  if (_labels.isNotEmpty) ...[
                    _buildSectionTitle(Icons.label, 'Labels'),
                    const SizedBox(height: 8),
                    _buildLabelChips(),
                    const SizedBox(height: 24),
                  ],
                  // Clear all button
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: Icon(
                      Icons.filter_alt_off,
                      color: Colors.red.shade400,
                    ),
                    label: Text(
                      'Clear All Filters',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 16,
                      ),
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
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryChips() {
    if (_loadingCats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return Text(
        'No categories available',
        style: TextStyle(color: Colors.grey.shade500),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _topLevelCategories.map((cat) {
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
              _pruneUnavailableSubcategories();
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

  Widget _buildSubcategoryPicker() {
    if (_loadingCats) {
      return const SizedBox.shrink();
    }
    if (_selectedCategoryIds.isEmpty) {
      return Text(
        'Select one or more categories to choose subcategories.',
        style: TextStyle(color: Colors.grey.shade500),
      );
    }
    final available = _availableSubcategories;
    if (available.isEmpty) {
      return Text(
        'No subcategories available for selected categories.',
        style: TextStyle(color: Colors.grey.shade500),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _openSubcategoryPicker,
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(
            _selectedSubcategoryIds.isEmpty
                ? 'Select subcategories'
                : '${_selectedSubcategoryIds.length} selected',
          ),
        ),
        if (_selectedSubcategoryIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available
                .where(
                  (subcat) => _selectedSubcategoryIds.contains(subcat['id']),
                )
                .map((subcat) {
                  final id = subcat['id'] as String;
                  final name = subcat['name'] as String;
                  return Chip(
                    label: Text(name),
                    onDeleted: () {
                      setState(() => _selectedSubcategoryIds.remove(id));
                    },
                  );
                })
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLabelChips() {
    if (_labels.isEmpty) {
      return Text(
        'No labels available',
        style: TextStyle(color: Colors.grey.shade500),
      );
    }

    final sortedLabels = [..._labels]
      ..sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sortedLabels.map((raw) {
        final label = raw as Map<String, dynamic>;
        final id = label['id']?.toString() ?? '';
        final name = label['name']?.toString() ?? 'Label';
        final isSelected = _selectedLabelIds.contains(id);
        return FilterChip(
          label: Text(name),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedLabelIds.add(id);
              } else {
                _selectedLabelIds.remove(id);
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
}
