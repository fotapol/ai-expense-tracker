import 'package:flutter/material.dart';

import '../core/app_env.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static List<_TermsSection> _sections(BuildContext context) => [
    _TermsSection(
      title: context.tr('1_acceptance_of_terms'),
      paragraphs: [context.tr('terms_acceptance_body')],
    ),
    _TermsSection(
      title: context.tr('2_description_of_service'),
      paragraphs: [context.tr('terms_service_desc_body')],
      bullets: [
        context.tr('terms_service_bullet_1'),
        context.tr('terms_service_bullet_2'),
        context.tr('terms_service_bullet_3'),
        context.tr('terms_service_bullet_4'),
      ],
    ),
    _TermsSection(
      title: context.tr('3_user_accounts'),
      paragraphs: [context.tr('terms_accounts_body')],
      bullets: [
        context.tr('terms_accounts_bullet_1'),
        context.tr('terms_accounts_bullet_2'),
        context.tr('terms_accounts_bullet_3'),
        context.tr('terms_accounts_bullet_4'),
        context.tr('terms_accounts_bullet_5'),
      ],
    ),
    _TermsSection(
      title: context.tr('4_subscription_and_billing'),
      paragraphs: [context.tr('terms_billing_body')],
    ),
    _TermsSection(
      title: context.tr('5_prohibited_uses'),
      paragraphs: [context.tr('terms_prohibited_body')],
      bullets: [
        context.tr('terms_prohibited_bullet_1'),
        context.tr('terms_prohibited_bullet_2'),
        context.tr('terms_prohibited_bullet_3'),
        context.tr('terms_prohibited_bullet_4'),
        context.tr('terms_prohibited_bullet_5'),
        context.tr('terms_prohibited_bullet_6'),
      ],
    ),
    _TermsSection(
      title: context.tr('6_intellectual_property'),
      paragraphs: [context.tr('terms_ip_body')],
    ),
    _TermsSection(
      title: context.tr('7_service_availability'),
      paragraphs: [context.tr('terms_availability_body')],
    ),
    _TermsSection(
      title: context.tr('8_limitation_of_liability'),
      paragraphs: [context.tr('terms_liability_body')],
    ),
    _TermsSection(
      title: context.tr('9_termination'),
      paragraphs: [context.tr('terms_termination_body')],
    ),
    _TermsSection(
      title: context.tr('10_changes_to_terms'),
      paragraphs: [context.tr('terms_changes_body')],
    ),
    _TermsSection(
      title: context.tr('11_governing_law'),
      paragraphs: [context.tr('terms_law_body')],
    ),
    _TermsSection(
      title: context.tr('12_contact'),
      paragraphs: [context.tr('terms_contact_body'), AppEnv.supportEmail],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_terms_of_service'),
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
                        AppIcons.document,
                        color: ShellStyles.heroBadgeIcon(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Terms of Service',
                            style: TextStyle(
                              color: ShellStyles.heroTextPrimary(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            context.tr('terms_intro'),
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
                    for (
                      var index = 0;
                      index < _sections(context).length;
                      index++
                    ) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _TermsBlock(section: _sections(context)[index]),
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

class _TermsBlock extends StatelessWidget {
  const _TermsBlock({required this.section});

  final _TermsSection section;

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
        ...section.paragraphs.map(
          (paragraph) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              paragraph,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
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
    );
  }
}

class _TermsSection {
  const _TermsSection({
    required this.title,
    required this.paragraphs,
    this.bullets = const [],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}
