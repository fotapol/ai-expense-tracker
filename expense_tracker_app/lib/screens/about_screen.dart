import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_env.dart';
import '../core/app_release_notes.dart';
import '../core/redesign_system.dart';
import 'settings_detail_scaffold.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;
  String? _metadataError;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _packageInfo = packageInfo;
        _metadataError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _metadataError = 'Version details are unavailable on this device.';
      });
    }
  }

  String get _versionLabel {
    final packageInfo = _packageInfo;
    if (packageInfo == null) return 'Loading version...';
    return 'Version ${packageInfo.version}';
  }

  Future<void> _openUrl(String rawUrl) async {
    final uri = AppEnv.uriFrom(rawUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppEnv.supportEmail,
      queryParameters: <String, String>{'subject': AppEnv.supportSubject},
    );
    final opened = await launchUrl(uri);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open ${AppEnv.supportEmail}.')),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: ShellStyles.heroCardDecoration(context, radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ShellStyles.heroBadgeSurface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ShellStyles.heroBadgeBorder(context)),
            ),
            child: Icon(
              AppIcons.info,
              color: ShellStyles.heroBadgeIcon(context),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AI Expense Tracker',
            style: TextStyle(
              color: ShellStyles.heroTextPrimary(context),
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _versionLabel,
            style: TextStyle(
              color: ShellStyles.heroTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_metadataError != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _metadataError!,
              style: TextStyle(
                color: ShellStyles.heroTextSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWhatIsNewCard(AppReleaseNotes releaseNotes) {
    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${releaseNotes.version} - ${releaseNotes.title}',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...releaseNotes.highlights.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      AppIcons.checkCircle,
                      color: ShellColors.softGreen,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLinkRow({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevronRight,
              color: ShellStyles.textMuted(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = _packageInfo;
    final releaseNotes = releaseNotesForVersion(packageInfo?.version ?? '');

    return SettingsDetailScaffold(
      title: 'About',
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildHero(),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, "What's new"),
              const SizedBox(height: 8),
              _buildWhatIsNewCard(releaseNotes),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'About the app'),
              const SizedBox(height: 8),
              SettingsDetailCard(
                child: Text(
                  appAboutIdentityCopy,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'Links'),
              const SizedBox(height: 8),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: <Widget>[
                    _buildLinkRow(
                      title: 'Website',
                      subtitle: AppEnv.websiteUrl,
                      onTap: () => _openUrl(AppEnv.websiteUrl),
                    ),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(
                      title: 'Privacy policy',
                      subtitle: AppEnv.privacyUrl,
                      onTap: () => _openUrl(AppEnv.privacyUrl),
                    ),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(
                      title: 'Terms of service',
                      subtitle: AppEnv.termsUrl,
                      onTap: () => _openUrl(AppEnv.termsUrl),
                    ),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(
                      title: 'Email support',
                      subtitle: AppEnv.supportEmail,
                      onTap: _openSupportEmail,
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
