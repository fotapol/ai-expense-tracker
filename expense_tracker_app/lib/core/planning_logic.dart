import 'dart:math' as math;

class BudgetCategoryLimitRecord {
  const BudgetCategoryLimitRecord({
    required this.categoryId,
    required this.limitAmount,
  });

  final String categoryId;
  final double limitAmount;

  factory BudgetCategoryLimitRecord.fromJson(Map<String, dynamic> json) {
    return BudgetCategoryLimitRecord(
      categoryId: json['category_id']?.toString() ?? '',
      limitAmount: _parseDouble(json['limit_amount']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'category_id': categoryId,
    'limit_amount': limitAmount,
  };
}

class BudgetPlanRecord {
  const BudgetPlanRecord({
    required this.currency,
    required this.categoryLimits,
    this.monthlyIncome,
  });

  final double? monthlyIncome;
  final String currency;
  final List<BudgetCategoryLimitRecord> categoryLimits;

  factory BudgetPlanRecord.fromJson(Map<String, dynamic> json) {
    final rawLimits = json['category_limits'] as List<dynamic>? ?? const [];
    return BudgetPlanRecord(
      monthlyIncome: json['monthly_income'] == null
          ? null
          : _parseDouble(json['monthly_income']),
      currency: (json['currency']?.toString() ?? 'EUR').toUpperCase(),
      categoryLimits: rawLimits
          .whereType<Map<String, dynamic>>()
          .map(BudgetCategoryLimitRecord.fromJson)
          .toList(),
    );
  }
}

class BudgetCategoryProgress {
  const BudgetCategoryProgress({
    required this.categoryId,
    required this.categoryCode,
    required this.categoryName,
    required this.limitAmount,
    required this.spentAmount,
  });

  final String categoryId;
  final String categoryCode;
  final String categoryName;
  final double limitAmount;
  final double spentAmount;

  bool get isExceeded => limitAmount > 0 && spentAmount > limitAmount;
  double get remainingAmount => limitAmount - spentAmount;
  double get progress =>
      limitAmount <= 0 ? 0 : (spentAmount / limitAmount).clamp(0, 1).toDouble();
}

class BudgetOverview {
  const BudgetOverview({
    required this.totalBudget,
    required this.totalSpent,
    required this.remaining,
    required this.savingsGoal,
  });

  final double totalBudget;
  final double totalSpent;
  final double remaining;
  final double savingsGoal;

  bool get isOverBudget => totalSpent > totalBudget;
}

BudgetOverview buildBudgetOverview({
  required double monthlyIncome,
  required List<BudgetCategoryProgress> categories,
  required double totalSpent,
}) {
  final allocatedBudget = categories.fold<double>(
    0,
    (sum, category) => sum + category.limitAmount,
  );
  final totalBudget = monthlyIncome > 0 ? monthlyIncome : allocatedBudget;
  return BudgetOverview(
    totalBudget: totalBudget,
    totalSpent: totalSpent,
    remaining: totalBudget - totalSpent,
    savingsGoal: monthlyIncome > 0 && allocatedBudget > 0
        ? math.max(monthlyIncome - allocatedBudget, 0)
        : 0,
  );
}

class BillReminderRecord {
  const BillReminderRecord({
    required this.id,
    required this.name,
    required this.amount,
    required this.currency,
    required this.recurrence,
    required this.firstDueDate,
    required this.remindDaysBefore,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
    this.lastPaidDueDate,
    this.lastPaidAt,
    this.lastSkippedDueDate,
  });

  final String id;
  final String name;
  final double amount;
  final String currency;
  final String recurrence;
  final DateTime firstDueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastPaidDueDate;
  final DateTime? lastPaidAt;
  final DateTime? lastSkippedDueDate;
  final int remindDaysBefore;
  final bool isActive;

  factory BillReminderRecord.fromJson(Map<String, dynamic> json) {
    return BillReminderRecord(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      amount: _parseDouble(json['amount']),
      currency: (json['currency']?.toString() ?? 'EUR').toUpperCase(),
      recurrence: normalizeBillReminderRecurrence(
        json['recurrence']?.toString(),
      ),
      firstDueDate: _dateOnly(
        DateTime.parse(json['first_due_date'].toString()),
      ),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'].toString()).toLocal(),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'].toString()).toLocal(),
      lastPaidDueDate: json['last_paid_due_date'] == null
          ? null
          : _dateOnly(DateTime.parse(json['last_paid_due_date'].toString())),
      lastPaidAt: json['last_paid_at'] == null
          ? null
          : DateTime.parse(json['last_paid_at'].toString()).toLocal(),
      lastSkippedDueDate: json['last_skipped_due_date'] == null
          ? null
          : _dateOnly(DateTime.parse(json['last_skipped_due_date'].toString())),
      remindDaysBefore:
          int.tryParse(json['remind_days_before']?.toString() ?? '3') ?? 3,
      isActive: json['is_active'] != false,
    );
  }
}

enum BillReminderStatus { upcoming, dueSoon, overdue }

const String billReminderRecurrenceNone = 'none';
const String billReminderRecurrenceDaily = 'daily';
const String billReminderRecurrenceWeekly = 'weekly';
const String billReminderRecurrenceMonthly = 'monthly';
const String billReminderRecurrenceYearly = 'yearly';

String normalizeBillReminderRecurrence(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'once':
    case 'one-time':
    case 'one_time':
    case billReminderRecurrenceNone:
      return billReminderRecurrenceNone;
    case billReminderRecurrenceDaily:
      return billReminderRecurrenceDaily;
    case billReminderRecurrenceWeekly:
      return billReminderRecurrenceWeekly;
    case billReminderRecurrenceYearly:
      return billReminderRecurrenceYearly;
    case billReminderRecurrenceMonthly:
    default:
      return billReminderRecurrenceMonthly;
  }
}

class BillReminderOccurrence {
  const BillReminderOccurrence({
    required this.reminder,
    required this.dueDate,
    required this.status,
  });

  final BillReminderRecord reminder;
  final DateTime dueDate;
  final BillReminderStatus status;

  bool get isOverdue => status == BillReminderStatus.overdue;
}

DateTime monthlyDueDate(DateTime anchorDate, int year, int month) {
  final normalizedMonth = DateTime(year, month);
  final lastDay = DateTime(normalizedMonth.year, normalizedMonth.month + 1, 0);
  return DateTime(
    normalizedMonth.year,
    normalizedMonth.month,
    math.min(anchorDate.day, lastDay.day),
  );
}

DateTime nextMonthlyDueDate(DateTime anchorDate, DateTime currentDueDate) {
  final nextMonth = DateTime(currentDueDate.year, currentDueDate.month + 1);
  return monthlyDueDate(anchorDate, nextMonth.year, nextMonth.month);
}

DateTime weeklyDueDate(DateTime anchorDate, DateTime value) {
  final anchor = _dateOnly(anchorDate);
  final date = _dateOnly(value);
  if (anchor.isAfter(date)) {
    return anchor;
  }
  final elapsedDays = date.difference(anchor).inDays;
  final weekOffset = elapsedDays ~/ 7;
  return anchor.add(Duration(days: weekOffset * 7));
}

DateTime nextWeeklyDueDate(DateTime currentDueDate) {
  return _dateOnly(currentDueDate).add(const Duration(days: 7));
}

DateTime yearlyDueDate(DateTime anchorDate, int year) {
  final lastDay = DateTime(year, anchorDate.month + 1, 0);
  return DateTime(
    year,
    anchorDate.month,
    math.min(anchorDate.day, lastDay.day),
  );
}

DateTime nextYearlyDueDate(DateTime anchorDate, DateTime currentDueDate) {
  return yearlyDueDate(anchorDate, currentDueDate.year + 1);
}

DateTime? billReminderDueDateForList(
  BillReminderRecord reminder, {
  DateTime? now,
}) {
  if (!reminder.isActive) return null;

  final today = _dateOnly(now ?? DateTime.now());
  final anchor = _dateOnly(reminder.firstDueDate);
  final lastHandled = latestHandledBillReminderDueDate(reminder);
  switch (normalizeBillReminderRecurrence(reminder.recurrence)) {
    case billReminderRecurrenceNone:
      if (lastHandled != null && !lastHandled.isBefore(anchor)) {
        return null;
      }
      return anchor;
    case billReminderRecurrenceDaily:
      if (anchor.isAfter(today)) {
        return anchor;
      }
      if (lastHandled != null && !lastHandled.isBefore(today)) {
        return today.add(const Duration(days: 1));
      }
      return today;
    case billReminderRecurrenceWeekly:
      final currentWeekDue = weeklyDueDate(anchor, today);
      if (anchor.isAfter(currentWeekDue)) {
        return anchor;
      }
      if (lastHandled != null && !lastHandled.isBefore(currentWeekDue)) {
        return nextWeeklyDueDate(currentWeekDue);
      }
      return currentWeekDue;
    case billReminderRecurrenceYearly:
      final currentYearDue = yearlyDueDate(anchor, today.year);
      if (anchor.isAfter(currentYearDue)) {
        return anchor;
      }
      if (lastHandled != null && !lastHandled.isBefore(currentYearDue)) {
        return nextYearlyDueDate(anchor, currentYearDue);
      }
      return currentYearDue;
    case billReminderRecurrenceMonthly:
    default:
      final currentMonthDue = monthlyDueDate(anchor, today.year, today.month);
      if (anchor.isAfter(currentMonthDue)) {
        return anchor;
      }
      if (lastHandled != null && !lastHandled.isBefore(currentMonthDue)) {
        return nextMonthlyDueDate(anchor, currentMonthDue);
      }
      return currentMonthDue;
  }
}

DateTime? nextSchedulableBillReminderDueDate(
  BillReminderRecord reminder, {
  DateTime? now,
}) {
  return billReminderDueDateForList(reminder, now: now);
}

BillReminderStatus billReminderStatusForDueDate(
  DateTime dueDate, {
  DateTime? now,
  int dueSoonWindowDays = 7,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final normalizedDueDate = _dateOnly(dueDate);
  if (normalizedDueDate.isBefore(today)) {
    return BillReminderStatus.overdue;
  }
  final dueSoonThreshold = today.add(Duration(days: dueSoonWindowDays));
  if (!normalizedDueDate.isAfter(dueSoonThreshold)) {
    return BillReminderStatus.dueSoon;
  }
  return BillReminderStatus.upcoming;
}

BillReminderOccurrence? billReminderOccurrenceForList(
  BillReminderRecord reminder, {
  DateTime? now,
}) {
  final dueDate = billReminderDueDateForList(reminder, now: now);
  if (dueDate == null) return null;
  return BillReminderOccurrence(
    reminder: reminder,
    dueDate: dueDate,
    status: billReminderStatusForDueDate(dueDate, now: now),
  );
}

DateTime dueSoonNotificationDateTime(DateTime dueDate, int remindDaysBefore) {
  final date = _dateOnly(dueDate).subtract(Duration(days: remindDaysBefore));
  return DateTime(date.year, date.month, date.day, 9);
}

DateTime dueDateNotificationDateTime(DateTime dueDate) {
  final date = _dateOnly(dueDate);
  return DateTime(date.year, date.month, date.day, 9);
}

double upcomingBillsTotal(Iterable<BillReminderOccurrence> reminders) {
  return reminders.fold<double>(
    0,
    (sum, occurrence) => sum + occurrence.reminder.amount,
  );
}

DateTime? latestHandledBillReminderDueDate(BillReminderRecord reminder) {
  final lastPaid = reminder.lastPaidDueDate == null
      ? null
      : _dateOnly(reminder.lastPaidDueDate!);
  final lastSkipped = reminder.lastSkippedDueDate == null
      ? null
      : _dateOnly(reminder.lastSkippedDueDate!);
  if (lastPaid == null) return lastSkipped;
  if (lastSkipped == null) return lastPaid;
  return lastPaid.isAfter(lastSkipped) ? lastPaid : lastSkipped;
}

double _parseDouble(Object? value) {
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
