import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class AppTabFooter extends StatelessWidget {
  const AppTabFooter({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ShellStyles.surface(context),
        border: Border(top: BorderSide(color: ShellStyles.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
          child: Row(
            children: [
              _AppTabFooterItem(
                icon: AppIcons.home,
                activeIcon: AppIcons.homeFilled,
                label: context.tr('nav_home'),
                selected: selectedIndex == 0,
                onTap: () => onSelected(0),
              ),
              _AppTabFooterItem(
                icon: AppIcons.tools,
                activeIcon: AppIcons.toolsFilled,
                label: context.tr('nav_tools'),
                selected: selectedIndex == 1,
                onTap: () => onSelected(1),
              ),
              _AppTabFooterItem(
                icon: AppIcons.settings,
                activeIcon: AppIcons.settingsFilled,
                label: context.tr('nav_settings'),
                selected: selectedIndex == 2,
                onTap: () => onSelected(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppTabFooterItem extends StatelessWidget {
  const _AppTabFooterItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = ShellStyles.textPrimary(context);
    final unselectedColor = ShellStyles.textMuted(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? activeIcon : icon,
                color: selected ? selectedColor : unselectedColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? selectedColor : unselectedColor,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
