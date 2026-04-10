import 'package:flutter/material.dart';

import '../core/app_navigation.dart';
import '../core/redesign_system.dart';
import '../widgets/app_tab_footer.dart';
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
  late int _selectedIndex;

  static const List<Widget> _tabs = [HomeTab(), ToolsScreen(), MeScreen()];

  bool get _showsScanAction => _selectedIndex <= 1;

  @override
  void initState() {
    super.initState();
    _selectedIndex = appShellTabIndex.value;
    appShellTabIndex.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    appShellTabIndex.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted || _selectedIndex == appShellTabIndex.value) return;
    setState(() {
      _selectedIndex = appShellTabIndex.value;
    });
  }

  void _selectTab(int index) {
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
    selectRootTab(index);
  }

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
          ? ClipOval(
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: Material(
                color: ShellStyles.accent(context),
                child: InkWell(
                  onTap: _openScan,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(
                      AppIcons.scanFab,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: AppTabFooter(
        selectedIndex: _selectedIndex,
        onSelected: _selectTab,
      ),
    );
  }
}
