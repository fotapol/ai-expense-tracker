import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  final Map<String, bool> _values = <String, bool>{
    'push': true,
    'email': true,
    'spending': true,
    'budget': true,
    'receipts': true,
    'weekly': true,
    'insights': false,
    'marketing': false,
  };

  Widget _buildGroup(String label, List<_NotificationToggle> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShellStyles.sectionLabel(context, label),
        const SizedBox(height: 8),
        Container(
          decoration: ShellStyles.cardDecoration(context, radius: 18),
          child: Column(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                SettingsToggleRow(
                  title: items[index].title,
                  subtitle: items[index].subtitle,
                  value: _values[items[index].id] ?? false,
                  onChanged: (value) {
                    setState(() => _values[items[index].id] = value);
                  },
                ),
                if (index != items.length - 1)
                  Divider(
                    height: 1,
                    color: ShellStyles.border(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_notifications'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGroup(context.tr('settings_notification_channels'), [
                _NotificationToggle(
                  id: 'push',
                  title: context.tr('settings_push_notifications'),
                  subtitle: context.tr('settings_push_notifications_subtitle'),
                ),
                _NotificationToggle(
                  id: 'email',
                  title: context.tr('settings_email_notifications'),
                  subtitle: context.tr('settings_email_notifications_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_activity'), [
                _NotificationToggle(
                  id: 'spending',
                  title: context.tr('settings_spending_alerts'),
                  subtitle: context.tr('settings_spending_alerts_subtitle'),
                ),
                _NotificationToggle(
                  id: 'budget',
                  title: context.tr('settings_budget_alerts'),
                  subtitle: context.tr('settings_budget_alerts_subtitle'),
                ),
                _NotificationToggle(
                  id: 'receipts',
                  title: context.tr('settings_receipt_reminders'),
                  subtitle: context.tr('settings_receipt_reminders_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_summaries'), [
                _NotificationToggle(
                  id: 'weekly',
                  title: context.tr('settings_weekly_summary'),
                  subtitle: context.tr('settings_weekly_summary_subtitle'),
                ),
                _NotificationToggle(
                  id: 'insights',
                  title: context.tr('settings_ai_insights'),
                  subtitle: context.tr('settings_ai_insights_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_marketing'), [
                _NotificationToggle(
                  id: 'marketing',
                  title: context.tr('settings_promotions_updates'),
                  subtitle: context.tr('settings_promotions_updates_subtitle'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationToggle {
  const _NotificationToggle({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}
