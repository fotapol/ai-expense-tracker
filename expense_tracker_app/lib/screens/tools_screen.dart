import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data_transfer_actions.dart';
import '../core/redesign_system.dart';
import '../core/single_user_launch.dart';
import '../l10n/app_localizations.dart';
import '../widgets/surface_action.dart';
import 'analytics_screen.dart';
import 'bill_reminders_screen.dart';
import 'budget_calculator_screen.dart';
import 'categories_screen.dart';
import 'duplicate_finder_screen.dart';
import 'labels_screen.dart';
import 'receipt_manager_screen.dart';
import 'receipt_upload_screen.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});
  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  static const _prefsKey = 'tools_pinned_ids_v1';
  List<String> _pins = ['scan', 'receipts', 'analytics'];
  List<String> _savedPins = ['scan', 'receipts', 'analytics'];
  bool _ready = false;
  int _revision = 0;
  Future<void> _writes = Future.value();

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pins = prefs.getStringList(_prefsKey);
      if (!mounted) return;
      setState(() {
        if (pins != null) _pins = pins.toSet().toList();
        _savedPins = List.of(_pins);
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  void _togglePin(String id) {
    if (!_ready) return;
    final revision = ++_revision;
    setState(() {
      _pins = List.of(_pins);
      if (_pins.contains(id)) {
        _pins.remove(id);
      } else {
        _pins.add(id);
      }
    });
    final snapshot = List<String>.of(_pins);
    // Serialize snapshots so a slower write cannot overwrite a newer order.
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setStringList(_prefsKey, snapshot)) {
          throw StateError('Tool preferences were not saved');
        }
        _savedPins = snapshot;
      } catch (_) {
        if (!mounted || revision != _revision) return;
        setState(() => _pins = List.of(_savedPins));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('error_generic'))));
      }
    });
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ShellStyles.scaled(context, 12, min: 12, max: 16);
    final bottomPadding = MediaQuery.of(context).padding.bottom + 104;

    final sections = <(String, List<_ToolTileData>)>[
      (
        context.tr('tools_core'),
        [
          _ToolTileData(
            id: 'scan',
            icon: AppIcons.scan,
            title: context.tr('tools_scan_receipt'),
            subtitle: context.tr('quick_scan_with_ai_review'),
            onTap: () => _open(context, const ReceiptUploadScreen()),
          ),
          _ToolTileData(
            id: 'receipts',
            icon: AppIcons.receipt,
            title: context.tr('tools_receipt_manager'),
            subtitle: context.tr('tools_receipt_manager_subtitle'),
            onTap: () => _open(context, const ReceiptManagerScreen()),
          ),
          _ToolTileData(
            id: 'analytics',
            icon: AppIcons.analyticsAlt,
            title: context.tr('tools_analytics'),
            subtitle: context.tr('tools_analytics_subtitle'),
            onTap: () => _open(context, const AnalyticsScreen()),
          ),
          _ToolTileData(
            id: 'duplicates',
            icon: AppIcons.copy,
            title: context.tr('duplicates_title'),
            subtitle: context.tr('duplicates_subtitle'),
            onTap: () => _open(context, const DuplicateFinderScreen()),
          ),
          _ToolTileData(
            id: 'categories',
            icon: AppIcons.category,
            title: context.tr('tools_categories'),
            subtitle: context.tr('tools_categories_subtitle'),
            onTap: () => _open(context, const CategoriesScreen()),
          ),
          _ToolTileData(
            id: 'labels',
            icon: AppIcons.labels,
            title: context.tr('settings_labels'),
            subtitle: context.tr('settings_manage_labels'),
            onTap: () => _open(context, const LabelsScreen()),
          ),
        ],
      ),
      (
        context.tr('tools_planning'),
        [
          _ToolTileData(
            id: 'budget',
            icon: AppIcons.budget,
            title: context.tr('tools_budget_calculator'),
            subtitle: context.tr('tools_budget_calculator_subtitle'),
            onTap: () => _open(context, const BudgetCalculatorScreen()),
          ),
          _ToolTileData(
            id: 'reminders',
            icon: AppIcons.notifications,
            title: context.tr('tools_bill_reminders'),
            subtitle: context.tr('tools_bill_reminders_subtitle'),
            onTap: () => _open(context, const BillRemindersScreen()),
          ),
        ],
      ),
      if (launchEnableDataTransferTools)
        (
          context.tr('tools_data'),
          [
            _ToolTileData(
              id: 'export',
              icon: AppIcons.export,
              title: context.tr('tools_export_data'),
              subtitle: context.tr('tools_export_data_subtitle'),
              onTap: () => DataTransferActions.exportData(context),
            ),
            _ToolTileData(
              id: 'import',
              icon: AppIcons.importData,
              title: context.tr('tools_import_data'),
              subtitle: context.tr('tools_import_data_subtitle'),
              onTap: () => DataTransferActions.importData(context),
            ),
          ],
        ),
    ];
    final tools = {
      for (final section in sections)
        for (final tile in section.$2) tile.id: tile,
    };
    final pinned = [
      for (final id in _pins)
        if (tools.containsKey(id)) tools[id]!,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          ShellStyles.scaled(context, 18, min: 16, max: 22),
          horizontalPadding,
          bottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('nav_tools'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: ShellStyles.scaled(context, 26, min: 22, max: 30),
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 4, min: 3, max: 6)),
            Text(
              context.tr('tools_subtitle'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: ShellStyles.scaled(context, 12.5, min: 12, max: 13.5),
                height: 1.3,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 18, min: 14, max: 20)),
            Text(
              context.tr('tools_pin_hint'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (pinned.isNotEmpty) ...[
              _buildToolSection(
                context,
                title: context.tr('tools_pinned'),
                tiles: pinned,
              ),
              const SizedBox(height: 16),
            ],
            for (final section in sections)
              if (section.$2.any((tile) => !_pins.contains(tile.id))) ...[
                _buildToolSection(
                  context,
                  title: section.$1,
                  tiles: section.$2
                      .where((tile) => !_pins.contains(tile.id))
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolSection(
    BuildContext context, {
    required String title,
    required List<_ToolTileData> tiles,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: ShellStyles.scaled(context, 2, min: 0, max: 4),
            bottom: ShellStyles.scaled(context, 8, min: 6, max: 10),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: ShellStyles.scaled(context, 12, min: 11, max: 13),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (var index = 0; index < tiles.length; index++) ...[
          _buildListTile(context, tiles[index]),
          if (index != tiles.length - 1)
            SizedBox(height: ShellStyles.scaled(context, 10, min: 8, max: 12)),
        ],
      ],
    );
  }

  Widget _buildListTile(BuildContext context, _ToolTileData tile) {
    final pinned = _pins.contains(tile.id);
    final pinLabel = context.tr(pinned ? 'tools_unpin' : 'tools_pin');
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: pinLabel): () => _togglePin(tile.id),
      },
      child: SurfaceAction(
        key: ValueKey('tool-${tile.id}'),
        onTap: tile.onTap,
        onLongPress: _ready ? () => _togglePin(tile.id) : null,
        radius: 18,
        highlighted: pinned,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: ShellStyles.scaled(context, 38, min: 34, max: 42),
              height: ShellStyles.scaled(context, 38, min: 34, max: 42),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pinned
                    ? ShellStyles.accentTone(context).base
                    : ShellStyles.accentTone(context).container,
                borderRadius: BorderRadius.circular(
                  ShellStyles.scaled(context, 12, min: 10, max: 14),
                ),
                border: Border.all(
                  color: ShellStyles.accentTone(context).border,
                ),
              ),
              child: Icon(
                tile.icon,
                color: pinned
                    ? ShellStyles.accentTone(context).onSolid
                    : ShellStyles.accentTone(context).foreground,
                size: ShellStyles.scaled(context, 18, min: 16, max: 20),
              ),
            ),
            SizedBox(width: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: ShellStyles.scaled(
                        context,
                        14,
                        min: 13,
                        max: 15,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(
                    height: ShellStyles.scaled(context, 2, min: 1, max: 4),
                  ),
                  Text(
                    tile.subtitle,
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: ShellStyles.scaled(
                        context,
                        11,
                        min: 10.5,
                        max: 12,
                      ),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (pinned) ...[
              const SizedBox(width: 8),
              Tooltip(
                triggerMode: TooltipTriggerMode.manual,
                message: pinLabel,
                child: Icon(
                  AppIcons.pin,
                  size: 18,
                  color: ShellStyles.accentTone(context).foreground,
                ),
              ),
            ],
            SizedBox(width: ShellStyles.scaled(context, 10, min: 8, max: 12)),
            Icon(
              AppIcons.chevronRight,
              color: ShellStyles.textMuted(context),
              size: ShellStyles.scaled(context, 16, min: 14, max: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolTileData {
  const _ToolTileData({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
