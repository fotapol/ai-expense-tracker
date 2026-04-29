import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/data_transfer_actions.dart';
import '../core/redesign_system.dart';
import '../core/single_user_launch.dart';
import '../l10n/app_localizations.dart';
import 'analytics_screen.dart';
import 'bill_reminders_screen.dart';
import 'budget_calculator_screen.dart';
import 'categories_screen.dart';
import 'labels_screen.dart';
import 'receipt_manager_screen.dart';
import 'receipt_upload_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ShellStyles.scaled(context, 12, min: 12, max: 16);
    final bottomPadding = MediaQuery.of(context).padding.bottom + 104;

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
            Row(
              children: [
                Icon(
                  CupertinoIcons.pin_fill,
                  size: ShellStyles.scaled(context, 12, min: 11, max: 13),
                  color: ShellStyles.accentTone(context).base,
                ),
                const SizedBox(width: 6),
                ShellStyles.sectionLabel(
                  context,
                  context.tr('tools_most_used'),
                ),
              ],
            ),
            SizedBox(height: ShellStyles.scaled(context, 10, min: 8, max: 12)),
            Row(
              children: [
                Expanded(
                  child: _buildShortcutCard(
                    context,
                    icon: AppIcons.scan,
                    title: context.tr('tools_scan_receipt'),
                    subtitle: context.tr('quick_scan_with_ai_review'),
                    onTap: () => _open(context, const ReceiptUploadScreen()),
                  ),
                ),
                SizedBox(width: ShellStyles.scaled(context, 8, min: 6, max: 10)),
                Expanded(
                  child: _buildShortcutCard(
                    context,
                    icon: AppIcons.analyticsAlt,
                    title: context.tr('tools_analytics'),
                    subtitle: context.tr('view_insights_and_trends'),
                    onTap: () => _open(context, const AnalyticsScreen()),
                  ),
                ),
                SizedBox(width: ShellStyles.scaled(context, 8, min: 6, max: 10)),
                Expanded(
                  child: _buildShortcutCard(
                    context,
                    icon: AppIcons.receipt,
                    title: context.tr('tools_receipt_manager'),
                    subtitle: context.tr('organize_your_receipts'),
                    onTap: () => _open(context, const ReceiptManagerScreen()),
                  ),
                ),
              ],
            ),
            SizedBox(height: ShellStyles.scaled(context, 22, min: 18, max: 26)),
            ShellStyles.sectionLabel(context, context.tr('tools_all_tools')),
            SizedBox(height: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            _buildToolSection(
              context,
              title: context.tr('tools_core'),
              tiles: [
                _ToolTileData(
                  icon: AppIcons.receipt,
                  title: context.tr('tools_receipt_manager'),
                  subtitle: context.tr('tools_receipt_manager_subtitle'),
                  onTap: () => _open(context, const ReceiptManagerScreen()),
                ),
                _ToolTileData(
                  icon: AppIcons.analyticsAlt,
                  title: context.tr('tools_analytics'),
                  subtitle: context.tr('tools_analytics_subtitle'),
                  onTap: () => _open(context, const AnalyticsScreen()),
                ),
                _ToolTileData(
                  icon: AppIcons.category,
                  title: context.tr('tools_categories'),
                  subtitle: context.tr('tools_categories_subtitle'),
                  onTap: () => _open(context, const CategoriesScreen()),
                ),
                _ToolTileData(
                  icon: AppIcons.labels,
                  title: context.tr('settings_labels'),
                  subtitle: context.tr('settings_manage_labels'),
                  onTap: () => _open(context, const LabelsScreen()),
                ),
              ],
            ),
            SizedBox(height: ShellStyles.scaled(context, 16, min: 14, max: 20)),
            _buildToolSection(
              context,
              title: context.tr('tools_planning'),
              tiles: [
                _ToolTileData(
                  icon: AppIcons.budget,
                  title: context.tr('tools_budget_calculator'),
                  subtitle: context.tr('tools_budget_calculator_subtitle'),
                  onTap: () => _open(context, const BudgetCalculatorScreen()),
                ),
                _ToolTileData(
                  icon: AppIcons.notifications,
                  title: context.tr('tools_bill_reminders'),
                  subtitle: context.tr('tools_bill_reminders_subtitle'),
                  onTap: () => _open(context, const BillRemindersScreen()),
                ),
              ],
            ),
            if (launchEnableDataTransferTools) ...[
              SizedBox(
                height: ShellStyles.scaled(context, 16, min: 14, max: 20),
              ),
              _buildToolSection(
                context,
                title: context.tr('tools_data'),
                tiles: [
                  _ToolTileData(
                    icon: AppIcons.export,
                    title: context.tr('tools_export_data'),
                    subtitle: context.tr('tools_export_data_subtitle'),
                    onTap: () => DataTransferActions.exportData(context),
                  ),
                  _ToolTileData(
                    icon: AppIcons.importData,
                    title: context.tr('tools_import_data'),
                    subtitle: context.tr('tools_import_data_subtitle'),
                    onTap: () => DataTransferActions.importData(context),
                  ),
                ],
              ),
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

  Widget _buildShortcutCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(
        ShellStyles.scaled(context, 16, min: 14, max: 18),
      ),
      onTap: onTap,
      child: Container(
        height: ShellStyles.scaled(context, 120, min: 110, max: 130),
        padding: EdgeInsets.all(
          ShellStyles.scaled(context, 10, min: 9, max: 12),
        ),
        decoration: ShellStyles.cardDecoration(
          context,
          radius: ShellStyles.scaled(context, 16, min: 14, max: 18),
          color: ShellStyles.surface(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: ShellStyles.scaled(context, 36, min: 32, max: 40),
              height: ShellStyles.scaled(context, 36, min: 32, max: 40),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ShellStyles.accentTone(context).base,
                borderRadius: BorderRadius.circular(
                  ShellStyles.scaled(context, 12, min: 10, max: 13),
                ),
              ),
              child: Icon(
                icon,
                size: ShellStyles.scaled(context, 18, min: 16, max: 20),
                color: ShellStyles.accentTone(context).onSolid,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: ShellStyles.scaled(context, 12.5, min: 11, max: 13.5),
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 3, min: 2, max: 5)),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: ShellStyles.scaled(
                  context,
                  10.5,
                  min: 9.5,
                  max: 11.5,
                ),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(BuildContext context, _ToolTileData tile) {
    return InkWell(
      onTap: tile.onTap,
      borderRadius: BorderRadius.circular(
        ShellStyles.scaled(context, 18, min: 16, max: 20),
      ),
      child: Container(
        decoration: ShellStyles.cardDecoration(
          context,
          radius: ShellStyles.scaled(context, 18, min: 16, max: 20),
          color: ShellStyles.surface(context),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ShellStyles.scaled(context, 14, min: 12, max: 16),
          vertical: ShellStyles.scaled(context, 14, min: 12, max: 16),
        ),
        child: Row(
          children: [
            Container(
              width: ShellStyles.scaled(context, 38, min: 34, max: 42),
              height: ShellStyles.scaled(context, 38, min: 34, max: 42),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ShellStyles.accentTone(context).container,
                borderRadius: BorderRadius.circular(
                  ShellStyles.scaled(context, 12, min: 10, max: 14),
                ),
                border: Border.all(color: ShellStyles.accentTone(context).border),
              ),
              child: Icon(
                tile.icon,
                color: ShellStyles.accentTone(context).foreground,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
