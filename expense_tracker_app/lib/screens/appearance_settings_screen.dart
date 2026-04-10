import 'package:flutter/material.dart';

import '../core/app_color_semantics.dart';
import '../core/redesign_system.dart';
import '../core/theme_provider.dart';
import '../main.dart';
import 'settings_detail_scaffold.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  static const List<_ScaleOption> _scaleOptions = <_ScaleOption>[
    _ScaleOption(id: '60', label: '60%', subtitle: 'Extra compact text'),
    _ScaleOption(id: '80', label: '80%', subtitle: 'Smaller interface'),
    _ScaleOption(id: '100', label: '100%', subtitle: 'Default'),
    _ScaleOption(id: '120', label: '120%', subtitle: 'Larger interface'),
  ];

  Future<void> _selectThemeMode(ThemeMode mode) async {
    await themeProvider.setThemeMode(mode);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectAccent(String accentId) async {
    await themeProvider.setAccent(accentId);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectScale(String? id) async {
    if (id == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await themeProvider.setFontSize(id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectLabelColorMode(AppLabelColorMode mode) async {
    await themeProvider.setLabelColorMode(mode);
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildThemeModeSection() {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Theme',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a fixed theme or let the app follow your device appearance.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _ThemeModeChoice(
            icon: AppIcons.sun,
            title: 'Light',
            subtitle: 'Always use the light interface.',
            selected: themeProvider.themeMode == ThemeMode.light,
            onTap: () => _selectThemeMode(ThemeMode.light),
          ),
          const SizedBox(height: 8),
          _ThemeModeChoice(
            icon: AppIcons.moon,
            title: 'Dark',
            subtitle: 'Always use the dark interface.',
            selected: themeProvider.themeMode == ThemeMode.dark,
            onTap: () => _selectThemeMode(ThemeMode.dark),
          ),
          const SizedBox(height: 8),
          _ThemeModeChoice(
            icon: AppIcons.auto,
            title: 'Auto',
            subtitle: 'Follow your device theme setting.',
            selected: themeProvider.themeMode == ThemeMode.system,
            onTap: () => _selectThemeMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentSection() {
    final accentThemes = themeProvider.availableAccents;

    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Accent color',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mix is the default multi-accent mode. Neutral keeps charts and semantic surfaces monochrome. Purple remaps accents and semantic colors into a restrained purple family.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var index = 0; index < accentThemes.length; index++) ...[
                Expanded(child: _buildAccentOption(accentThemes[index])),
                if (index != accentThemes.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLabelColorModeSection() {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Label colors',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Raw colors use each label’s saved color. Accent-aware colors keep labels stable, but remap them into the active Mix, Neutral, or Purple system.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SettingsChoiceRow(
            title: 'Raw colors',
            subtitle: 'Default. Preserve each label’s saved color across the app.',
            selected: themeProvider.labelColorMode == AppLabelColorMode.raw,
            selectedBorder:
                themeProvider.labelColorMode == AppLabelColorMode.raw,
            onTap: () => _selectLabelColorMode(AppLabelColorMode.raw),
          ),
          const SizedBox(height: 8),
          SettingsChoiceRow(
            title: 'Accent-aware colors',
            subtitle: 'Map labels into the active theme while keeping each label stable.',
            selected: themeProvider.labelColorMode == AppLabelColorMode.themed,
            selectedBorder:
                themeProvider.labelColorMode == AppLabelColorMode.themed,
            onTap: () => _selectLabelColorMode(AppLabelColorMode.themed),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentOption(AppAccentTheme accent) {
    final selected = accent.id == themeProvider.accentId;
    final previewAccent = accent.primaryFor(Theme.of(context).brightness);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _selectAccent(accent.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        decoration: BoxDecoration(
          color: selected
              ? ShellStyles.surfaceAlt(context)
              : ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? previewAccent
                : ShellStyles.border(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: accent.previewGradient,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? (ShellStyles.isDark(context)
                            ? ShellStyles.textPrimary(context)
                            : Colors.white.withAlpha(220))
                      : (ShellStyles.isDark(context)
                            ? ShellStyles.border(context)
                            : Colors.white.withAlpha(120)),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: previewAccent.withAlpha(45),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: selected
                  ? Icon(AppIcons.check, color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              accent.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterfaceScaleSection() {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Interface scale',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scale text and the main controls across the app. Layout density still uses the current screen designs.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: themeProvider.fontSizeId,
            decoration: const InputDecoration(
              labelText: 'Scale',
              isDense: true,
            ),
            items: _scaleOptions.map((option) {
              return DropdownMenuItem<String>(
                value: option.id,
                child: Text('${option.label} - ${option.subtitle}'),
              );
            }).toList(),
            onChanged: _selectScale,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Preview',
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monthly total and key controls will scale with this setting.',
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _scaleSubtitleFor(themeProvider.fontSizeId),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scaleSubtitleFor(String id) {
    for (final option in _scaleOptions) {
      if (option.id == id) {
        return '${option.label} is active right now.';
      }
    }
    return '100% is active right now.';
  }

  @override
  Widget build(BuildContext context) {
    // TODO(theme): add Compact Mode when it changes real density and spacing.
    // TODO(theme): add Animations toggle when there is a user-facing motion
    // preference wired across the app.
    return SettingsDetailScaffold(
      title: 'Appearance',
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildThemeModeSection(),
              const SizedBox(height: 16),
              _buildAccentSection(),
              const SizedBox(height: 16),
              _buildLabelColorModeSection(),
              const SizedBox(height: 16),
              _buildInterfaceScaleSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeModeChoice extends StatelessWidget {
  const _ThemeModeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accentTone = ShellStyles.accentTone(context);
    return SettingsChoiceRow(
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accentTone.container
              : ShellStyles.surfaceAlt(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accentTone.border
                : ShellStyles.border(context),
          ),
        ),
        child: Icon(
          icon,
          color: selected
              ? accentTone.foreground
              : ShellStyles.textPrimary(context),
          size: 18,
        ),
      ),
      title: title,
      subtitle: subtitle,
      selected: selected,
      selectedBorder: selected,
      onTap: onTap,
    );
  }
}

class _ScaleOption {
  const _ScaleOption({
    required this.id,
    required this.label,
    required this.subtitle,
  });

  final String id;
  final String label;
  final String subtitle;
}
