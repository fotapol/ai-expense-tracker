import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'home_tab.dart';
import 'me_screen.dart';
import 'receipt_upload_screen.dart';
import 'tools_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _tabs = [HomeTab(), ToolsScreen(), MeScreen()];

  bool get _showsScanAction => _selectedIndex == 0 || _selectedIndex == 1;

  Future<void> _openScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReceiptUploadScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      body: IndexedStack(index: _selectedIndex, children: _tabs),
      floatingActionButton: _showsScanAction
          ? FloatingActionButton(
              onPressed: _openScan,
              backgroundColor: ShellStyles.textPrimary(context),
              foregroundColor: ShellStyles.surface(context),
              shape: const CircleBorder(),
              child: const Icon(AppIcons.scanFab),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Container(
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
                _NavItem(
                  icon: AppIcons.home,
                  activeIcon: AppIcons.homeFilled,
                  label: context.tr('nav_home'),
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                _NavItem(
                  icon: AppIcons.tools,
                  activeIcon: AppIcons.toolsFilled,
                  label: context.tr('nav_tools'),
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                _NavItem(
                  icon: AppIcons.settings,
                  activeIcon: AppIcons.settingsFilled,
                  label: context.tr('nav_settings'),
                  selected: _selectedIndex == 2,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
