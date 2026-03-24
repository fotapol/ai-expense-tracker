import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
              'The Free plan includes basic receipt scanning, manual expense entry, and core reporting with a limited monthly scan allowance.',
        ),
        _FaqItem(
          question:
              'What\'s the difference between Individual and Family plans?',
          answer:
              'Individual unlocks premium scanning and analytics for one account. Family adds shared household management, member invites, and premium household tools.',
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
          question: 'How do I export my data?',
          answer:
              'Open Tools and choose Export Data. You can generate a file with your transactions and receipt information for external analysis or backup.',
        ),
        _FaqItem(
          question: 'What are Smart Insights?',
          answer:
              'Smart Insights are quick summaries based on your recent spending activity, pending receipt reviews, and category changes this month.',
        ),
        _FaqItem(
          question: 'How do I set up budgets?',
          answer:
              'Budget planning tools are being expanded. For now, you can monitor category trends in Analytics and use the budgeting placeholders as a preview of the upcoming flow.',
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
          question: 'How do I enable two-factor authentication?',
          answer:
              'Two-factor authentication support is planned. Once available, you will be able to enable it from Security in Settings.',
        ),
        _FaqItem(
          question: 'Can I delete my account?',
          answer:
              'Account deletion support is being finalized. Until then, contact support and we can help with account-related requests.',
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
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@expense-tracker.app',
      queryParameters: {'subject': 'Expense Tracker Support'},
    );
    final opened = await launchUrl(uri);
    if (!mounted || opened) return;
    ShellStyles.showComingSoon(
      context,
      message: 'Support contact is not configured on this device yet.',
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
