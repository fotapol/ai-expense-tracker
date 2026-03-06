import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/api_client.dart';
import '../main.dart';
import 'categories_screen.dart';
import 'labels_screen.dart';
import 'login_screen.dart';

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
  bool _isUpdatingCurrency = false;

  // Local state for settings
  bool _notificationsEnabled = false;

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

  String _currentCurrencyCode() {
    return (_profileData?['default_currency'] ?? 'EUR')
        .toString()
        .toUpperCase();
  }

  String _currencySubtitle() {
    final currency = CurrencyService().findByCode(_currentCurrencyCode());
    if (currency == null) return _currentCurrencyCode();
    return '${currency.symbol} ${currency.name}';
  }

  Future<void> _updateDefaultCurrency(String code) async {
    if (_isUpdatingCurrency) return;

    setState(() => _isUpdatingCurrency = true);
    try {
      final updated = await ApiClient.updateMe({
        'default_currency': code.toUpperCase(),
      });
      if (!mounted) return;
      setState(() => _profileData = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Currency updated to ${code.toUpperCase()}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update currency: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingCurrency = false);
    }
  }

  void _openCurrencyPicker() {
    final currentCode = _currentCurrencyCode();
    showCurrencyPicker(
      context: context,
      showSearchField: true,
      showFlag: false,
      favorite: [currentCode],
      onSelect: (currency) {
        final selectedCode = currency.code.toUpperCase();
        if (selectedCode == currentCode) return;
        _updateDefaultCurrency(selectedCode);
      },
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
                  subtitle: _currencySubtitle(),
                  trailing: _isUpdatingCurrency
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _openCurrencyPicker,
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LabelsScreen()),
                    );
                  },
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
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  onTap: () => themeProvider.toggle(),
                  trailing: Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (val) => themeProvider.toggle(),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
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
