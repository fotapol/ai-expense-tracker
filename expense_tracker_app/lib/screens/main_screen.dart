import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'home_tab.dart';
import 'me_screen.dart';
import 'receipt_upload_screen.dart';
import 'receipts_tab.dart';
import 'analytics_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    if (index == 2) {
      // Intercept the "Scan" button center tap and push to upload screen directly
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReceiptUploadScreen()),
      );
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final widgetOptions = <Widget>[
      const HomeTab(),
      const ReceiptsTab(),
      const SizedBox.shrink(),
      const AnalyticsTab(),
      const MeScreen(),
    ];

    return Scaffold(
      body: widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: context.tr('nav_home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long),
            label: context.tr('nav_receipts'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.document_scanner_outlined, size: 36),
            label: context.tr('nav_scan_receipt'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bar_chart),
            label: context.tr('nav_analytics'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: context.tr('nav_profile'),
          ),
        ],
      ),
    );
  }
}
