import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/data_transfer_actions.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'analytics_screen.dart';
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
    final bottomPadding = MediaQuery.of(context).padding.bottom + 140;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('nav_tools'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('tools_subtitle'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(CupertinoIcons.pin, size: 14, color: ShellStyles.textMuted(context)),
                const SizedBox(width: 6),
                ShellStyles.sectionLabel(context, context.tr('tools_most_used')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFeatureCard(
                    context,
                    icon: AppIcons.scan,
                    title: context.tr('tools_scan_receipt'),
                    subtitle: context.tr('tools_scan_receipt_subtitle'),
                    onTap: () => _open(context, const ReceiptUploadScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFeatureCard(
                    context,
                    icon: AppIcons.analyticsAlt,
                    title: context.tr('tools_analytics'),
                    subtitle: context.tr('tools_analytics_subtitle'),
                    onTap: () => _open(context, const AnalyticsScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFeatureCard(
                    context,
                    icon: AppIcons.receipt,
                    title: context.tr('tools_receipt_manager'),
                    subtitle: context.tr('tools_receipt_manager_subtitle'),
                    onTap: () => _open(context, const ReceiptManagerScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ShellStyles.sectionLabel(context, context.tr('tools_all_tools')),
            const SizedBox(height: 16),
            _buildSection(
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
            const SizedBox(height: 18),
            _buildSection(
              context,
              title: context.tr('tools_planning'),
              tiles: [
                _ToolTileData(
                  icon: AppIcons.budget,
                  title: context.tr('tools_budget_calculator'),
                  subtitle: context.tr('tools_budget_calculator_subtitle'),
                  onTap: () => ShellStyles.showComingSoon(context),
                  isPlaceholder: true,
                ),
                _ToolTileData(
                  icon: AppIcons.notifications,
                  title: context.tr('tools_bill_reminders'),
                  subtitle: context.tr('tools_bill_reminders_subtitle'),
                  onTap: () => ShellStyles.showComingSoon(context),
                  isPlaceholder: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildSection(
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
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<_ToolTileData> tiles,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < tiles.length; index++) ...[
          _buildListTile(context, tiles[index]),
          if (index != tiles.length - 1)
            const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 145,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: ShellStyles.cardDecoration(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ShellStyles.textPrimary(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: ShellStyles.surface(context),
                size: 24,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 10.5,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(BuildContext context, _ToolTileData tile) {
    final iconBackground = ShellStyles.textPrimary(
      context,
    ).withAlpha(tile.isPlaceholder ? 188 : 215);

    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 18, withShadow: false),
      child: InkWell(
        onTap: tile.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  tile.icon,
                  color: ShellStyles.surface(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tile.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                color: ShellStyles.textMuted(context),
                size: 16,
              ),
            ],
          ),
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
    this.isPlaceholder = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPlaceholder;
}
