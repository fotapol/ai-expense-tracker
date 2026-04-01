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
  static const List<_FaqSection> _sections = [
    _FaqSection(
      title: 'Getting Started',
      items: [
        _FaqItem(
          question: 'How do I scan my first receipt?',
          answer:
              'Open Home or Tools and tap Scan Receipt. Take a clear photo, confirm the capture, and we will extract the merchant, date, total, and line items for review.',
        ),
        _FaqItem(
          question: 'How does the AI categorization work?',
          answer:
              'The app uses the merchant name, item names, and receipt totals to suggest categories automatically. You can always adjust the category manually before saving.',
        ),
        _FaqItem(
          question: 'Can I manually add expenses?',
          answer:
              'Yes. Use Add Expense from the Home quick actions or open the receipts flow and create a transaction without scanning a receipt.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Subscription & Billing',
      items: [
        _FaqItem(
          question: 'What\'s included in the Free plan?',
          answer:
              'The Free plan includes manual expense entry, receipt review, and core history with a limited monthly scan allowance.',
        ),
        _FaqItem(
          question: 'What does Premium unlock?',
          answer:
              'Premium unlocks unlimited receipt scans, deeper analytics, labels, and planning tools for your personal account.',
        ),
        _FaqItem(
          question: 'How do I restore Premium access?',
          answer:
              'Open Subscription and tap Restore Purchases. Your store keeps the subscription tied to the same account.',
        ),
        _FaqItem(
          question: 'Can I cancel anytime?',
          answer:
              'Yes. You can cancel through your store subscription settings at any time and keep access until the current billing period ends.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Features & Tools',
      items: [
        _FaqItem(
          question: 'How do I review extracted items?',
          answer:
              'After scanning, review the merchant, total, date, and line items before saving. You can adjust categories, labels, and receipt details on the review screen.',
        ),
        _FaqItem(
          question: 'What are labels for?',
          answer:
              'Labels help you group transactions your own way, like work, travel, or groceries, so you can filter them later in history and analytics.',
        ),
        _FaqItem(
          question: 'Where do I find reminders and budget tools?',
          answer:
              'Open Tools to manage bill reminders, categories, labels, and budget planning tools from one place.',
        ),
      ],
    ),
    _FaqSection(
      title: 'Privacy & Security',
      items: [
        _FaqItem(
          question: 'Is my financial data secure?',
          answer:
              'We protect account and receipt data using authenticated access, secure transport, and restricted internal access. Sensitive actions always require an authenticated session.',
        ),
        _FaqItem(
          question: 'What if my receipt needs corrections?',
          answer:
              'That is normal. Review the extracted details, adjust anything that looks off, and then save only when the receipt looks right to you.',
        ),
        _FaqItem(
          question: 'How do I contact support?',
          answer:
              'Use the Contact Support button or email support@expense-tracker.app and include a short description of the issue.',
        ),
      ],
    ),
  ];

  String _query = '';
  String? _expandedQuestion;

  List<_FaqSection> _filteredSections() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _sections;
    return _sections
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
      SnackBar(content: Text('Support email copied: $supportEmail')),
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
                hintText: 'Search for help...',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _openSupport,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F20),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(AppIcons.help, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Contact Support',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Get help from our support team',
                              style: TextStyle(
                                color: Color(0xFFD2D2D4),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        AppIcons.chevronRight,
                        color: Colors.white70,
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
