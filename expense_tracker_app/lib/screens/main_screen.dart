import 'package:flutter/material.dart';
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

  // We lazily load the screens to avoid initializing them all at once.
  static final List<Widget> _widgetOptions = <Widget>[
    const HomeTab(),
    const ReceiptsTab(),
    const Center(child: Text('Placeholder for Scan')), // Replaced by floating action button intercept
    const AnalyticsTab(),
    const MeScreen(), // The previous Profile/Me screen
  ];

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
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Dark grey matching body
        selectedItemColor: Theme.of(context).colorScheme.primary, // Teal
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Receipts',
          ),
          BottomNavigationBarItem(
            // Special icon matching the design's center scan button
            icon: Icon(Icons.document_scanner_outlined, size: 36),
            label: 'Scan Receipt',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
