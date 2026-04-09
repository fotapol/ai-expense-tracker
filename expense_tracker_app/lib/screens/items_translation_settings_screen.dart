import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/item_translation_preferences.dart';
import '../core/redesign_system.dart';
import '../l10n/app_languages.dart';
import '../main.dart';
import 'settings_detail_scaffold.dart';

class ItemsTranslationSettingsScreen extends StatefulWidget {
  const ItemsTranslationSettingsScreen({super.key, required this.initialCode});

  final String initialCode;

  @override
  State<ItemsTranslationSettingsScreen> createState() =>
      _ItemsTranslationSettingsScreenState();
}

class _ItemsTranslationSettingsScreenState
    extends State<ItemsTranslationSettingsScreen> {
  late String _selectedTargetCode;
  bool _isSaving = false;
  bool _autoDetect = true;
  late String _manualSourceCode;

  @override
  void initState() {
    super.initState();
    _selectedTargetCode = widget.initialCode.toLowerCase();
    _autoDetect = itemTranslationPreferences.autoDetectSourceLanguage;
    _manualSourceCode = itemTranslationPreferences.manualSourceLanguage;
  }

  Future<void> _selectTargetLanguage(AppLanguage language) async {
    if (_isSaving || _selectedTargetCode == language.code) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updateMe(<String, dynamic>{
        'items_language': language.code,
      });
      if (!mounted) return;
      setState(() => _selectedTargetCode = language.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Item translation language set to ${language.englishName}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update translation language: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _setAutoDetect(bool value) async {
    await itemTranslationPreferences.setAutoDetectSourceLanguage(
      value,
      fallbackLanguageCode: localeProvider.locale.languageCode,
    );
    if (!mounted) return;
    setState(() {
      _autoDetect = itemTranslationPreferences.autoDetectSourceLanguage;
      _manualSourceCode = itemTranslationPreferences.manualSourceLanguage;
    });
  }

  Future<void> _selectManualSourceLanguage(AppLanguage language) async {
    await itemTranslationPreferences.setManualSourceLanguage(language.code);
    if (!mounted) return;
    setState(
      () => _manualSourceCode = itemTranslationPreferences.manualSourceLanguage,
    );
  }

  AppLanguage _languageForCode(String code) {
    final normalized = code.trim().toLowerCase();
    for (final language in appLanguages) {
      if (language.code == normalized) return language;
    }
    return appLanguages.first;
  }

  Future<AppLanguage?> _showLanguagePicker({
    required String title,
    required String currentCode,
  }) {
    return showModalBottomSheet<AppLanguage>(
      context: context,
      showDragHandle: true,
      backgroundColor: ShellStyles.surface(context),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: appLanguages.length + 1,
            separatorBuilder: (_, index) =>
                Divider(height: 1, color: ShellStyles.border(context)),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final language = appLanguages[index - 1];
              final selected = language.code == currentCode;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  language.englishName,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(language.nativeName),
                trailing: selected
                    ? Icon(
                        AppIcons.check,
                        color: ShellStyles.textPrimary(context),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(language),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'How item translation works',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Receipt item names can be translated into your chosen target language. When Auto-detect is on, the app first tries to identify the original language from the item text.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'If very similar languages are detected incorrectly, turn Auto-detect off and choose the source language manually.',
            style: const TextStyle(
              color: ShellColors.softBlue,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorField({
    required String label,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ShellStyles.border(context)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              AppIcons.chevronDown,
              color: ShellStyles.textMuted(context),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetLanguage = _languageForCode(_selectedTargetCode);
    final sourceLanguage = _languageForCode(_manualSourceCode);

    return SettingsDetailScaffold(
      title: 'Items Translation',
      body: SafeArea(
        top: false,
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  ShellStyles.sectionLabel(context, 'Target language'),
                  const SizedBox(height: 8),
                  _buildSelectorField(
                    label: 'Translate items into',
                    title: targetLanguage.englishName,
                    subtitle:
                        '${targetLanguage.nativeName} - Translated item names will appear in this language.',
                    onTap: () async {
                      final picked = await _showLanguagePicker(
                        title: 'Translate items to',
                        currentCode: _selectedTargetCode,
                      );
                      if (picked != null) {
                        await _selectTargetLanguage(picked);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  ShellStyles.sectionLabel(context, 'Source language'),
                  const SizedBox(height: 8),
                  SettingsDetailCard(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: Column(
                      children: <Widget>[
                        SettingsToggleRow(
                          title: 'Auto-detect source language',
                          subtitle:
                              'Use the item text to guess the original language before translation.',
                          value: _autoDetect,
                          onChanged: _setAutoDetect,
                        ),
                        Divider(height: 1, color: ShellStyles.border(context)),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: _autoDetect
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: ShellStyles.surfaceAlt(context),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: ShellStyles.border(context),
                                    ),
                                  ),
                                  child: Text(
                                    'The app will detect the original language from each receipt item before translating it.',
                                    style: TextStyle(
                                      color: ShellStyles.textMuted(context),
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                )
                              : _buildSelectorField(
                                  label: 'Use this source language',
                                  title: sourceLanguage.englishName,
                                  subtitle:
                                      '${sourceLanguage.nativeName} - The app will use this as the original language before translation.',
                                  onTap: () async {
                                    final picked = await _showLanguagePicker(
                                      title: 'Choose source language',
                                      currentCode: _manualSourceCode,
                                    );
                                    if (picked != null) {
                                      await _selectManualSourceLanguage(picked);
                                    }
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isSaving)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}
