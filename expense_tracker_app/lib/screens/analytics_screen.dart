import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics_filters.dart';
import '../core/api_client.dart';
import '../core/app_color_semantics.dart';
import '../core/app_navigation.dart';
import '../core/launch_error_copy.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/subscription_confirmation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_tab_footer.dart';
import '../widgets/analytics_shared.dart';
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
  static const int _collapsedActiveFilterLimit = 4;

  late final PageController _pageController;
  bool _isLoading = true;
  String? _error;
  AnalyticsSection _selectedSection = AnalyticsSection.overview;
  bool _showAllActiveFilters = false;
  AnalyticsFilters _filters = const AnalyticsFilters();
  Map<String, String> _categoryNamesById = {};
  Map<String, String> _categoryCodesById = {};
  Map<String, String> _categoryParentCodesById = {};
  Map<String, String> _categoryColorsById = {};
  Map<String, String> _labelNamesById = {};
  Map<String, String> _labelColorsById = {};
  Set<String> _featureCodes = <String>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedSection.index);
    _loadShellState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshFeatureCodes() async {
    try {
      final entitlements = await ApiClient.getMeEntitlements();
      final mergedFeatureCodes = await featureCodesWithOptimisticPremiumAccess(
        (entitlements['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
            .map((code) => code.toString()),
      );
      if (!mounted) return;
      setState(() {
        _featureCodes = mergedFeatureCodes;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      final mergedFeatureCodes = await featureCodesWithOptimisticPremiumAccess(
        const <String>{},
      );
      if (!mounted) return;
      setState(() {
        _featureCodes = mergedFeatureCodes;
      });
    }
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
      Map<String, String> categoryCodesById = {};
      Map<String, String> categoryParentCodesById = {};
      Map<String, String> categoryColorsById = {};
      Map<String, String> labelNamesById = {};
      Map<String, String> labelColorsById = {};
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
        categoryCodesById = {
          for (final category in categories)
            if (category['id'] != null)
              category['id'].toString(): category['code']?.toString() ?? '',
        };
        categoryParentCodesById = {
          for (final category in categories)
            if (category['id'] != null)
              category['id'].toString():
                  category['parent_category_code']?.toString() ?? '',
        };
        categoryColorsById = {
          for (final category in categories)
            if (category['id'] != null)
              category['id'].toString(): category['color']?.toString() ?? '',
        };
      } catch (_) {}

      try {
        final labels = await ApiClient.listLabels();
        labelNamesById = {
          for (final label in labels)
            if (label['id'] != null && label['name'] != null)
              label['id'].toString(): label['name'].toString(),
        };
        labelColorsById = {
          for (final label in labels)
            if (label['id'] != null)
              label['id'].toString(): label['color']?.toString() ?? '',
        };
      } catch (_) {}

      try {
        final entitlements = await ApiClient.getMeEntitlements();
        featureCodes = await featureCodesWithOptimisticPremiumAccess(
          (entitlements['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
              .map((code) => code.toString()),
        );
      } catch (_) {}
      featureCodes = await featureCodesWithOptimisticPremiumAccess(
        featureCodes,
      );

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
        _categoryCodesById = categoryCodesById;
        _categoryParentCodesById = categoryParentCodesById;
        _categoryColorsById = categoryColorsById;
        _labelNamesById = labelNamesById;
        _labelColorsById = labelColorsById;
        _featureCodes = featureCodes;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(_selectedSection.index);
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback: context.tr('analytics_error_message'),
        );
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
      _showAllActiveFilters = false;
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

  void _selectSection(AnalyticsSection section) {
    if (section == _selectedSection) return;
    setState(() => _selectedSection = section);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        section.index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    _saveSection();
  }

  void _handlePageChanged(int index) {
    final section = AnalyticsSection.values[index];
    if (section == _selectedSection) return;
    setState(() => _selectedSection = section);
    _saveSection();
  }

  void _openRootTab(int index) {
    selectRootTab(index);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Widget _buildSectionChip(AnalyticsSection section) {
    final isSelected = _selectedSection == section;
    final accentTone = ShellStyles.accentTone(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _selectSection(section),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accentTone.container : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(
                      ShellStyles.isDark(context) ? 20 : 12,
                    ),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Text(
          context.tr(_sectionLabelKey(section)),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? accentTone.foreground
                : ShellStyles.textMuted(context),
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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
    VoidCallback? onDeleted,
    SemanticColorTone? tone,
  }) {
    final resolvedTone = tone ?? ShellStyles.accentTone(context);
    return InputChip(
      avatar: Icon(icon, size: 16, color: resolvedTone.foreground),
      label: Text(
        label,
        style: TextStyle(
          color: resolvedTone.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: resolvedTone.container,
      side: BorderSide(color: resolvedTone.border),
      deleteIconColor: resolvedTone.foreground,
      onDeleted: onDeleted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Future<void> _clearAllFilters() async {
    setState(() {
      _showAllActiveFilters = false;
      _filters = _filters.copyWith(
        categoryIds: const <String>[],
        subcategoryIds: const <String>[],
        labelIds: const <String>[],
      );
    });
    await _saveFilters();
  }

  Widget _buildActiveFiltersBar() {
    if (!_filters.hasScopedFilters) return const SizedBox.shrink();

    final chips = <Widget>[
      ..._filters.categoryIds.map(
        (id) => _buildFilterChip(
          _categoryNamesById[id] ?? context.tr('filters_category'),
          icon: Icons.category_outlined,
          tone: ShellStyles.categoryTone(
            context,
            code: _categoryCodesById[id],
            parentCode: _categoryParentCodesById[id],
            name: _categoryNamesById[id],
            rawHex: _categoryColorsById[id],
          ),
          onDeleted: () {
            setState(() {
              final newIds = List<String>.from(_filters.categoryIds)
                ..remove(id);
              _filters = _filters.copyWith(categoryIds: newIds);
            });
            _saveFilters();
          },
        ),
      ),
      ..._filters.subcategoryIds.map(
        (id) => _buildFilterChip(
          _categoryNamesById[id] ?? context.tr('filters_subcategory'),
          icon: Icons.account_tree_outlined,
          tone: ShellStyles.categoryTone(
            context,
            code: _categoryCodesById[id],
            parentCode: _categoryParentCodesById[id],
            name: _categoryNamesById[id],
            rawHex: _categoryColorsById[id],
          ),
          onDeleted: () {
            setState(() {
              final newIds = List<String>.from(_filters.subcategoryIds)
                ..remove(id);
              _filters = _filters.copyWith(subcategoryIds: newIds);
            });
            _saveFilters();
          },
        ),
      ),
      ..._filters.labelIds.map(
        (id) => _buildFilterChip(
          _labelNamesById[id] ?? context.tr('filters_labels'),
          icon: Icons.label_outline,
          tone: ShellStyles.labelTone(
            context,
            labelId: id,
            name: _labelNamesById[id],
            rawHex: _labelColorsById[id],
          ),
          onDeleted: () {
            setState(() {
              final newIds = List<String>.from(_filters.labelIds)..remove(id);
              _filters = _filters.copyWith(labelIds: newIds);
            });
            _saveFilters();
          },
        ),
      ),
    ];

    final hasOverflow = chips.length > _collapsedActiveFilterLimit;
    final visibleChips = _showAllActiveFilters || !hasOverflow
        ? chips
        : chips.take(_collapsedActiveFilterLimit).toList(growable: false);
    final hiddenCount = chips.length - visibleChips.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: 20,
        color: ShellStyles.surfaceAlt(context),
        withShadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('analytics_active_filters'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearAllFilters,
                style: TextButton.styleFrom(
                  foregroundColor: ShellStyles.textPrimary(context),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: Text(context.tr('analytics_clear_all_filters')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: visibleChips),
          if (hasOverflow) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _showAllActiveFilters = !_showAllActiveFilters;
                  });
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: ShellStyles.textPrimary(context),
                  side: BorderSide(color: ShellStyles.border(context)),
                  backgroundColor: ShellStyles.surface(context),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
                child: Text(
                  _showAllActiveFilters
                      ? context.tr('analytics_show_fewer_filters')
                      : context.tr(
                          'analytics_view_all_active_filters',
                          params: {'count': hiddenCount.toString()},
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionSelector() {
    final sections = AnalyticsSection.values;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ShellStyles.sectionBackground(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShellStyles.border(context)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            Expanded(child: _buildSectionChip(sections[index])),
            if (index != sections.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterAction() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _openFilters,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ShellStyles.elevatedSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ShellStyles.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 16, color: ShellStyles.textPrimary(context)),
            const SizedBox(width: 8),
            Text(
              context.tr('filters_title'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: _buildFilterAction()),
          ),
        ],
      ),
      body: _isLoading
          ? const AnalyticsLoadingState()
          : _error != null
          ? AnalyticsErrorState(
              message: _error ?? context.tr('common_error'),
              onRetry: _loadShellState,
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  decoration: BoxDecoration(
                    color: ShellStyles.sectionBackground(context),
                    border: Border(
                      bottom: BorderSide(color: ShellStyles.divider(context)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(
                          ShellStyles.isDark(context) ? 18 : 6,
                        ),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(children: [_buildSectionSelector()]),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _handlePageChanged,
                    children: [
                      // TODO(household): restore currentHousehold/onHouseholdUpdated
                      // params to AnalyticsOverviewTab when household feature ships
                      AnalyticsOverviewTab(
                        filters: _filters,
                        activeFiltersBuilder: _filters.hasScopedFilters
                            ? _buildActiveFiltersBar
                            : null,
                      ),
                      AnalyticsTrendsTab(
                        filters: _filters,
                        activeFiltersBuilder: _filters.hasScopedFilters
                            ? _buildActiveFiltersBar
                            : null,
                      ),
                      AnalyticsTab(
                        filters: _filters,
                        featureCodes: _featureCodes,
                        onPremiumStatusChanged: _refreshFeatureCodes,
                        activeFiltersBuilder: _filters.hasScopedFilters
                            ? _buildActiveFiltersBar
                            : null,
                      ),
                      // TODO(household): restore AnalyticsHouseholdTab when household feature ships
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: AppTabFooter(
        selectedIndex: 1,
        onSelected: _openRootTab,
      ),
    );
  }
}
