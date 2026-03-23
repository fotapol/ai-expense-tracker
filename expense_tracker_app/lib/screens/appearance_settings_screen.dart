import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'settings_detail_scaffold.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

enum _ThemeChoice { light, dark, auto }

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  static const List<_AccentOption> _accentOptions = [
    _AccentOption('neutral', Color(0xFF1C1A19)),
    _AccentOption('blue', Color(0xFF4F7FF7)),
    _AccentOption('violet', Color(0xFFA04DF0)),
    _AccentOption('green', Color(0xFF2FBD85)),
    _AccentOption('amber', Color(0xFFF5A313)),
    _AccentOption('red', Color(0xFFEF4747)),
  ];

  late _ThemeChoice _themeChoice;
  late String _fontSize;
  String _selectedAccent = 'neutral';
  bool _compactMode = false;
  bool _animationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _fontSize = themeProvider.fontSizeId;
    if (themeProvider.themeMode == ThemeMode.system) {
      _themeChoice = _ThemeChoice.auto;
    } else if (themeProvider.themeMode == ThemeMode.dark) {
      _themeChoice = _ThemeChoice.dark;
    } else {
      _themeChoice = _ThemeChoice.light;
    }
  }

  Future<void> _selectTheme(_ThemeChoice choice) async {
    setState(() => _themeChoice = choice);
    switch (choice) {
      case _ThemeChoice.light:
        await themeProvider.setThemeMode(ThemeMode.light);
        break;
      case _ThemeChoice.dark:
        await themeProvider.setThemeMode(ThemeMode.dark);
        break;
      case _ThemeChoice.auto:
        await themeProvider.setThemeMode(ThemeMode.system);
        break;
    }
  }

  Widget _buildThemeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required _ThemeChoice value,
  }) {
    return SettingsChoiceRow(
      title: title,
      subtitle: subtitle,
      leading: Container(
        width: 34,
        height: 34,
        decoration: ShellStyles.iconBadgeDecoration(context, radius: 11),
        alignment: Alignment.center,
        child: Icon(icon, color: ShellStyles.textPrimary(context), size: 18),
      ),
      selected: _themeChoice == value,
      selectedBorder: _themeChoice == value,
      onTap: () => _selectTheme(value),
    );
  }

  Widget _buildFontRow({
    required String id,
    required String title,
    required String subtitle,
    required bool hasDivider,
  }) {
    final selected = _fontSize == id;
    return InkWell(
      onTap: () async {
        setState(() => _fontSize = id);
        await themeProvider.setFontSize(id);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(text: title),
                        TextSpan(
                          text: '  $subtitle',
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (selected)
                  Icon(AppIcons.check, color: ShellStyles.textPrimary(context)),
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
    return SettingsDetailScaffold(
      title: context.tr('settings_appearance'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShellStyles.sectionLabel(context, context.tr('settings_theme')),
              const SizedBox(height: 8),
              _buildThemeOption(
                icon: AppIcons.sun,
                title: context.tr('settings_theme_light'),
                subtitle: context.tr('settings_theme_light_subtitle'),
                value: _ThemeChoice.light,
              ),
              const SizedBox(height: 8),
              _buildThemeOption(
                icon: AppIcons.moon,
                title: context.tr('settings_theme_dark'),
                subtitle: context.tr('settings_theme_dark_subtitle'),
                value: _ThemeChoice.dark,
              ),
              const SizedBox(height: 8),
              _buildThemeOption(
                icon: AppIcons.auto,
                title: context.tr('settings_theme_auto'),
                subtitle: context.tr('settings_theme_auto_subtitle'),
                value: _ThemeChoice.auto,
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(
                context,
                context.tr('settings_accent_color'),
              ),
              const SizedBox(height: 8),
              SettingsDetailCard(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                radius: 22,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 20,
                  children: _accentOptions.map((option) {
                    final selected = _selectedAccent == option.id;
                    return InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => setState(() => _selectedAccent = option.id),
                      child: SizedBox(
                        width: 90,
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: option.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? ShellStyles.surface(context)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: option.color.withAlpha(55),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: selected
                                  ? Icon(
                                      AppIcons.check,
                                      color: Colors.white,
                                      size: 24,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.tr('settings_accent_${option.id}'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ShellStyles.textPrimary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(
                context,
                context.tr('settings_font_size'),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: [
                    _buildFontRow(
                      id: 'small',
                      title: context.tr('settings_font_small'),
                      subtitle: '14px',
                      hasDivider: true,
                    ),
                    _buildFontRow(
                      id: 'medium',
                      title: context.tr('settings_font_medium'),
                      subtitle: '16px',
                      hasDivider: true,
                    ),
                    _buildFontRow(
                      id: 'large',
                      title: context.tr('settings_font_large'),
                      subtitle: '18px',
                      hasDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(
                context,
                context.tr('settings_display_options'),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: [
                    SettingsToggleRow(
                      title: context.tr('settings_compact_mode'),
                      subtitle: context.tr('settings_compact_mode_subtitle'),
                      value: _compactMode,
                      onChanged: (value) =>
                          setState(() => _compactMode = value),
                    ),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                    ),
                    SettingsToggleRow(
                      title: context.tr('settings_animations'),
                      subtitle: context.tr('settings_animations_subtitle'),
                      value: _animationsEnabled,
                      onChanged: (value) =>
                          setState(() => _animationsEnabled = value),
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

class _AccentOption {
  const _AccentOption(this.id, this.color);

  final String id;
  final Color color;
}
