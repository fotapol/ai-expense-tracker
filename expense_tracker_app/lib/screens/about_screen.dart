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
    return 'Version ${packageInfo.version} (${packageInfo.buildNumber})';
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1A1918), Color(0xFF302824)],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(AppIcons.info, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'AI Expense Tracker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _versionLabel,
            style: TextStyle(
              color: Colors.white.withAlpha(220),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_metadataError != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _metadataError!,
              style: TextStyle(
                color: Colors.white.withAlpha(190),
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

  Widget _buildBuildDetailsCard(PackageInfo? packageInfo) {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Installed build',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Live package metadata from this build is shown below.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Column(
              children: <Widget>[
                _BuildInfoRow(
                  label: 'Version',
                  value: packageInfo?.version ?? '--',
                ),
                Divider(
                  height: 1,
                  color: ShellStyles.border(context),
                  indent: 14,
                  endIndent: 14,
                ),
                _BuildInfoRow(
                  label: 'Build number',
                  value: packageInfo?.buildNumber ?? '--',
                ),
                Divider(
                  height: 1,
                  color: ShellStyles.border(context),
                  indent: 14,
                  endIndent: 14,
                ),
                _BuildInfoRow(
                  label: 'Package name',
                  value: packageInfo?.packageName ?? '--',
                  compactValue: true,
                ),
              ],
            ),
          ),
        ],
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
                      title: 'GitHub',
                      subtitle: AppEnv.githubUrl,
                      onTap: () => _openUrl(AppEnv.githubUrl),
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
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'Build details'),
              const SizedBox(height: 8),
              _buildBuildDetailsCard(packageInfo),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildInfoRow extends StatelessWidget {
  const _BuildInfoRow({
    required this.label,
    required this.value,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        crossAxisAlignment: compactValue
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: compactValue ? 2 : 1,
              overflow: compactValue
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: compactValue ? 12.5 : 15,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
