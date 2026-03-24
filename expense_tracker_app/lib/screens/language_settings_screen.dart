import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_languages.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'settings_detail_scaffold.dart';

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  String _query = '';

  Iterable<AppLanguage> _filteredLanguages() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return appLanguages;
    return appLanguages.where((language) {
      if (language.code.contains(query)) return true;
      if (language.englishName.toLowerCase().contains(query)) return true;
      if (language.nativeName.toLowerCase().contains(query)) return true;
      for (final keyword in language.searchKeywords) {
        if (keyword.toLowerCase().contains(query)) return true;
      }
      return false;
    });
  }

  Future<void> _selectLanguage(AppLanguage language) async {
    await localeProvider.setLocale(Locale(language.code));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'settings_language_updated',
            params: {'language': language.englishName},
          ),
        ),
      ),
    );
  }

  Widget _buildRow(AppLanguage language, bool hasDivider) {
    final selected = localeProvider.locale.languageCode == language.code;
    return InkWell(
      onTap: () => _selectLanguage(language),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.englishName,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        language.nativeName,
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(AppIcons.check, color: ShellStyles.textPrimary(context), size: 18),
              ],
            ),
          ),
          if (hasDivider)
            Divider(height: 1, color: ShellStyles.border(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languages = _filteredLanguages().toList();
    return SettingsDetailScaffold(
      title: context.tr('settings_language'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSearchField(
                hintText: context.tr('settings_language_search'),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: [
                    for (var index = 0; index < languages.length; index++)
                      _buildRow(
                        languages[index],
                        index != languages.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
