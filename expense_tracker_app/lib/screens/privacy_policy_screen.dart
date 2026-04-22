import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static List<_PolicySection> _sections(BuildContext context) => [
    _PolicySection(
      title: context.tr('1_information_we_collect'),
      body:
          'We collect information that you provide directly to us, including:',
      bullets: [
        'Account information (name, email, password)',
        'Receipt images and scanned data',
        'Expense tracking and categorization data',
        'Payment and subscription information',
        'Device information and usage analytics',
      ],
    ),
    _PolicySection(
      title: context.tr('2_how_we_use_your_information'),
      body: 'We use the information we collect to:',
      bullets: [
        'Provide, maintain, and improve our services',
        'Process your receipts and categorize expenses',
        'Generate AI-powered insights and analytics',
        'Send you updates and promotional materials (with consent)',
        'Detect and prevent fraud and security issues',
      ],
    ),
    _PolicySection(
      title: context.tr('3_data_security'),
      body:
          'We implement industry-standard security measures to protect your data:',
      bullets: [
        'End-to-end encryption for all data transmission',
        'Secure cloud storage with regular backups',
        'Two-factor authentication support',
        'Regular security audits and updates',
        'Limited employee access to personal data',
      ],
    ),
    _PolicySection(
      title: context.tr('4_data_sharing'),
      body:
          'We do not sell your personal information. We may share your data only:',
      bullets: [
        'With your consent',
        'To comply with legal obligations',
        'With service providers who assist our operations',
        'In case of business transfers or mergers',
      ],
    ),
    _PolicySection(
      title: context.tr('5_your_rights'),
      body: 'You have the right to:',
      bullets: [
        'Access and download your data',
        'Correct inaccurate information',
        'Delete your account and data',
        'Opt out of marketing communications',
        'Withdraw consent for data processing',
      ],
    ),
    _PolicySection(
      title: context.tr('6_cookies_and_tracking'),
      body:
          'We use cookies and similar technologies to improve your experience, analyze usage, and personalize content. You can control cookie preferences through your device settings.',
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('7_children')s Privacy',
      body:
          'Our service is not intended for users under 18 years of age. We do not knowingly collect personal information from children.',
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('8_changes_to_this_policy'),
      body:
          'We may update this Privacy Policy from time to time. We will notify you of any significant changes via email or through the app.',
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('9_contact_us'),
      body:
          'If you have questions about this Privacy Policy, please contact us at:',
      bullets: ['privacy@expensetracker.com'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_privacy_policy'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last updated: March 18, 2026',
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: ShellStyles.heroCardDecoration(context, radius: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ShellStyles.heroBadgeSurface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ShellStyles.heroBadgeBorder(context),
                        ),
                      ),
                      child: Icon(
                        AppIcons.privacy,
                        color: ShellStyles.heroBadgeIcon(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Privacy Matters',
                            style: TextStyle(
                              color: ShellStyles.heroTextPrimary(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'We are committed to protecting your personal information and your right to privacy. This Privacy Policy explains how we collect, use, and protect your data.',
                            style: TextStyle(
                              color: ShellStyles.heroTextSecondary(context),
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < _sections(context).length; index++) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _SectionBlock(section: _sections(context)[index]),
                      ),
                      if (index != _sections(context).length - 1)
                        Divider(height: 1, color: ShellStyles.border(context)),
                    ],
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

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section});

  final _PolicySection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          section.body,
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (section.bullets.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...section.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ShellStyles.textMuted(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PolicySection {
  const _PolicySection({
    required this.title,
    required this.body,
    required this.bullets,
  });

  final String title;
  final String body;
  final List<String> bullets;
}
