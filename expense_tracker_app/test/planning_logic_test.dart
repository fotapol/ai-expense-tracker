import 'package:expense_tracker_app/core/planning_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildBudgetOverview', () {
    test('computes totals, remaining, and savings goal', () {
      final overview = buildBudgetOverview(
        monthlyIncome: 5000,
        totalSpent: 1180,
        categories: const [
          BudgetCategoryProgress(
            categoryId: 'food',
            categoryCode: 'food',
            categoryName: 'Food',
            limitAmount: 600,
            spentAmount: 450,
          ),
          BudgetCategoryProgress(
            categoryId: 'transport',
            categoryCode: 'transport',
            categoryName: 'Transport',
            limitAmount: 300,
            spentAmount: 200,
          ),
          BudgetCategoryProgress(
            categoryId: 'shopping',
            categoryCode: 'shopping',
            categoryName: 'Shopping',
            limitAmount: 400,
            spentAmount: 300,
          ),
          BudgetCategoryProgress(
            categoryId: 'entertainment',
            categoryCode: 'entertainment',
            categoryName: 'Entertainment',
            limitAmount: 200,
            spentAmount: 150,
          ),
          BudgetCategoryProgress(
            categoryId: 'healthcare',
            categoryCode: 'healthcare',
            categoryName: 'Healthcare',
            limitAmount: 150,
            spentAmount: 80,
          ),
        ],
      );

      expect(overview.totalBudget, 1650);
      expect(overview.totalSpent, 1180);
      expect(overview.remaining, 470);
      expect(overview.savingsGoal, 3350);
      expect(overview.isOverBudget, isFalse);
    });

    test(
      'marks categories and overview as exceeded when spend is too high',
      () {
        const category = BudgetCategoryProgress(
          categoryId: 'food',
          categoryCode: 'food',
          categoryName: 'Food',
          limitAmount: 300,
          spentAmount: 420,
        );

        final overview = buildBudgetOverview(
          monthlyIncome: 1000,
          totalSpent: 420,
          categories: const [category],
        );

        expect(category.isExceeded, isTrue);
        expect(category.remainingAmount, -120);
        expect(category.progress, 1);
        expect(overview.isOverBudget, isTrue);
        expect(overview.remaining, -120);
      },
    );
  });

  group('bill reminders', () {
    final now = DateTime(2026, 3, 23);

    BillReminderRecord buildReminder({
      DateTime? firstDueDate,
      DateTime? lastPaidDueDate,
      bool isActive = true,
    }) {
      return BillReminderRecord(
        id: 'bill-1',
        name: 'Rent',
        amount: 1500,
        currency: 'USD',
        firstDueDate: firstDueDate ?? DateTime(2026, 1, 5),
        lastPaidDueDate: lastPaidDueDate,
        remindDaysBefore: 3,
        isActive: isActive,
      );
    }

    test('classifies overdue, due soon, and upcoming bills', () {
      expect(
        billReminderStatusForDueDate(DateTime(2026, 3, 22), now: now),
        BillReminderStatus.overdue,
      );
      expect(
        billReminderStatusForDueDate(DateTime(2026, 3, 30), now: now),
        BillReminderStatus.dueSoon,
      );
      expect(
        billReminderStatusForDueDate(DateTime(2026, 4, 1), now: now),
        BillReminderStatus.upcoming,
      );
    });

    test('marking current cycle as paid hides it until next month', () {
      final reminder = buildReminder(lastPaidDueDate: DateTime(2026, 3, 5));

      expect(billReminderOccurrenceForList(reminder, now: now), isNull);
      expect(
        nextSchedulableBillReminderDueDate(reminder, now: now),
        DateTime(2026, 4, 5),
      );
      expect(
        billReminderOccurrenceForList(
          reminder,
          now: DateTime(2026, 4, 1),
        )?.dueDate,
        DateTime(2026, 4, 5),
      );
    });

    test('monthly due dates clamp to shorter months', () {
      final reminder = buildReminder(
        firstDueDate: DateTime(2026, 1, 31),
        lastPaidDueDate: DateTime(2026, 2, 28),
      );

      expect(
        nextSchedulableBillReminderDueDate(
          reminder,
          now: DateTime(2026, 2, 15),
        ),
        DateTime(2026, 3, 31),
      );
      expect(
        monthlyDueDate(reminder.firstDueDate, 2026, 4),
        DateTime(2026, 4, 30),
      );
    });

    test('notification times are scheduled for 9 AM local time', () {
      final dueDate = DateTime(2026, 4, 5);

      expect(dueSoonNotificationDateTime(dueDate, 3), DateTime(2026, 4, 2, 9));
      expect(dueDateNotificationDateTime(dueDate), DateTime(2026, 4, 5, 9));
    });

    test('upcoming total sums visible reminder amounts', () {
      final occurrences = [
        billReminderOccurrenceForList(buildReminder(), now: now)!,
        BillReminderOccurrence(
          reminder: BillReminderRecord(
            id: 'bill-2',
            name: 'Internet',
            amount: 79.99,
            currency: 'USD',
            firstDueDate: DateTime(2026, 1, 25),
            remindDaysBefore: 3,
            isActive: true,
          ),
          dueDate: DateTime(2026, 3, 25),
          status: BillReminderStatus.dueSoon,
        ),
      ];

      expect(upcomingBillsTotal(occurrences), closeTo(1579.99, 0.0001));
    });
  });
}
