import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics_filters.dart';
import '../core/analytics_filter_preferences.dart';
import '../core/api_client.dart';
import '../core/app_color_semantics.dart';
import '../core/app_navigation.dart';
import '../core/app_motion.dart';
import '../core/launch_error_copy.dart';
import '../core/localized_dates.dart';
import '../core/period_filter.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../core/subscription_confirmation.dart';
import '../core/taxonomy_localization.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_tab_footer.dart';
import '../widgets/keep_alive_tab.dart';
import '../widgets/analytics_shared.dart';
import '../widgets/filter_bottom_sheet.dart';
import 'analytics_overview_tab.dart';
import 'analytics_tab.dart';
import 'analytics_trends_tab.dart';

enum AnalyticsSection { overview, trends, categories }

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
  int _sectionTransition = 0;
  bool _animatingSection = false;
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
      final savedFilters = AnalyticsFilterPreferences.load(prefs);

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

      if (!mounted) return;
      setState(() {
        _selectedSection = AnalyticsSection.values.firstWhere(
          (section) => section.name == savedSection,
          orElse: () => AnalyticsSection.overview,
        );
        _filters = savedFilters;
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
    await AnalyticsFilterPreferences.save(prefs, _filters);
  }

  Future<void> _saveSection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('analytics_section', _selectedSection.name);
  }

  Future<void> _openFilters() async {
    final result = await FilterBottomSheet.show(
      context,
      selectedPeriod: _filters.period,
      selectedCustomRange: _filters.customRange,
      selectedCategoryIds: _filters.categoryIds,
      selectedSubcategoryIds: _filters.subcategoryIds,
      selectedLabelIds: _filters.labelIds,
    );
    if (result == null || !mounted) return;

    setState(() {
      _showAllActiveFilters = false;
      _filters = _filters.copyWith(
        period: result['period'] as String? ?? _filters.period,
        customRange: result['custom_range'] as PeriodDateRange?,
        categoryIds: List<String>.from(result['category_ids'] ?? const []),
        subcategoryIds: List<String>.from(
          result['subcategory_ids'] ?? const [],
        ),
        labelIds: List<String>.from(result['label_ids'] ?? const []),
      );
    });
    await _saveFilters();
  }

  Future<void> _selectSection(AnalyticsSection section) async {
    if (section == _selectedSection) return;
    final request = ++_sectionTransition;
    setState(() {
      _selectedSection = section;
      _animatingSection = true;
    });
    if (_pageController.hasClients) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pageController.jumpToPage(section.index);
      } else {
        await _pageController.animateToPage(
          section.index,
          duration: AppMotion.duration(context),
          curve: AppMotion.curve,
        );
      }
    }
    if (!mounted || request != _sectionTransition) return;
    _animatingSection = false;
    _saveSection();
  }

  void _handlePageChanged(int index) {
    if (_animatingSection) return;
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

  Widget _buildSectionChip(AnalyticsSection section, double height) {
    final selected = _selectedSection == section;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('analytics-section-${section.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectSection(section),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: AppMotion.duration(context),
                curve: AppMotion.curve,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: selected
                      ? ShellStyles.accentTone(context).foreground
                      : ShellStyles.textMuted(context),
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
                child: Text(
                  context.tr(_sectionLabelKey(section)),
                  textAlign: TextAlign.center,
                ),
              ),
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

  Widget _buildSectionSelector() => LayoutBuilder(
    builder: (context, constraints) {
      final sections = AnalyticsSection.values;
      final width = (constraints.maxWidth - 12) / sections.length;
      var height = 48.0;
      for (final section in sections) {
        final painter = TextPainter(
          text: TextSpan(
            text: context.tr(_sectionLabelKey(section)),
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: width - 16);
        if (painter.height + 20 > height) height = painter.height + 20;
        painter.dispose();
      }
      return DecoratedBox(
        decoration: ShellStyles.cardDecoration(context, radius: 20),
        child: Material(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    final position =
                        _pageController.hasClients &&
                            _pageController.position.hasContentDimensions
                        ? _pageController.page ??
                              _selectedSection.index.toDouble()
                        : _selectedSection.index.toDouble();
                    return PositionedDirectional(
                      start: position * width,
                      child: Container(
                        key: const ValueKey('analytics-tab-indicator'),
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: ShellStyles.accentTone(context).container,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    for (final section in sections)
                      Expanded(child: _buildSectionChip(section, height)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    children: [
                      _buildSectionSelector(),
                      if (_filters.period == PeriodFilter.custom) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _openFilters,
                          icon: const Icon(Icons.date_range_outlined, size: 18),
                          label: Text(
                            formatLocalizedDateRange(
                              context,
                              _filters.customRange!.start!,
                              _filters.customRange!.end!,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth == 0 &&
                          notification.metrics.axis == Axis.horizontal) {
                        if (notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          _sectionTransition++;
                          _animatingSection = false;
                        } else if (notification is ScrollEndNotification &&
                            !_animatingSection) {
                          _handlePageChanged(_pageController.page!.round());
                        }
                      }
                      return false;
                    },
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: _handlePageChanged,
                      children: [
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
                      ].map((child) => KeepAliveTab(child: child)).toList(),
                    ),
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
