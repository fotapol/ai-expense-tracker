import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _showLinkPlaceholder(BuildContext context) {
    ShellStyles.showComingSoon(
      context,
      message: 'Link destinations can be connected here later.',
    );
  }

  Widget _buildLinkRow(BuildContext context, String label) {
    return InkWell(
      onTap: () => _showLinkPlaceholder(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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

  Widget _buildInfoCell(BuildContext context, String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_about'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
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
                child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(AppIcons.info, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'AI Expense Tracker',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Version 1.0.0 (Build 1)',
                      style: TextStyle(
                        color: Color(0xFFD4D4D6),
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '© 2026 AI Expense Tracker Inc.',
                      style: TextStyle(
                        color: Color(0xFFB7B7BA),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'What\'s New'),
              const SizedBox(height: 8),
              SettingsDetailCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...const [
                      'New: Items translation feature (Beta)',
                      'Improved: AI categorization accuracy',
                      'Fixed: Receipt scanning issues in low light',
                      'Enhanced: Export flow and performance improvements',
                    ].map(
                      (item) => Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $item',
                          style: TextStyle(
                            color: Color(0xFF2C9A5D),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'About Us'),
              const SizedBox(height: 8),
              SettingsDetailCard(
                child: Text(
                  'AI Expense Tracker was founded in 2026 with a mission to simplify expense management through intelligent automation. Our AI-powered platform helps users worldwide track spending, scan receipts, and gain valuable financial insights.\n\nWe believe financial management should be effortless, accurate, and accessible to everyone. That\'s why we\'re constantly innovating to bring you the best expense tracking experience.',
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              // const SizedBox(height: 16),
              // ShellStyles.sectionLabel(context, 'Credits & Acknowledgments'),
              // const SizedBox(height: 8),
              // SettingsDetailCard(
              //   child: Text(
              //     'Made with love in San Francisco by a dedicated team of designers, developers, and AI enthusiasts.\n\nSpecial thanks to our beta testers, contributors, and the open-source community for making this app possible.',
              //     style: TextStyle(
              //       color: ShellStyles.textMuted(context),
              //       fontSize: 13,
              //       height: 1.55,
              //     ),
              //   ),
              // ),
              const SizedBox(height: 16),
              ShellStyles.sectionLabel(context, 'Links'),
              const SizedBox(height: 8),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: [
                    _buildLinkRow(context, 'Website'),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(context, 'Twitter'),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(context, 'Instagram'),
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                      indent: 14,
                      endIndent: 14,
                    ),
                    _buildLinkRow(context, 'GitHub'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: ShellStyles.cardDecoration(context, radius: 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildInfoCell(context, 'Platform', 'Web App'),
                        _buildInfoCell(context, 'Build', 'Production'),
                      ],
                    ),
                    // Divider(height: 1, color: ShellStyles.border(context)),
                    Row(
                      children: [
                        _buildInfoCell(context, 'Last Updated', 'Mar 18, 2026'),
                        _buildInfoCell(context, 'Size', '12.4 MB'),
                      ],
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
