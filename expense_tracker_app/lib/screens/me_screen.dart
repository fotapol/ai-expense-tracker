import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/api_client.dart';
import 'categories_screen.dart';
import 'login_screen.dart';
import 'receipt_upload_screen.dart';

/// Screen that displays the authenticated user's profile from the backend.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  String? _error;

  // Local state for fake settings
  bool _notificationsEnabled = false;
  bool _darkModeEnabled = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This feature is coming soon!')),
    );
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await ApiClient.getMe();
      setState(() {
        _profileData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchProfile();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Build the beautiful settings menu modeled after the provided image
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSettingsTile(
                  icon: Icons.attach_money,
                  title: 'Currency',
                  subtitle: 'дин. Serbian Dinar',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showComingSoon,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.translate,
                  title: 'Language',
                  subtitle: 'English',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showComingSoon,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.g_translate,
                  title: 'Items translation language',
                  subtitle: 'Русский',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showComingSoon,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.list,
                  title: 'Categories & Subcategories',
                  subtitle: 'Manage categories & subcategories',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CategoriesScreen()),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.label_outline,
                  title: 'Labels',
                  subtitle: 'Manage Labels',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showComingSoon,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.notifications_off_outlined,
                  title: 'Notifications',
                  onTap: () {
                    setState(() {
                      _notificationsEnabled = !_notificationsEnabled;
                    });
                  },
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: (val) {
                      setState(() {
                        _notificationsEnabled = val;
                      });
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  onTap: () {
                    setState(() {
                      _darkModeEnabled = !_darkModeEnabled;
                    });
                  },
                  trailing: Switch(
                    value: _darkModeEnabled,
                    onChanged: (val) {
                      setState(() {
                        _darkModeEnabled = val;
                      });
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // User Info & Sign Out
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_profileData != null) ...[
                  Text('Signed in as', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_profileData!['email'] ?? 'Unknown Email', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)) : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 16),
      child: Divider(color: Colors.grey.shade800, height: 1),
    );
  }
}
