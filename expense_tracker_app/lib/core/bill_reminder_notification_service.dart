import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'api_client.dart';
import 'notification_preferences.dart';
import 'planning_logic.dart';

class BillReminderNotificationService {
  BillReminderNotificationService._();

  static final BillReminderNotificationService instance =
      BillReminderNotificationService._();

  static const String _channelId = 'bill_reminders';
  static const String _channelName = 'Bill Reminders';
  static const String _channelDescription =
      'Upcoming and due recurring bill reminders';
  static const String _payloadPrefix = 'bill_reminder|';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Future<void>? _initializationFuture;

  Future<void> initialize() {
    if (_initialized || kIsWeb) {
      return Future<void>.value();
    }
    return _initializationFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    tz_data.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    await initialize();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> handleAuthStateChanged(User? user) async {
    if (user == null) {
      await cancelAllBillReminderNotifications();
      return;
    }
    await syncScheduledNotifications();
  }

  Future<void> syncScheduledNotifications({DateTime? now}) async {
    if (kIsWeb) return;
    try {
      await initialize();
      final prefs = await notificationPreferencesStore.load();
      if (!prefs.push || !prefs.billReminders) {
        await cancelAllBillReminderNotifications();
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        await cancelAllBillReminderNotifications();
        return;
      }

      final rawBills = await ApiClient.listBillReminders();
      final reminders = rawBills
          .whereType<Map<String, dynamic>>()
          .map(BillReminderRecord.fromJson)
          .toList();

      await cancelAllBillReminderNotifications();

      final referenceTime = now ?? DateTime.now();
      for (final reminder in reminders) {
        final nextDueDate = nextSchedulableBillReminderDueDate(
          reminder,
          now: referenceTime,
        );
        if (nextDueDate == null) continue;
        await _scheduleForReminder(
          reminder,
          dueDate: nextDueDate,
          now: referenceTime,
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'BillReminderNotificationService.syncScheduledNotifications failed: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<void> cancelAllBillReminderNotifications() async {
    if (kIsWeb) return;
    await initialize();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.payload?.startsWith(_payloadPrefix) != true) continue;
      await _plugin.cancel(id: request.id);
    }
  }

  Future<void> _scheduleForReminder(
    BillReminderRecord reminder, {
    required DateTime dueDate,
    required DateTime now,
  }) async {
    final dueSoonAt = dueSoonNotificationDateTime(
      dueDate,
      reminder.remindDaysBefore,
    );
    if (dueSoonAt.isAfter(now)) {
      await _scheduleNotification(
        id: _notificationId(reminder.id, 'soon'),
        title: 'Bill due soon',
        body:
            '${reminder.name} is due on ${_shortDate(dueDate)}. '
            'Amount: ${reminder.currency} ${reminder.amount.toStringAsFixed(2)}',
        scheduledAt: dueSoonAt,
        payload: '$_payloadPrefix${reminder.id}|soon',
      );
    }

    final dueAt = dueDateNotificationDateTime(dueDate);
    if (dueAt.isAfter(now)) {
      await _scheduleNotification(
        id: _notificationId(reminder.id, 'due'),
        title: 'Bill due today',
        body:
            '${reminder.name} is due today. '
            'Amount: ${reminder.currency} ${reminder.amount.toStringAsFixed(2)}',
        scheduledAt: dueAt,
        payload: '$_payloadPrefix${reminder.id}|due',
      );
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  int _notificationId(String reminderId, String kind) {
    final base = _stableHash(reminderId);
    return kind == 'soon' ? base * 2 : base * 2 + 1;
  }

  int _stableHash(String value) {
    var hash = 2166136261;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash & 0x3fffffff;
  }

  String _shortDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }
}
