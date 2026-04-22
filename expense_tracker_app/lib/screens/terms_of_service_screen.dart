import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static List<_TermsSection> _sections(BuildContext context) => [
    _TermsSection(
      title: context.tr('1_acceptance_of_terms'),
      paragraphs: [
        'By creating an account and using AI Expense Tracker, you agree to comply with and be bound by these Terms of Service. If you do not agree to these terms, please do not use our service.',
      ],
    ),
    _TermsSection(
      title: context.tr('2_description_of_service'),
      paragraphs: ['AI Expense Tracker provides:'],
      bullets: [
        'Receipt scanning and optical character recognition (OCR)',
        'Expense tracking and categorization',
        'AI-powered financial insights and analytics',
        'Budget management and spending reports',
        'Household expense sharing (Family plan only)',
      ],
    ),
    _TermsSection(
      title: context.tr('3_user_accounts'),
      paragraphs: ['You are responsible for:'],
      bullets: [
        'Maintaining the confidentiality of your account credentials',
        'All activities that occur under your account',
        'Notifying us immediately of any unauthorized access',
        'Providing accurate and complete information',
        'Keeping your account information up to date',
      ],
    ),
    _TermsSection(
      title: context.tr('4_subscription_and_billing'),
      paragraphs: [
        'Paid subscriptions are billed in advance on a monthly or yearly basis. You can cancel your subscription at any time, and you will continue to have access until the end of your billing period. No refunds are provided for partial periods.',
      ],
    ),
    _TermsSection(
      title: context.tr('5_prohibited_uses'),
      paragraphs: ['You agree not to:'],
      bullets: [
        'Use the service for illegal, fraudulent, or misleading activity',
        'Reverse engineer or attempt to copy protected product features',
        'Interfere with app stability, security, or availability',
        'Upload harmful, abusive, or infringing content',
        'Harass or abuse other users or our support team',
        'Use automated systems to access the service at scale',
      ],
    ),
    _TermsSection(
      title: context.tr('6_intellectual_property'),
      paragraphs: [
        'All content, features, and functionality of AI Expense Tracker are owned by us and are protected by copyright, trademark, and other intellectual property laws. You retain ownership of your data and receipts.',
      ],
    ),
    _TermsSection(
      title: context.tr('7_service_availability'),
      paragraphs: [
        'We strive to provide reliable service but do not guarantee uninterrupted access. We may modify, suspend, or discontinue any part of the service at any time with reasonable notice.',
      ],
    ),
    _TermsSection(
      title: context.tr('8_limitation_of_liability'),
      paragraphs: [
        'We are not liable for any indirect, incidental, special, or consequential damages arising from your use of the service. Our total liability shall not exceed the amount you paid in the past 12 months.',
      ],
    ),
    _TermsSection(
      title: context.tr('9_termination'),
      paragraphs: [
        'We reserve the right to terminate or suspend your account if you violate these terms. Upon termination, you may request a copy of your data within 30 days.',
      ],
    ),
    _TermsSection(
      title: context.tr('10_changes_to_terms'),
      paragraphs: [
        'We may modify these terms at any time. Continued use of the service after changes constitutes acceptance of the new terms. We will notify you of significant changes.',
      ],
    ),
    _TermsSection(
      title: context.tr('11_governing_law'),
      paragraphs: [
        'These terms are governed by the laws of the United States. Any disputes shall be resolved in the courts of San Francisco, California.',
      ],
    ),
    _TermsSection(
      title: context.tr('12_contact'),
      paragraphs: [
        'For questions about these Terms of Service, contact us at:',
        'legal@expensetracker.com',
      ],
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
                            'Please read these terms carefully before using our service. By using AI Expense Tracker, you agree to be bound by these terms.',
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
