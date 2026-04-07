import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';

class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({
    super.key,
    required this.selectedPeriod,
    this.selectedCategoryIds,
    this.selectedSubcategoryIds,
    this.selectedLabelIds,
  });

  final String selectedPeriod;
  final List<String>? selectedCategoryIds;
  final List<String>? selectedSubcategoryIds;
  final List<String>? selectedLabelIds;

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
    _selectedCategoryIds = Set<String>.from(widget.selectedCategoryIds ?? []);
    _selectedSubcategoryIds = Set<String>.from(
      widget.selectedSubcategoryIds ?? [],
    );
    _selectedLabelIds = Set<String>.from(widget.selectedLabelIds ?? []);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final cats = await ApiClient.listCategories();
      List<dynamic> labels = [];
      try {
        labels = await ApiClient.listLabels();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _labels = labels;
        _pruneUnavailableSubcategories();
        _loadingCats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCats = false);
    }
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedCategoryIds.isNotEmpty) count += 1;
    if (_selectedSubcategoryIds.isNotEmpty) count += 1;
    if (_selectedLabelIds.isNotEmpty) count += 1;
    return count;
  }

  String _localizedCategoryName(Map<String, dynamic> category) {
    return localizeCategoryByCode(
      context,
      code: category['code']?.toString(),
      fallbackName: category['name']?.toString(),
    );
  }

  List<dynamic> get _topLevelCategories {
    return _categories.where((c) => c['parent_id'] == null).toList()..sort(
      (a, b) => _localizedCategoryName(a as Map<String, dynamic>)
          .toLowerCase()
          .compareTo(
            _localizedCategoryName(b as Map<String, dynamic>).toLowerCase(),
          ),
    );
  }

  List<dynamic> get _availableSubcategories {
    if (_selectedCategoryIds.isEmpty) return [];
    return _categories.where((c) {
      final parentId = c['parent_id'] as String?;
      return parentId != null && _selectedCategoryIds.contains(parentId);
    }).toList()..sort(
      (a, b) => _localizedCategoryName(a as Map<String, dynamic>)
          .toLowerCase()
          .compareTo(
            _localizedCategoryName(b as Map<String, dynamic>).toLowerCase(),
          ),
    );
  }

  void _pruneUnavailableSubcategories() {
    final availableIds = _availableSubcategories
        .map((c) => c['id'] as String)
        .toSet();
    _selectedSubcategoryIds.removeWhere((id) => !availableIds.contains(id));
  }

  void _clearAll() {
    setState(() {
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
              final name = _localizedCategoryName(
                subcat as Map<String, dynamic>,
              ).toLowerCase();
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
                    Text(
                      context.tr('filters_select_subcategories'),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.tr('filters_search_subcategory'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (value) => setModalState(() => search = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                context.tr('filters_no_matching_subcategories'),
                                style: TextStyle(
                                  color: ShellStyles.textMuted(context),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final subcat = filtered[index];
                                final id = subcat['id'] as String;
                                final name = _localizedCategoryName(
                                  subcat as Map<String, dynamic>,
                                );
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
                          child: Text(context.tr('common_cancel')),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: Text(context.tr('common_apply')),
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

    if (result == null || !mounted) return;
    setState(() {
      _selectedSubcategoryIds = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.74,
      minChildSize: 0.48,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ShellStyles.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      context.tr('common_cancel'),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _activeFilterCount > 0
                          ? context.tr(
                              'filters_title_with_count',
                              params: {'count': _activeFilterCount.toString()},
                            )
                          : context.tr('filters_title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _apply,
                    child: Text(
                      context.tr('common_apply'),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSectionTitle(
                    icon: Icons.calendar_today_outlined,
                    title: context.tr('filters_period'),
                  ),
                  const SizedBox(height: 10),
                  _buildPeriodChips(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                    icon: Icons.category_outlined,
                    title: context.tr('filters_category'),
                  ),
                  const SizedBox(height: 10),
                  _buildCategoryChips(),
                  const SizedBox(height: 24),
                  _buildSectionTitle(
                    icon: Icons.account_tree_outlined,
                    title: context.tr('filters_subcategory'),
                  ),
                  const SizedBox(height: 10),
                  _buildSubcategoryPicker(),
                  if (_labels.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      icon: Icons.label_outline,
                      title: context.tr('filters_labels'),
                    ),
                    const SizedBox(height: 10),
                    _buildLabelChips(),
                  ],
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(
                      Icons.filter_alt_off,
                      color: ShellColors.softRed,
                    ),
                    label: const Text(
                      'Clear scoped filters',
                      style: TextStyle(
                        color: ShellColors.softRed,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ShellStyles.textPrimary(context)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
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
        return FilterChip(
          label: Text(context.tr(PeriodFilter.localizationKey(period))),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (_) {
            setState(() {
              _selectedPeriod = period;
            });
          },
          selectedColor: ShellStyles.textPrimary(context).withAlpha(18),
          backgroundColor: ShellStyles.surface(context),
          side: BorderSide(
            color: isSelected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.border(context),
          ),
          labelStyle: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
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
        context.tr('filters_no_categories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _topLevelCategories.map((cat) {
        final id = cat['id'] as String;
        final name = _localizedCategoryName(cat as Map<String, dynamic>);
        final isSelected = _selectedCategoryIds.contains(id);

        return FilterChip(
          label: Text(name),
          selected: isSelected,
          showCheckmark: false,
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
          selectedColor: ShellStyles.textPrimary(context).withAlpha(18),
          backgroundColor: ShellStyles.surface(context),
          side: BorderSide(
            color: isSelected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.border(context),
          ),
          labelStyle: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
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
        context.tr('filters_select_categories_for_subcategories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }
    final available = _availableSubcategories;
    if (available.isEmpty) {
      return Text(
        context.tr('filters_no_subcategories_for_categories'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _openSubcategoryPicker,
          style: OutlinedButton.styleFrom(
            foregroundColor: ShellStyles.textPrimary(context),
            backgroundColor: ShellStyles.surface(context),
            side: BorderSide(color: ShellStyles.border(context)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.arrow_drop_down),
          label: Text(
            _selectedSubcategoryIds.isEmpty
                ? context.tr('filters_select_subcategories')
                : context.tr(
                    'filters_selected_count',
                    params: {
                      'count': _selectedSubcategoryIds.length.toString(),
                    },
                  ),
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
                  final name = _localizedCategoryName(
                    subcat as Map<String, dynamic>,
                  );
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
        context.tr('filters_no_labels'),
        style: TextStyle(color: ShellStyles.textMuted(context)),
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
        final name = label['name']?.toString() ?? context.tr('labels_title');
        final isSelected = _selectedLabelIds.contains(id);
        return FilterChip(
          label: Text(name),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedLabelIds.add(id);
              } else {
                _selectedLabelIds.remove(id);
              }
            });
          },
          selectedColor: ShellStyles.textPrimary(context).withAlpha(18),
          backgroundColor: ShellStyles.surface(context),
          side: BorderSide(
            color: isSelected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.border(context),
          ),
          labelStyle: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }).toList(),
    );
  }
}
