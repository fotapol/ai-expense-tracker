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
        const SnackBar(
          content: Text(
            'Notifications are still blocked in your device settings.',
          ),
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
      return 'Notifications are unavailable';
    }
    if (_effectiveNotificationsEnabled) {
      return 'Notifications are on';
    }
    return 'Notifications are off';
  }

  String _statusSubtitle() {
    if (!_notificationsAvailableOnPlatform) {
      return 'This web build does not support local reminder notifications yet.';
    }
    if (!_systemNotificationsEnabled) {
      return 'Your device is currently blocking notifications for the app.';
    }
    if (!_pushEnabled) {
      return 'Notifications are allowed by the device, but turned off inside the app.';
    }
    return 'Bill reminders can be delivered on this device.';
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
                    ShellStyles.sectionLabel(context, 'Device'),
                    const SizedBox(height: 8),
                    _buildToggleCard(
                      title: context.tr('enable_notifications_in_the_app'),
                      subtitle: !_notificationsAvailableOnPlatform
                          ? 'Unavailable in this web build.'
                          : _systemNotificationsEnabled
                          ? 'Lets the app schedule bill reminder alerts.'
                          : 'Turn on notifications for this app in your device settings first.',
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
                          ? 'Unavailable in this web build.'
                          : _effectiveNotificationsEnabled
                          ? 'Schedules reminder notifications for your active bills.'
                          : 'Enable notifications above before bill reminders can run.',
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
