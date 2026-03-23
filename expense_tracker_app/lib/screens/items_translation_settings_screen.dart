import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../l10n/app_languages.dart';
import '../l10n/app_localizations.dart';
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
  late String _selectedCode;
  bool _isSaving = false;
  bool _translationEnabled = true;
  bool _autoDetect = true;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.initialCode.toLowerCase();
  }

  Future<void> _selectLanguage(AppLanguage language) async {
    if (_isSaving || _selectedCode == language.code) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updateMe({'items_language': language.code});
      if (!mounted) return;
      setState(() => _selectedCode = language.code);
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildLanguageRow(AppLanguage language, bool hasDivider) {
    final selected = _selectedCode == language.code;
    return InkWell(
      onTap: () => _selectLanguage(language),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.englishName,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Icon(AppIcons.check, color: ShellStyles.textPrimary(context)),
              ],
            ),
          ),
          if (hasDivider) Divider(height: 1, color: ShellStyles.border(context)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_items_translation_title'),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F6FF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFB6CCFF)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDE8FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            AppIcons.feature,
                            color: Color(0xFF5E7DFF),
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    context.tr('settings_beta_feature'),
                                    style: const TextStyle(
                                      color: Color(0xFF3054D8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDDE8FF),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'BETA',
                                      style: TextStyle(
                                        color: Color(0xFF3054D8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.tr(
                                  'settings_items_translation_beta_hint',
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF3054D8),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: ShellStyles.cardDecoration(context, radius: 18),
                    child: SettingsToggleRow(
                      title: context.tr('settings_enable_translation'),
                      subtitle: context.tr(
                        'settings_enable_translation_subtitle',
                      ),
                      value: _translationEnabled,
                      onChanged: (value) =>
                          setState(() => _translationEnabled = value),
                    ),
                  ),
                  // Collapse language list and options when translation is disabled
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                    child: _translationEnabled
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              ShellStyles.sectionLabel(
                                context,
                                context.tr('settings_translate_to'),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: ShellStyles.cardDecoration(context, radius: 18),
                                child: Column(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < appLanguages.length;
                                      index++
                                    )
                                      _buildLanguageRow(
                                        appLanguages[index],
                                        index != appLanguages.length - 1,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ShellStyles.sectionLabel(
                                context,
                                context.tr('settings_options'),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: ShellStyles.cardDecoration(context, radius: 18),
                                child: SettingsToggleRow(
                                  title: context.tr('settings_auto_detect_source_language'),
                                  subtitle: context.tr(
                                    'settings_auto_detect_source_language_subtitle',
                                  ),
                                  value: _autoDetect,
                                  onChanged: (value) => setState(() => _autoDetect = value),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 16),
                  ShellStyles.sectionLabel(
                    context,
                    context.tr('settings_example'),
                  ),
                  const SizedBox(height: 8),
                  SettingsDetailCard(
                    child: Column(
                      children: [
                        _ExampleRow(
                          label: context.tr('settings_original_text'),
                          value: 'Cafe au lait',
                        ),
                        const SizedBox(height: 8),
                        _ExampleRow(
                          label: context.tr('settings_translated_text'),
                          value: 'Coffee with milk',
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

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
