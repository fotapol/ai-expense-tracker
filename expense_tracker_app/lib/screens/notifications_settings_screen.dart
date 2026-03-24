import 'package:flutter/material.dart';

import '../core/bill_reminder_notification_service.dart';
import '../core/notification_preferences.dart';
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
  Map<String, bool> _values = <String, bool>{
    NotificationPreferencesStore.idPush: NotificationPreferences.defaults.push,
    NotificationPreferencesStore.idEmail:
        NotificationPreferences.defaults.email,
    NotificationPreferencesStore.idSpending:
        NotificationPreferences.defaults.spending,
    NotificationPreferencesStore.idBudget:
        NotificationPreferences.defaults.budget,
    NotificationPreferencesStore.idReceipts:
        NotificationPreferences.defaults.receipts,
    NotificationPreferencesStore.idBillReminders:
        NotificationPreferences.defaults.billReminders,
    NotificationPreferencesStore.idWeekly:
        NotificationPreferences.defaults.weekly,
    NotificationPreferencesStore.idInsights:
        NotificationPreferences.defaults.insights,
    NotificationPreferencesStore.idMarketing:
        NotificationPreferences.defaults.marketing,
  };

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  Future<void> _loadValues() async {
    final prefs = await notificationPreferencesStore.load();
    if (!mounted) return;
    setState(() {
      _values = <String, bool>{
        NotificationPreferencesStore.idPush: prefs.push,
        NotificationPreferencesStore.idEmail: prefs.email,
        NotificationPreferencesStore.idSpending: prefs.spending,
        NotificationPreferencesStore.idBudget: prefs.budget,
        NotificationPreferencesStore.idReceipts: prefs.receipts,
        NotificationPreferencesStore.idBillReminders: prefs.billReminders,
        NotificationPreferencesStore.idWeekly: prefs.weekly,
        NotificationPreferencesStore.idInsights: prefs.insights,
        NotificationPreferencesStore.idMarketing: prefs.marketing,
      };
    });
  }

  Future<void> _setValue(String id, bool value) async {
    setState(() => _values[id] = value);
    await notificationPreferencesStore.updateValue(id, value);
    if ((id == NotificationPreferencesStore.idPush ||
            id == NotificationPreferencesStore.idBillReminders) &&
        value) {
      await BillReminderNotificationService.instance.requestPermissions();
    }
    await BillReminderNotificationService.instance.syncScheduledNotifications();
  }

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
                    _setValue(items[index].id, value);
                  },
                ),
                if (index != items.length - 1)
                  Divider(height: 1, color: ShellStyles.border(context)),
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
                  id: NotificationPreferencesStore.idPush,
                  title: context.tr('settings_push_notifications'),
                  subtitle: context.tr('settings_push_notifications_subtitle'),
                ),
                _NotificationToggle(
                  id: NotificationPreferencesStore.idEmail,
                  title: context.tr('settings_email_notifications'),
                  subtitle: context.tr('settings_email_notifications_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_activity'), [
                _NotificationToggle(
                  id: NotificationPreferencesStore.idSpending,
                  title: context.tr('settings_spending_alerts'),
                  subtitle: context.tr('settings_spending_alerts_subtitle'),
                ),
                _NotificationToggle(
                  id: NotificationPreferencesStore.idBudget,
                  title: context.tr('settings_budget_alerts'),
                  subtitle: context.tr('settings_budget_alerts_subtitle'),
                ),
                _NotificationToggle(
                  id: NotificationPreferencesStore.idBillReminders,
                  title: context.tr('settings_bill_reminders'),
                  subtitle: context.tr('settings_bill_reminders_subtitle'),
                ),
                _NotificationToggle(
                  id: NotificationPreferencesStore.idReceipts,
                  title: context.tr('settings_receipt_reminders'),
                  subtitle: context.tr('settings_receipt_reminders_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_summaries'), [
                _NotificationToggle(
                  id: NotificationPreferencesStore.idWeekly,
                  title: context.tr('settings_weekly_summary'),
                  subtitle: context.tr('settings_weekly_summary_subtitle'),
                ),
                _NotificationToggle(
                  id: NotificationPreferencesStore.idInsights,
                  title: context.tr('settings_ai_insights'),
                  subtitle: context.tr('settings_ai_insights_subtitle'),
                ),
              ]),
              const SizedBox(height: 16),
              _buildGroup(context.tr('settings_notification_marketing'), [
                _NotificationToggle(
                  id: NotificationPreferencesStore.idMarketing,
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
