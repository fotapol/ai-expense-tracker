import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  const NotificationPreferences({
    this.push = true,
    this.email = true,
    this.spending = true,
    this.budget = true,
    this.receipts = true,
    this.billReminders = true,
    this.weekly = true,
    this.insights = false,
    this.marketing = false,
  });

  static const NotificationPreferences defaults = NotificationPreferences();

  final bool push;
  final bool email;
  final bool spending;
  final bool budget;
  final bool receipts;
  final bool billReminders;
  final bool weekly;
  final bool insights;
  final bool marketing;

  NotificationPreferences copyWith({
    bool? push,
    bool? email,
    bool? spending,
    bool? budget,
    bool? receipts,
    bool? billReminders,
    bool? weekly,
    bool? insights,
    bool? marketing,
  }) {
    return NotificationPreferences(
      push: push ?? this.push,
      email: email ?? this.email,
      spending: spending ?? this.spending,
      budget: budget ?? this.budget,
      receipts: receipts ?? this.receipts,
      billReminders: billReminders ?? this.billReminders,
      weekly: weekly ?? this.weekly,
      insights: insights ?? this.insights,
      marketing: marketing ?? this.marketing,
    );
  }

  bool valueForId(String id) {
    switch (id) {
      case NotificationPreferencesStore.idPush:
        return push;
      case NotificationPreferencesStore.idEmail:
        return email;
      case NotificationPreferencesStore.idSpending:
        return spending;
      case NotificationPreferencesStore.idBudget:
        return budget;
      case NotificationPreferencesStore.idReceipts:
        return receipts;
      case NotificationPreferencesStore.idBillReminders:
        return billReminders;
      case NotificationPreferencesStore.idWeekly:
        return weekly;
      case NotificationPreferencesStore.idInsights:
        return insights;
      case NotificationPreferencesStore.idMarketing:
        return marketing;
      default:
        return false;
    }
  }

  NotificationPreferences copyWithValue(String id, bool value) {
    switch (id) {
      case NotificationPreferencesStore.idPush:
        return copyWith(push: value);
      case NotificationPreferencesStore.idEmail:
        return copyWith(email: value);
      case NotificationPreferencesStore.idSpending:
        return copyWith(spending: value);
      case NotificationPreferencesStore.idBudget:
        return copyWith(budget: value);
      case NotificationPreferencesStore.idReceipts:
        return copyWith(receipts: value);
      case NotificationPreferencesStore.idBillReminders:
        return copyWith(billReminders: value);
      case NotificationPreferencesStore.idWeekly:
        return copyWith(weekly: value);
      case NotificationPreferencesStore.idInsights:
        return copyWith(insights: value);
      case NotificationPreferencesStore.idMarketing:
        return copyWith(marketing: value);
      default:
        return this;
    }
  }
}

class NotificationPreferencesStore {
  static const String idPush = 'push';
  static const String idEmail = 'email';
  static const String idSpending = 'spending';
  static const String idBudget = 'budget';
  static const String idReceipts = 'receipts';
  static const String idBillReminders = 'bill_reminders';
  static const String idWeekly = 'weekly';
  static const String idInsights = 'insights';
  static const String idMarketing = 'marketing';

  static const String _prefix = 'notification_pref_';

  Future<NotificationPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationPreferences(
      push:
          prefs.getBool(_key(idPush)) ?? NotificationPreferences.defaults.push,
      email:
          prefs.getBool(_key(idEmail)) ??
          NotificationPreferences.defaults.email,
      spending:
          prefs.getBool(_key(idSpending)) ??
          NotificationPreferences.defaults.spending,
      budget:
          prefs.getBool(_key(idBudget)) ??
          NotificationPreferences.defaults.budget,
      receipts:
          prefs.getBool(_key(idReceipts)) ??
          NotificationPreferences.defaults.receipts,
      billReminders:
          prefs.getBool(_key(idBillReminders)) ??
          NotificationPreferences.defaults.billReminders,
      weekly:
          prefs.getBool(_key(idWeekly)) ??
          NotificationPreferences.defaults.weekly,
      insights:
          prefs.getBool(_key(idInsights)) ??
          NotificationPreferences.defaults.insights,
      marketing:
          prefs.getBool(_key(idMarketing)) ??
          NotificationPreferences.defaults.marketing,
    );
  }

  Future<NotificationPreferences> save(NotificationPreferences value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(idPush), value.push);
    await prefs.setBool(_key(idEmail), value.email);
    await prefs.setBool(_key(idSpending), value.spending);
    await prefs.setBool(_key(idBudget), value.budget);
    await prefs.setBool(_key(idReceipts), value.receipts);
    await prefs.setBool(_key(idBillReminders), value.billReminders);
    await prefs.setBool(_key(idWeekly), value.weekly);
    await prefs.setBool(_key(idInsights), value.insights);
    await prefs.setBool(_key(idMarketing), value.marketing);
    return value;
  }

  Future<NotificationPreferences> updateValue(String id, bool value) async {
    final current = await load();
    final updated = current.copyWithValue(id, value);
    return save(updated);
  }

  String _key(String id) => '$_prefix$id';
}

final notificationPreferencesStore = NotificationPreferencesStore();
