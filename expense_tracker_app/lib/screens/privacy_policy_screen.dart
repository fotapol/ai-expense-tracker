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
          context.tr('privacy_collect_body'),
      bullets: [
        context.tr('privacy_collect_bullet_1'),
        context.tr('privacy_collect_bullet_2'),
        context.tr('privacy_collect_bullet_3'),
        context.tr('privacy_collect_bullet_4'),
        context.tr('privacy_collect_bullet_5'),
      ],
    ),
    _PolicySection(
      title: context.tr('2_how_we_use_your_information'),
      body: context.tr('privacy_use_body'),
      bullets: [
        context.tr('privacy_use_bullet_1'),
        context.tr('privacy_use_bullet_2'),
        context.tr('privacy_use_bullet_3'),
        context.tr('privacy_use_bullet_4'),
        context.tr('privacy_use_bullet_5'),
      ],
    ),
    _PolicySection(
      title: context.tr('3_data_security'),
      body:
          context.tr('privacy_security_body'),
      bullets: [
        context.tr('privacy_security_bullet_1'),
        context.tr('privacy_security_bullet_2'),
        context.tr('privacy_security_bullet_3'),
        context.tr('privacy_security_bullet_4'),
        context.tr('privacy_security_bullet_5'),
      ],
    ),
    _PolicySection(
      title: context.tr('4_data_sharing'),
      body:
          context.tr('privacy_sharing_body'),
      bullets: [
        context.tr('privacy_sharing_bullet_1'),
        context.tr('privacy_sharing_bullet_2'),
        context.tr('privacy_sharing_bullet_3'),
        context.tr('privacy_sharing_bullet_4'),
      ],
    ),
    _PolicySection(
      title: context.tr('5_your_rights'),
      body: context.tr('privacy_rights_body'),
      bullets: [
        context.tr('privacy_rights_bullet_1'),
        context.tr('privacy_rights_bullet_2'),
        context.tr('privacy_rights_bullet_3'),
        context.tr('privacy_rights_bullet_4'),
        context.tr('privacy_rights_bullet_5'),
      ],
    ),
    _PolicySection(
      title: context.tr('6_cookies_and_tracking'),
      body:
          context.tr('privacy_cookies_body'),
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('privacy_children_title'),
      body:
          context.tr('privacy_children_body'),
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('8_changes_to_this_policy'),
      body:
          context.tr('privacy_changes_body'),
      bullets: [],
    ),
    _PolicySection(
      title: context.tr('9_contact_us'),
      body:
          context.tr('privacy_contact_body'),
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
                context.tr('privacy_last_updated'),
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
                            context.tr('privacy_hero_title'),
                            style: TextStyle(
                              color: ShellStyles.heroTextPrimary(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            context.tr('privacy_intro'),
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
