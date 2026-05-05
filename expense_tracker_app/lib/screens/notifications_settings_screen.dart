import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/bill_reminder_notification_service.dart';
import '../core/notification_preferences.dart';
import '../core/redesign_system.dart';
import 'settings_detail_scaffold.dart';
import '../l10n/app_localizations.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _pushEnabled = NotificationPreferences.defaults.push;
  bool _billRemindersEnabled = NotificationPreferences.defaults.billReminders;
  bool _systemNotificationsEnabled = false;

  bool get _notificationsAvailableOnPlatform => !kIsWeb;
  bool get _effectiveNotificationsEnabled =>
      _notificationsAvailableOnPlatform &&
      _pushEnabled &&
      _systemNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadValues();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshSystemStatus();
  }

  Future<void> _loadValues() async {
    final prefs = await notificationPreferencesStore.load();
    final systemEnabled = _notificationsAvailableOnPlatform
        ? await BillReminderNotificationService.instance
              .areNotificationsEnabled()
        : false;
    if (!mounted) return;
    setState(() {
      _pushEnabled = prefs.push;
      _billRemindersEnabled = prefs.billReminders;
      _systemNotificationsEnabled = systemEnabled;
      _isLoading = false;
    });
  }

  Future<void> _refreshSystemStatus() async {
    if (!_notificationsAvailableOnPlatform) return;
    final systemEnabled = await BillReminderNotificationService.instance
        .areNotificationsEnabled();
    if (!mounted) return;
    setState(() => _systemNotificationsEnabled = systemEnabled);
  }

  Future<void> _setPushEnabled(bool value) async {
    if (!_notificationsAvailableOnPlatform) return;

    if (!value) {
      await notificationPreferencesStore.updateValue(
        NotificationPreferencesStore.idPush,
        false,
      );
      if (!mounted) return;
      setState(() => _pushEnabled = false);
      await BillReminderNotificationService.instance
          .syncScheduledNotifications();
      return;
    }

    final granted = await BillReminderNotificationService.instance
        .ensurePermissions();
    await notificationPreferencesStore.updateValue(
      NotificationPreferencesStore.idPush,
      granted,
    );
    if (!mounted) return;
    setState(() {
      _pushEnabled = granted;
      _systemNotificationsEnabled = granted;
    });
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('notifications_still_blocked_snackbar')),
        ),
      );
    }
    await BillReminderNotificationService.instance.syncScheduledNotifications();
  }

  Future<void> _setBillRemindersEnabled(bool value) async {
    setState(() => _billRemindersEnabled = value);
    await notificationPreferencesStore.updateValue(
      NotificationPreferencesStore.idBillReminders,
      value,
    );
    await BillReminderNotificationService.instance.syncScheduledNotifications();
  }

  String _statusTitle() {
    if (!_notificationsAvailableOnPlatform) {
      return context.tr('notifications_status_unavailable');
    }
    if (_effectiveNotificationsEnabled) {
      return context.tr('notifications_status_on');
    }
    return context.tr('notifications_status_off');
  }

  String _statusSubtitle() {
    if (!_notificationsAvailableOnPlatform) {
      return context.tr('notifications_web_unavailable_detail');
    }
    if (!_systemNotificationsEnabled) {
      return context.tr('notifications_device_blocking_detail');
    }
    if (!_pushEnabled) {
      return context.tr('notifications_app_off_detail');
    }
    return context.tr('notifications_bill_reminders_available_detail');
  }

  Widget _buildStatusCard() {
    final active = _effectiveNotificationsEnabled;
    return SettingsDetailCard(
      radius: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? ShellStyles.accent(context).withAlpha(22)
                  : ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? ShellStyles.accent(context).withAlpha(80)
                    : ShellStyles.border(context),
              ),
            ),
            child: Icon(
              AppIcons.notifications,
              color: active
                  ? ShellStyles.accent(context)
                  : ShellStyles.textPrimary(context),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _statusTitle(),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusSubtitle(),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SettingsDetailCard(
          radius: 18,
          padding: EdgeInsets.zero,
          child: SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            value: value,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // TODO(notifications): restore email notifications when backend delivery
    // and preference syncing are implemented.
    // TODO(notifications): restore spending, budget, receipt, weekly summary,
    // insights, and marketing notification controls when each category has a
    // real end-to-end notification pipeline.
    return SettingsDetailScaffold(
      title: context.tr('settings_notifications'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('notifications_device_section'),
                    ),
                    const SizedBox(height: 8),
                    _buildToggleCard(
                      title: context.tr('enable_notifications_in_the_app'),
                      subtitle: !_notificationsAvailableOnPlatform
                          ? context.tr('notifications_unavailable_web_short')
                          : _systemNotificationsEnabled
                          ? context.tr('notifications_schedule_app_alerts')
                          : context.tr(
                              'notifications_enable_device_settings_first',
                            ),
                      value: _pushEnabled && _systemNotificationsEnabled,
                      onChanged: _setPushEnabled,
                      enabled: _notificationsAvailableOnPlatform,
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('settings_bill_reminders'),
                    ),
                    const SizedBox(height: 8),
                    _buildToggleCard(
                      title: context.tr('upcoming_and_due_reminders'),
                      subtitle: !_notificationsAvailableOnPlatform
                          ? context.tr('notifications_unavailable_web_short')
                          : _effectiveNotificationsEnabled
                          ? context.tr('notifications_schedule_bill_reminders')
                          : context.tr(
                              'notifications_enable_above_for_bill_reminders',
                            ),
                      value: _billRemindersEnabled,
                      onChanged: _setBillRemindersEnabled,
                      enabled: _effectiveNotificationsEnabled,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
