import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../widgets/filter_bottom_sheet.dart';
// TODO(household): re-import analytics_household_tab when household feature ships
import 'analytics_overview_tab.dart';
import 'analytics_tab.dart';
import 'analytics_trends_tab.dart';

enum AnalyticsSection {
  overview,
  trends,
  categories,
  // TODO(household): add households back when household feature ships
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  String? _error;
  AnalyticsSection _selectedSection = AnalyticsSection.overview;
  AnalyticsFilters _filters = const AnalyticsFilters();
  Map<String, String> _categoryNamesById = {};
  Map<String, String> _labelNamesById = {};
  Set<String> _featureCodes = <String>{};

  @override
  void initState() {
    super.initState();
    _loadShellState();
  }

  Future<void> _loadShellState() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSection = prefs.getString('analytics_section');
      final savedPeriod = prefs.getString('analytics_period');
      final savedCategoryIds =
          prefs.getStringList('analytics_category_ids') ?? const <String>[];
      final savedSubcategoryIds =
          prefs.getStringList('analytics_subcategory_ids') ?? const <String>[];
      final savedLabelIds =
          prefs.getStringList('analytics_label_ids') ?? const <String>[];

      Map<String, String> categoryNamesById = {};
      Map<String, String> labelNamesById = {};
      Set<String> featureCodes = <String>{};

      try {
        final categories = await ApiClient.listCategories();
        if (!mounted) return;
        categoryNamesById = {
          for (final category in categories)
            if (category['id'] != null)
              category['id'].toString(): localizeCategoryByCode(
                context,
                code: category['code']?.toString(),
                fallbackName: category['name']?.toString(),
              ),
        };
      } catch (_) {}

      try {
        final labels = await ApiClient.listLabels();
        labelNamesById = {
          for (final label in labels)
            if (label['id'] != null && label['name'] != null)
              label['id'].toString(): label['name'].toString(),
        };
      } catch (_) {}

      try {
        final entitlements = await ApiClient.getMeEntitlements();
        featureCodes =
            (entitlements['feature_codes'] as List<dynamic>? ??
                    const <dynamic>[])
                .map((code) => code.toString())
                .toSet();
      } catch (_) {}

      // TODO(household): restore getCurrentHousehold() call when household feature ships

      if (!mounted) return;
      setState(() {
        _selectedSection = AnalyticsSection.values.firstWhere(
          (section) => section.name == savedSection,
          orElse: () => AnalyticsSection.overview,
        );
        _filters = AnalyticsFilters(
          period: savedPeriod ?? _filters.period,
          categoryIds: savedCategoryIds,
          subcategoryIds: savedSubcategoryIds,
          labelIds: savedLabelIds,
        );
        _categoryNamesById = categoryNamesById;
        _labelNamesById = labelNamesById;
        _featureCodes = featureCodes;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_period', _filters.period);
    await prefs.setStringList('analytics_category_ids', _filters.categoryIds);
    await prefs.setStringList(
      'analytics_subcategory_ids',
      _filters.subcategoryIds,
    );
    await prefs.setStringList('analytics_label_ids', _filters.labelIds);
  }

  Future<void> _saveSection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_section', _selectedSection.name);
  }

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _filters.period,
      selectedCategoryIds: _filters.categoryIds,
      selectedSubcategoryIds: _filters.subcategoryIds,
      selectedLabelIds: _filters.labelIds,
    );
    if (result == null) return;

    setState(() {
      _filters = _filters.copyWith(
        period: result['period'] as String? ?? _filters.period,
        categoryIds: List<String>.from(result['category_ids'] ?? const []),
        subcategoryIds: List<String>.from(
          result['subcategory_ids'] ?? const [],
        ),
        labelIds: List<String>.from(result['label_ids'] ?? const []),
      );
    });
    await _saveFilters();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _filters = _filters.copyWith(
        categoryIds: const <String>[],
        subcategoryIds: const <String>[],
        labelIds: const <String>[],
      );
    });
    await _saveFilters();
  }

  void _selectSection(AnalyticsSection section) {
    if (section == _selectedSection) return;
    setState(() => _selectedSection = section);
    _saveSection();
  }

  Widget _buildSectionChip(AnalyticsSection section) {
    final isSelected = _selectedSection == section;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectSection(section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? ShellStyles.surface(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            context.tr(_sectionLabelKey(section)),
            style: TextStyle(
              color: isSelected
                  ? ShellStyles.textPrimary(context)
                  : ShellStyles.textMuted(context),
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _sectionLabelKey(AnalyticsSection section) {
    switch (section) {
      case AnalyticsSection.overview:
        return 'analytics_tab_overview';
      case AnalyticsSection.trends:
        return 'analytics_tab_trends';
      case AnalyticsSection.categories:
        return 'analytics_tab_categories';
      // TODO(household): add households case back when household feature ships
    }
  }

  Widget _buildFilterChip(
    String label, {
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    if (!_filters.hasScopedFilters) return const SizedBox.shrink();

    final categoryLabels = _filters.categoryIds
        .map((id) => _categoryNamesById[id] ?? context.tr('filters_category'))
        .toList();
    final subcategoryLabels = _filters.subcategoryIds
        .map((id) => _categoryNamesById[id] ?? context.tr('filters_subcategory'))
        .toList();
    final labelLabels = _filters.labelIds
        .map((id) => _labelNamesById[id] ?? context.tr('filters_labels'))
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr('analytics_active_filters'),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearFilters,
                child: Text(context.tr('filters_clear_all')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              ...categoryLabels.map(
                (label) => _buildFilterChip(
                  label,
                  icon: Icons.category_outlined,
                  color: ShellColors.softBlue,
                ),
              ),
              ...subcategoryLabels.map(
                (label) => _buildFilterChip(
                  label,
                  icon: Icons.account_tree_outlined,
                  color: const Color(0xFF2C8B72),
                ),
              ),
              ...labelLabels.map(
                (label) => _buildFilterChip(
                  label,
                  icon: Icons.label_outline,
                  color: const Color(0xFFB96A38),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('tools_analytics')),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: _filters.activeFilterCount > 0,
                label: Text('${_filters.activeFilterCount}'),
                child: const Icon(Icons.tune),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: ShellColors.softRed,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error ?? context.tr('common_error'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadShellState,
                          child: Text(context.tr('common_retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ShellStyles.surfaceAlt(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ShellStyles.border(context)),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: AnalyticsSection.values
                                .map(_buildSectionChip)
                                .toList(),
                          ),
                        ),
                      ),
                    ),
                    if (_filters.hasScopedFilters)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: _buildActiveFiltersBar(),
                      ),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedSection.index,
                        children: [
                          // TODO(household): restore currentHousehold/onHouseholdUpdated
                          // params to AnalyticsOverviewTab when household feature ships
                          AnalyticsOverviewTab(filters: _filters),
                          AnalyticsTrendsTab(filters: _filters),
                          AnalyticsTab(
                            filters: _filters,
                            featureCodes: _featureCodes,
                          ),
                          // TODO(household): restore AnalyticsHouseholdTab when household feature ships
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
