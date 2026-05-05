import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_env.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  static List<_FaqSection> _sections(BuildContext context) => [
    _FaqSection(
      title: context.tr('getting_started'),
      items: [
        _FaqItem(question: context.tr('faq_q1'), answer: context.tr('faq_a1')),
        _FaqItem(question: context.tr('faq_q2'), answer: context.tr('faq_a2')),
        _FaqItem(question: context.tr('faq_q3'), answer: context.tr('faq_a3')),
      ],
    ),
    _FaqSection(
      title: context.tr('subscription_billing'),
      items: [
        _FaqItem(question: context.tr('faq_q4'), answer: context.tr('faq_a4')),
        _FaqItem(question: context.tr('faq_q5'), answer: context.tr('faq_a5')),
        _FaqItem(question: context.tr('faq_q6'), answer: context.tr('faq_a6')),
        _FaqItem(question: context.tr('faq_q7'), answer: context.tr('faq_a7')),
      ],
    ),
    _FaqSection(
      title: context.tr('features_tools'),
      items: [
        _FaqItem(question: context.tr('faq_q8'), answer: context.tr('faq_a8')),
        _FaqItem(question: context.tr('faq_q9'), answer: context.tr('faq_a9')),
        _FaqItem(
          question: context.tr('faq_q10'),
          answer: context.tr('faq_a10'),
        ),
      ],
    ),
    _FaqSection(
      title: context.tr('privacy_security'),
      items: [
        _FaqItem(
          question: context.tr('faq_q11'),
          answer: context.tr('faq_a11'),
        ),
        _FaqItem(
          question: context.tr('faq_q12'),
          answer: context.tr('faq_a12'),
        ),
        _FaqItem(
          question: context.tr('faq_q13'),
          answer: context.tr('faq_a13'),
        ),
      ],
    ),
  ];

  String _query = '';
  String? _expandedQuestion;

  List<_FaqSection> _filteredSections() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _sections(context);
    return _sections(context)
        .map((section) {
          final items = section.items.where((item) {
            return item.question.toLowerCase().contains(query) ||
                item.answer.toLowerCase().contains(query);
          }).toList();
          return _FaqSection(title: section.title, items: items);
        })
        .where((section) => section.items.isNotEmpty)
        .toList();
  }

  Future<void> _openSupport() async {
    final supportEmail = AppEnv.supportEmail;
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {'subject': AppEnv.supportSubject},
    );
    final opened = await launchUrl(uri);
    if (!mounted || opened) return;
    await Clipboard.setData(ClipboardData(text: supportEmail));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'help_support_email_copied',
            params: {'email': supportEmail},
          ),
        ),
      ),
    );
  }

  void _toggleAnswer(_FaqItem item) {
    setState(() {
      _expandedQuestion = _expandedQuestion == item.question
          ? null
          : item.question;
    });
  }

  Widget _buildFaqCard(_FaqSection section) {
    return Container(
      decoration: ShellStyles.cardDecoration(context, radius: 18),
      child: Column(
        children: [
          for (var index = 0; index < section.items.length; index++) ...[
            Builder(
              builder: (context) {
                final item = section.items[index];
                final expanded = _expandedQuestion == item.question;
                return Column(
                  children: [
                    InkWell(
                      onTap: () => _toggleAnswer(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.question,
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              expanded
                                  ? AppIcons.chevronDown
                                  : AppIcons.chevronRight,
                              color: ShellStyles.textMuted(context),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expanded) ...[
                      Divider(
                        height: 1,
                        color: ShellStyles.border(context),
                        indent: 14,
                        endIndent: 14,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                        child: Text(
                          item.answer,
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 13.5,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (index != section.items.length - 1)
              Divider(
                height: 1,
                color: ShellStyles.border(context),
                indent: 14,
                endIndent: 14,
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections();
    return SettingsDetailScaffold(
      title: context.tr('settings_help_center'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSearchField(
                hintText: context.tr('help_search_hint'),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _openSupport,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: ShellStyles.heroCardDecoration(
                    context,
                    radius: 18,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ShellStyles.heroBadgeSurface(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ShellStyles.heroBadgeBorder(context),
                          ),
                        ),
                        child: Icon(
                          AppIcons.help,
                          color: ShellStyles.heroBadgeIcon(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('help_contact_support'),
                              style: TextStyle(
                                color: ShellStyles.heroTextPrimary(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('help_get_help_subtitle'),
                              style: TextStyle(
                                color: ShellStyles.heroTextSecondary(context),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        AppIcons.chevronRight,
                        color: ShellStyles.heroTextSecondary(context),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final section in sections) ...[
                ShellStyles.sectionLabel(context, section.title),
                const SizedBox(height: 8),
                _buildFaqCard(section),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqSection {
  const _FaqSection({required this.title, required this.items});

  final String title;
  final List<_FaqItem> items;
}

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}
