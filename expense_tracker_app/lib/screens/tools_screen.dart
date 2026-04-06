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
    final bottomPadding = MediaQuery.of(context).padding.bottom + 28;
    final density = ShellStyles.densityScale(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          ShellStyles.scaled(context, 16, min: 14),
          ShellStyles.scaled(context, 18, min: 14),
          ShellStyles.scaled(context, 16, min: 14),
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
                fontSize: ShellStyles.scaled(context, 13, min: 12, max: 14),
                height: 1.35,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 18, min: 14, max: 22)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(
                ShellStyles.scaled(context, 18, min: 15, max: 22),
              ),
              decoration: ShellStyles.cardDecoration(
                context,
                radius: ShellStyles.scaled(context, 24, min: 20, max: 26),
                color: ShellStyles.surfaceAlt(context),
                withShadow: false,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: ShellStyles.scaled(context, 48, min: 44, max: 52),
                    height: ShellStyles.scaled(context, 48, min: 44, max: 52),
                    alignment: Alignment.center,
                    decoration: ShellStyles.iconBadgeDecoration(
                      context,
                      color: ShellStyles.surface(context),
                      radius: ShellStyles.scaled(context, 16, min: 14, max: 18),
                    ),
                    child: Icon(
                      AppIcons.toolsFilled,
                      color: ShellStyles.textPrimary(context),
                      size: ShellStyles.scaled(context, 22, min: 19, max: 24),
                    ),
                  ),
                  SizedBox(width: ShellStyles.scaled(context, 14, min: 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('tools_all_tools'),
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: ShellStyles.scaled(
                              context,
                              18,
                              min: 16,
                              max: 20,
                            ),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(
                          height: ShellStyles.scaled(
                            context,
                            6,
                            min: 4,
                            max: 8,
                          ),
                        ),
                        Text(
                          'Keep scanning, reviewing, organizing, and planning from one place.',
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: ShellStyles.scaled(
                              context,
                              13,
                              min: 12,
                              max: 14,
                            ),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 20, min: 16, max: 24)),
            Row(
              children: [
                Icon(
                  CupertinoIcons.pin_fill,
                  size: ShellStyles.scaled(context, 13, min: 12, max: 14),
                  color: ShellStyles.textMuted(context),
                ),
                const SizedBox(width: 6),
                ShellStyles.sectionLabel(
                  context,
                  context.tr('tools_most_used'),
                ),
                const Spacer(),
                Text(
                  density < 0.95 ? 'Compact layout active' : 'Pinned shortcuts',
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: ShellStyles.scaled(context, 11, min: 10, max: 12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: ShellStyles.scaled(context, 12, min: 10, max: 14)),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = ShellStyles.scaled(context, 8, min: 6, max: 10);
                final cardWidth = (constraints.maxWidth - (spacing * 2)) / 3;
                return Row(
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildShortcutCard(
                        context,
                        icon: AppIcons.scan,
                        title: context.tr('tools_scan_receipt'),
                        subtitle: 'Capture and review',
                        onTap: () =>
                            _open(context, const ReceiptUploadScreen()),
                        emphasized: true,
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: cardWidth,
                      child: _buildShortcutCard(
                        context,
                        icon: AppIcons.analyticsAlt,
                        title: context.tr('tools_analytics'),
                        subtitle: 'Track trends',
                        onTap: () => _open(context, const AnalyticsScreen()),
                      ),
                    ),
                    SizedBox(width: spacing),
                    SizedBox(
                      width: cardWidth,
                      child: _buildShortcutCard(
                        context,
                        icon: AppIcons.receipt,
                        title: context.tr('tools_receipt_manager'),
                        subtitle: 'Search history',
                        onTap: () =>
                            _open(context, const ReceiptManagerScreen()),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: ShellStyles.scaled(context, 20, min: 16, max: 24)),
            _buildToolSection(
              context,
              title: context.tr('tools_core'),
              subtitle: 'Receipt flow and organization tools.',
              icon: AppIcons.receipt,
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
            SizedBox(height: ShellStyles.scaled(context, 18, min: 14, max: 22)),
            _buildToolSection(
              context,
              title: context.tr('tools_planning'),
              subtitle: 'Keep budgets and upcoming bills in one routine.',
              icon: AppIcons.notifications,
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
                height: ShellStyles.scaled(context, 18, min: 14, max: 22),
              ),
              _buildToolSection(
                context,
                title: context.tr('tools_data'),
                subtitle: 'Bring data in or export a copy when needed.',
                icon: AppIcons.export,
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
    required String subtitle,
    required IconData icon,
    required List<_ToolTileData> tiles,
  }) {
    return Container(
      decoration: ShellStyles.cardDecoration(
        context,
        radius: ShellStyles.scaled(context, 24, min: 20, max: 26),
        color: ShellStyles.surface(context),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          ShellStyles.scaled(context, 16, min: 14, max: 20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: ShellStyles.scaled(context, 40, min: 36, max: 44),
                  height: ShellStyles.scaled(context, 40, min: 36, max: 44),
                  alignment: Alignment.center,
                  decoration: ShellStyles.iconBadgeDecoration(
                    context,
                    color: ShellStyles.surfaceAlt(context),
                    radius: ShellStyles.scaled(context, 14, min: 12, max: 16),
                  ),
                  child: Icon(
                    icon,
                    size: ShellStyles.scaled(context, 19, min: 17, max: 21),
                    color: ShellStyles.textPrimary(context),
                  ),
                ),
                SizedBox(width: ShellStyles.scaled(context, 12, min: 10)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: ShellStyles.scaled(
                            context,
                            17,
                            min: 15,
                            max: 19,
                          ),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(
                        height: ShellStyles.scaled(context, 4, min: 3, max: 6),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: ShellStyles.scaled(
                            context,
                            12.5,
                            min: 11.5,
                            max: 13.5,
                          ),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: ShellStyles.scaled(context, 14, min: 12, max: 18)),
            for (var index = 0; index < tiles.length; index++) ...[
              _buildListTile(context, tiles[index]),
              if (index != tiles.length - 1)
                Divider(
                  height: ShellStyles.scaled(context, 18, min: 14, max: 20),
                  color: ShellStyles.border(context),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    final iconContainerColor = emphasized
        ? ShellStyles.textPrimary(context)
        : ShellStyles.surfaceAlt(context);
    final iconColor = emphasized
        ? ShellStyles.surface(context)
        : ShellStyles.textPrimary(context);
    final cardHeight = ShellStyles.scaled(context, 132, min: 116, max: 148);

    return InkWell(
      borderRadius: BorderRadius.circular(
        ShellStyles.scaled(context, 18, min: 16, max: 20),
      ),
      onTap: onTap,
      child: Container(
        height: cardHeight,
        padding: EdgeInsets.all(
          ShellStyles.scaled(context, 12, min: 10, max: 14),
        ),
        decoration: ShellStyles.cardDecoration(
          context,
          radius: ShellStyles.scaled(context, 18, min: 16, max: 20),
          color: emphasized
              ? ShellStyles.surface(context)
              : ShellStyles.surfaceAlt(context),
          withShadow: !emphasized,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: ShellStyles.scaled(context, 40, min: 34, max: 44),
              height: ShellStyles.scaled(context, 40, min: 34, max: 44),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconContainerColor,
                borderRadius: BorderRadius.circular(
                  ShellStyles.scaled(context, 13, min: 11, max: 15),
                ),
              ),
              child: Icon(
                icon,
                size: ShellStyles.scaled(context, 20, min: 17, max: 22),
                color: iconColor,
              ),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: ShellStyles.scaled(context, 13, min: 11.5, max: 14),
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: ShellStyles.scaled(context, 4, min: 3, max: 6)),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: ShellStyles.scaled(context, 11, min: 10, max: 12),
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
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ShellStyles.scaled(context, 2, min: 0, max: 4),
          vertical: ShellStyles.scaled(context, 8, min: 6, max: 10),
        ),
        child: Row(
          children: [
            Container(
              width: ShellStyles.scaled(context, 42, min: 38, max: 46),
              height: ShellStyles.scaled(context, 42, min: 38, max: 46),
              alignment: Alignment.center,
              decoration: ShellStyles.iconBadgeDecoration(
                context,
                color: ShellStyles.surfaceAlt(context),
                radius: ShellStyles.scaled(context, 14, min: 12, max: 16),
              ),
              child: Icon(
                tile.icon,
                color: ShellStyles.textPrimary(context),
                size: ShellStyles.scaled(context, 19, min: 17, max: 21),
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
                        15,
                        min: 13.5,
                        max: 16,
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
                        12,
                        min: 11,
                        max: 13,
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
