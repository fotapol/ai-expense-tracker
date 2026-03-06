import 'package:currency_picker/currency_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_languages.dart';
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

  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('settings_feature_coming_soon'))),
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

  String _languageNameForCode(String code) {
    final normalized = code.toLowerCase();
    for (final language in appLanguages) {
      if (language.code == normalized) {
        return language.nativeName;
      }
    }
    return code.toUpperCase();
  }

  String _currentLanguageSubtitle() {
    return _languageNameForCode(localeProvider.locale.languageCode);
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
        SnackBar(
          content: Text(
            context.tr(
              'settings_currency_updated',
              params: {'code': code.toUpperCase()},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'settings_currency_update_failed',
              params: {'error': e.toString()},
            ),
          ),
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

  Future<void> _updateLanguage(String code) async {
    await localeProvider.setLocale(Locale(code));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'settings_language_updated',
            params: {'language': _languageNameForCode(code)},
          ),
        ),
      ),
    );
  }

  void _openLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final currentCode = localeProvider.locale.languageCode;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = appLanguages.where((language) {
              if (normalizedQuery.isEmpty) return true;
              if (language.nativeName.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              if (language.code.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              for (final keyword in language.searchKeywords) {
                if (keyword.toLowerCase().contains(normalizedQuery)) {
                  return true;
                }
              }
              return false;
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr('language_picker_title'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => setModalState(() => query = value),
                      decoration: InputDecoration(
                        hintText: context.tr('language_picker_search'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final language = filtered[index];
                          final code = language.code;
                          final selected = code == currentCode;
                          return ListTile(
                            title: Text(language.nativeName),
                            trailing: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade500,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _updateLanguage(code);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
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
        _error = context.tr(
          'settings_failed_load_profile',
          params: {'error': e.toString()},
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('settings_title'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
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
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchProfile();
              },
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      );
    }

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
                  title: context.tr('settings_currency'),
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
                  title: context.tr('settings_language'),
                  subtitle: _currentLanguageSubtitle(),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _openLanguagePicker,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.g_translate,
                  title: context.tr('settings_items_language'),
                  subtitle: _languageNameForCode('ru'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _showComingSoon,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.list,
                  title: context.tr('settings_categories_subcategories'),
                  subtitle: context.tr(
                    'settings_manage_categories_subcategories',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategoriesScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.label_outline,
                  title: context.tr('settings_labels'),
                  subtitle: context.tr('settings_manage_labels'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LabelsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.notifications_off_outlined,
                  title: context.tr('settings_notifications'),
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
                  title: context.tr('settings_dark_mode'),
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
                  Text(
                    context.tr('settings_signed_in_as'),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profileData!['email'] ??
                        context.tr('settings_unknown_email'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      context.tr('settings_sign_out'),
                      style: const TextStyle(color: Colors.redAccent),
                    ),
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
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 28,
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            )
          : null,
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
