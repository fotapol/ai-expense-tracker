import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/bill_reminder_notification_service.dart';
import '../core/launch_error_copy.dart';
import '../core/planning_logic.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class BillRemindersScreen extends StatefulWidget {
  const BillRemindersScreen({super.key});

  @override
  State<BillRemindersScreen> createState() => _BillRemindersScreenState();
}

class _BillRemindersScreenState extends State<BillRemindersScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = true;
  bool _isCreating = false;
  bool _showComposer = false;
  bool _showHistoryMode = false;
  _BillHistorySort _historySort = _BillHistorySort.latestPaidAt;
  String? _savingBillId;
  String? _deletingBillId;
  String? _error;
  String _currency = 'EUR';
  String _selectedRecurrence = billReminderRecurrenceMonthly;
  DateTime? _selectedDueDate = DateTime.now();
  List<BillReminderRecord> _reminders = <BillReminderRecord>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        ApiClient.listBillReminders(),
        ApiClient.getMe(),
      ]);
      final rawReminders = results[0] as List<dynamic>;
      final me = results[1] as Map<String, dynamic>;
      final reminders = rawReminders
          .whereType<Map<String, dynamic>>()
          .map(BillReminderRecord.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _reminders = reminders;
        _currency = (me['default_currency']?.toString() ?? 'EUR').toUpperCase();
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback:
              'Bill reminders could not load right now. Pull to try again.',
        );
        _isLoading = false;
      });
    }
  }

  List<BillReminderOccurrence> _upcomingOccurrences() {
    final now = DateTime.now();
    final items = _reminders
        .map((reminder) => billReminderOccurrenceForList(reminder, now: now))
        .whereType<BillReminderOccurrence>()
        .toList();
    items.sort((left, right) {
      final statusOrder = _statusWeight(
        left.status,
      ).compareTo(_statusWeight(right.status));
      if (statusOrder != 0) return statusOrder;
      return left.dueDate.compareTo(right.dueDate);
    });
    return items;
  }

  List<BillReminderOccurrence> _paidHistoryOccurrences() {
    final items = _reminders
        .where((reminder) => reminder.lastPaidDueDate != null)
        .map(
          (reminder) => BillReminderOccurrence(
            reminder: reminder,
            dueDate: reminder.lastPaidDueDate!,
            status: BillReminderStatus.upcoming,
          ),
        )
        .toList();
    switch (_historySort) {
      case _BillHistorySort.latestPaidAt:
        items.sort(
          (left, right) => _historyPaidMoment(
            right.reminder,
          ).compareTo(_historyPaidMoment(left.reminder)),
        );
        break;
      case _BillHistorySort.earliestPaidAt:
        items.sort(
          (left, right) => _historyPaidMoment(
            left.reminder,
          ).compareTo(_historyPaidMoment(right.reminder)),
        );
        break;
      case _BillHistorySort.latestDueDate:
        items.sort((left, right) => right.dueDate.compareTo(left.dueDate));
        break;
      case _BillHistorySort.earliestDueDate:
        items.sort((left, right) => left.dueDate.compareTo(right.dueDate));
        break;
    }
    return items;
  }

  int _statusWeight(BillReminderStatus status) {
    switch (status) {
      case BillReminderStatus.overdue:
        return 0;
      case BillReminderStatus.dueSoon:
        return 1;
      case BillReminderStatus.upcoming:
        return 2;
    }
  }

  String _formatAmount(double amount) {
    final symbol = CurrencyDisplay.symbolForCode(_currency);
    final prefix = symbol == _currency ? '${_currency.toUpperCase()} ' : symbol;
    return amount % 1 == 0
        ? '$prefix${amount.toStringAsFixed(0)}'
        : '$prefix${amount.toStringAsFixed(2)}';
  }

  String _statusLabel(BillReminderStatus status) {
    switch (status) {
      case BillReminderStatus.upcoming:
        return context.tr('bill_reminders_upcoming');
      case BillReminderStatus.dueSoon:
        return context.tr('bill_reminders_due_soon');
      case BillReminderStatus.overdue:
        return context.tr('bill_reminders_overdue');
    }
  }

  String _recurrenceLabel(String recurrence) {
    switch (normalizeBillReminderRecurrence(recurrence)) {
      case billReminderRecurrenceNone:
        return 'One-time';
      case billReminderRecurrenceDaily:
        return context.tr('bill_reminders_recurring_daily');
      case billReminderRecurrenceWeekly:
        return 'Weekly';
      case billReminderRecurrenceYearly:
        return context.tr('bill_reminders_recurring_yearly');
      case billReminderRecurrenceMonthly:
      default:
        return context.tr('bill_reminders_recurring_monthly');
    }
  }

  String _dueDateFieldLabel() {
    return 'Next due date';
  }

  String _dueDateFieldHint() {
    return 'Pick next due date';
  }

  String _historySortLabel(_BillHistorySort sort) {
    switch (sort) {
      case _BillHistorySort.latestPaidAt:
        return 'Latest paid';
      case _BillHistorySort.earliestPaidAt:
        return 'Earliest paid';
      case _BillHistorySort.latestDueDate:
        return 'Latest due';
      case _BillHistorySort.earliestDueDate:
        return 'Earliest due';
    }
  }

  String _historySubtitle() {
    switch (_historySort) {
      case _BillHistorySort.latestPaidAt:
        return 'Sorted by when reminders were marked as paid most recently.';
      case _BillHistorySort.earliestPaidAt:
        return 'Sorted by the oldest recorded payment time first.';
      case _BillHistorySort.latestDueDate:
        return 'Sorted by the latest due date that was paid.';
      case _BillHistorySort.earliestDueDate:
        return 'Sorted by the earliest due date that was paid.';
    }
  }

  DateTime _historyPaidMoment(BillReminderRecord reminder) {
    return reminder.lastPaidAt ??
        reminder.updatedAt ??
        DateTime(
          reminder.lastPaidDueDate!.year,
          reminder.lastPaidDueDate!.month,
          reminder.lastPaidDueDate!.day,
        );
  }

  Color _statusColor(BillReminderStatus status) {
    switch (status) {
      case BillReminderStatus.upcoming:
        return ShellColors.softBlue;
      case BillReminderStatus.dueSoon:
        return ShellColors.gold;
      case BillReminderStatus.overdue:
        return ShellColors.softRed;
    }
  }

  Future<void> _pickDueDate() async {
    final initialDate = _selectedDueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (dialogContext, child) =>
          ShellStyles.clampOverlayScale(dialogContext, child!),
    );
    if (picked == null) return;
    setState(() => _selectedDueDate = picked);
  }

  void _toggleComposer() {
    setState(() {
      _showHistoryMode = false;
      _showComposer = !_showComposer;
      if (!_showComposer) {
        _nameController.clear();
        _amountController.clear();
        _selectedRecurrence = billReminderRecurrenceMonthly;
        _selectedDueDate = DateTime.now();
      }
    });
  }

  void _toggleHistoryMode() {
    setState(() {
      _showHistoryMode = !_showHistoryMode;
      if (_showHistoryMode) {
        _showComposer = false;
        _historySort = _BillHistorySort.latestPaidAt;
      }
    });
  }

  void _handleBackNavigation() {
    if (_showHistoryMode) {
      setState(() => _showHistoryMode = false);
      return;
    }
    if (_showComposer) {
      _toggleComposer();
    }
  }

  Future<void> _createReminder() async {
    if (_isCreating) return;
    final name = _nameController.text.trim();
    final amount = _parseAmount(_amountController.text);
    if (name.isEmpty ||
        amount == null ||
        amount <= 0 ||
        _selectedDueDate == null) {
      _showMessage(context.tr('bill_reminders_invalid_form'), isError: true);
      return;
    }

    setState(() => _isCreating = true);
    try {
      await ApiClient.createBillReminder(
        name: name,
        amount: amount,
        currency: _currency,
        recurrence: _selectedRecurrence,
        firstDueDate: _selectedDueDate!,
      );
      await BillReminderNotificationService.instance.requestPermissions();
      await BillReminderNotificationService.instance
          .syncScheduledNotifications();
      if (!mounted) return;
      setState(() {
        _showComposer = false;
        _nameController.clear();
        _amountController.clear();
        _selectedRecurrence = billReminderRecurrenceMonthly;
        _selectedDueDate = DateTime.now();
      });
      await _loadData(showLoader: false);
      if (!mounted) return;
      _showMessage(context.tr('bill_reminders_saved'));
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      _showMessage(
        friendlyLaunchErrorMessage(
          error,
          fallback: 'Bill reminder could not be saved right now.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _markAsPaid(BillReminderOccurrence occurrence) async {
    if (_savingBillId != null || _deletingBillId != null) return;
    setState(() => _savingBillId = occurrence.reminder.id);
    try {
      await ApiClient.markBillReminderPaid(
        billId: occurrence.reminder.id,
        dueDate: occurrence.dueDate,
      );
      await BillReminderNotificationService.instance
          .syncScheduledNotifications();
      await _loadData(showLoader: false);
      if (!mounted) return;
      _showMessage(context.tr('bill_reminders_paid'));
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (await _recoverUnavailableReminder(error)) return;
      if (!mounted) return;
      _showMessage(
        friendlyLaunchErrorMessage(
          error,
          fallback: 'That bill could not be updated right now.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _savingBillId = null);
    }
  }

  bool _isRecurring(BillReminderRecord reminder) {
    return normalizeBillReminderRecurrence(reminder.recurrence) !=
        billReminderRecurrenceNone;
  }

  bool _isReminderMissingError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('bill reminder not found') ||
        raw.contains(': 404') ||
        raw.contains(' 404');
  }

  Future<bool> _recoverUnavailableReminder(Object error) async {
    if (!_isReminderMissingError(error)) return false;
    await _loadData(showLoader: false);
    if (!mounted) return true;
    _showMessage('This reminder is no longer available.', isError: true);
    return true;
  }

  Future<_ReminderDeleteAction?> _confirmReminderDelete(
    BillReminderOccurrence occurrence,
  ) async {
    final reminder = occurrence.reminder;
    if (!_isRecurring(reminder)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ShellStyles.clampOverlayScale(
          dialogContext,
          AlertDialog(
            title: Text(context.tr('delete_reminder')),
            content: Text(
              'Delete "${reminder.name}"?',
              style: TextStyle(
                color: ShellStyles.textPrimary(dialogContext),
                height: 1.35,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(context.tr('common_cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: ShellColors.softRed,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      );
      return confirmed == true ? _ReminderDeleteAction.deleteSeries : null;
    }

    return showDialog<_ReminderDeleteAction>(
      context: context,
      builder: (dialogContext) => ShellStyles.clampOverlayScale(
        dialogContext,
        AlertDialog(
          title: Text(context.tr('remove_reminder')),
          content: Text(
            'Choose whether to remove only the next due reminder or the whole recurring series.',
            style: TextStyle(
              color: ShellStyles.textPrimary(dialogContext),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('common_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _ReminderDeleteAction.skipOccurrence,
              ),
              style: TextButton.styleFrom(foregroundColor: ShellColors.softRed),
              child: Text(context.tr('remove_this_reminder')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _ReminderDeleteAction.deleteSeries,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: ShellColors.softRed,
                foregroundColor: Colors.white,
              ),
              child: Text(context.tr('remove_all_in_series')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _skipReminderOccurrence(
    BillReminderOccurrence occurrence,
  ) async {
    if (_savingBillId != null || _deletingBillId != null) return;
    setState(() => _deletingBillId = occurrence.reminder.id);
    try {
      await ApiClient.skipBillReminder(
        billId: occurrence.reminder.id,
        dueDate: occurrence.dueDate,
      );
      await BillReminderNotificationService.instance
          .syncScheduledNotifications();
      await _loadData(showLoader: false);
      if (!mounted) return;
      _showMessage('The next reminder was removed from this series.');
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (await _recoverUnavailableReminder(error)) return;
      if (!mounted) return;
      _showMessage(
        friendlyLaunchErrorMessage(
          error,
          fallback: 'That reminder could not be updated right now.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _deletingBillId = null);
    }
  }

  Future<void> _deleteReminderSeries(BillReminderRecord reminder) async {
    if (_savingBillId != null || _deletingBillId != null) return;
    setState(() => _deletingBillId = reminder.id);
    try {
      await ApiClient.deleteBillReminder(reminder.id);
      await BillReminderNotificationService.instance
          .syncScheduledNotifications();
      await _loadData(showLoader: false);
      if (!mounted) return;
      _showMessage('Reminder series removed.');
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (await _recoverUnavailableReminder(error)) return;
      if (!mounted) return;
      _showMessage(
        friendlyLaunchErrorMessage(
          error,
          fallback: 'That reminder could not be deleted right now.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _deletingBillId = null);
    }
  }

  Future<void> _handleDeleteAction(BillReminderOccurrence occurrence) async {
    final action = await _confirmReminderDelete(occurrence);
    if (action == null || !mounted) return;
    switch (action) {
      case _ReminderDeleteAction.skipOccurrence:
        await _skipReminderOccurrence(occurrence);
      case _ReminderDeleteAction.deleteSeries:
        await _deleteReminderSeries(occurrence.reminder);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? ShellColors.softRed : null,
      ),
    );
  }

  double? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  Widget _buildSummaryCard(List<BillReminderOccurrence> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShellStyles.heroCardDecoration(context, radius: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ShellStyles.heroBadgeSurface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ShellStyles.heroBadgeBorder(context)),
            ),
            child: Icon(
              AppIcons.notifications,
              color: ShellStyles.heroBadgeIcon(context),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('bill_reminders_total_upcoming'),
                style: TextStyle(
                  color: ShellStyles.heroTextSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatAmount(upcomingBillsTotal(items)),
                style: TextStyle(
                  color: ShellStyles.heroTextPrimary(context),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                items.isEmpty
                    ? 'No upcoming reminders'
                    : '${items.length} upcoming reminder${items.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: ShellStyles.heroTextSecondary(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerCard() {
    final dateText = _selectedDueDate == null
        ? _dueDateFieldHint()
        : DateFormat.yMMMd().format(_selectedDueDate!);
    final accentTone = ShellStyles.accentTone(context);

    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add bill reminder',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose when this bill is due next and whether it repeats.',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Bill name',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              hintText: context.tr('bill_reminders_name_hint'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('bill_reminders_amount'),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixText: '${CurrencyDisplay.symbolForCode(_currency)} ',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pickDueDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: _dueDateFieldLabel(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    child: Text(
                      dateText,
                      style: TextStyle(
                        color: _selectedDueDate == null
                            ? ShellStyles.textMuted(context)
                            : ShellStyles.textPrimary(context),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Recurrence',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final recurrence in <String>[
                  billReminderRecurrenceNone,
                  billReminderRecurrenceDaily,
                  billReminderRecurrenceWeekly,
                  billReminderRecurrenceMonthly,
                  billReminderRecurrenceYearly,
                ])
                  ChoiceChip(
                    label: Text(_recurrenceLabel(recurrence)),
                    selected: _selectedRecurrence == recurrence,
                    showCheckmark: false,
                    backgroundColor: ShellStyles.surface(context),
                    selectedColor: accentTone.container,
                    side: BorderSide(
                      color: _selectedRecurrence == recurrence
                          ? accentTone.border
                          : ShellStyles.border(context),
                    ),
                    labelStyle: TextStyle(
                      color: _selectedRecurrence == recurrence
                          ? accentTone.foreground
                          : ShellStyles.textMuted(context),
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: _isCreating
                        ? null
                        : (_) {
                            setState(() {
                              _selectedRecurrence = recurrence;
                            });
                          },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isCreating ? null : _createReminder,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('bill_reminders_add_action')),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _isCreating ? null : _toggleComposer,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(context.tr('common_cancel')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(
    BillReminderOccurrence occurrence, {
    bool isHistory = false,
  }) {
    final statusColor = isHistory
        ? ShellColors.softGreen
        : _statusColor(occurrence.status);
    final isSaving = _savingBillId == occurrence.reminder.id;
    final isDeleting = _deletingBillId == occurrence.reminder.id;
    final isBusy = isSaving || isDeleting;
    final borderColor = isHistory
        ? ShellStyles.border(context)
        : occurrence.isOverdue
        ? ShellColors.softRed.withAlpha(90)
        : ShellStyles.border(context);
    final statusLabel = isHistory ? 'Paid' : _statusLabel(occurrence.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHistory
            ? ShellStyles.surfaceAlt(context)
            : ShellStyles.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  occurrence.reminder.name,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatAmount(occurrence.reminder.amount),
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!isHistory)
                IconButton(
                  onPressed: isBusy
                      ? null
                      : () => _handleDeleteAction(occurrence),
                  tooltip: 'Remove reminder',
                  icon: isDeleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ShellColors.softRed,
                          ),
                        )
                      : Icon(Icons.delete_outline, color: ShellColors.softRed),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withAlpha(60)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _recurrenceLabel(occurrence.reminder.recurrence),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: ShellStyles.textMuted(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isHistory ? 'Paid for due' : 'Next due'}: ${DateFormat.yMMMd().format(occurrence.dueDate)}',
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                    if (isHistory &&
                        occurrence.reminder.lastPaidAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Marked paid ${DateFormat.yMMMd().add_Hm().format(occurrence.reminder.lastPaidAt!)}',
                        style: TextStyle(
                          color: ShellStyles.textMuted(context),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isHistory) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: isBusy ? null : () => _markAsPaid(occurrence),
                  style: FilledButton.styleFrom(
                    backgroundColor: ShellColors.softGreen.withAlpha(18),
                    foregroundColor: ShellColors.softGreen,
                    elevation: 0,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 16),
                  label: Text(context.tr('bill_reminders_mark_paid')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ShellStyles.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistorySortButton() {
    return PopupMenuButton<_BillHistorySort>(
      initialValue: _historySort,
      onSelected: (value) => setState(() => _historySort = value),
      itemBuilder: (context) => _BillHistorySort.values.map((value) {
        return PopupMenuItem<_BillHistorySort>(
          value: value,
          child: Text(_historySortLabel(value)),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ShellStyles.border(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 16,
              color: ShellStyles.textPrimary(context),
            ),
            const SizedBox(width: 8),
            Text(
              _historySortLabel(_historySort),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(int count) {
    if (count == 1) {
      return context.tr('bill_reminders_subtitle_single');
    }
    return context.tr(
      'bill_reminders_subtitle_plural',
      params: {'count': count.toString()},
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcomingItems = _upcomingOccurrences();
    final paidItems = _paidHistoryOccurrences();
    final isShowingHistory = _showHistoryMode;
    final accentTone = ShellStyles.accentTone(context);

    return PopScope<bool>(
      canPop: !_showHistoryMode && !_showComposer,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: SettingsDetailScaffold(
        title: context.tr('tools_bill_reminders'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: _toggleHistoryMode,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(40, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    backgroundColor: isShowingHistory
                        ? accentTone.container
                        : ShellStyles.surface(context),
                    side: BorderSide(
                      color: isShowingHistory
                          ? accentTone.border
                          : ShellStyles.border(context),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Icon(
                    isShowingHistory
                        ? Icons.schedule_outlined
                        : Icons.history_outlined,
                    size: 18,
                    color: isShowingHistory
                        ? accentTone.foreground
                        : ShellStyles.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _toggleComposer,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _showComposer
                        ? context.tr('common_cancel')
                        : '+ ${context.tr('common_new')}',
                  ),
                ),
              ],
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ShellStyles.textPrimary(context)),
                  ),
                ),
              )
            : SafeArea(
                top: false,
                child: RefreshIndicator(
                  onRefresh: () => _loadData(showLoader: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      MediaQuery.of(context).padding.bottom + 32,
                    ),
                    children: [
                      if (!isShowingHistory) ...[
                        Text(
                          _subtitle(upcomingItems.length),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(upcomingItems),
                      ],
                      if (_showComposer) ...[
                        const SizedBox(height: 16),
                        _buildComposerCard(),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildSectionHeader(
                              isShowingHistory ? 'Paid history' : 'Upcoming',
                              subtitle: isShowingHistory
                                  ? _historySubtitle()
                                  : 'Sorted by the nearest due date and counted in the summary above.',
                            ),
                          ),
                          if (isShowingHistory && paidItems.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            _buildHistorySortButton(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!isShowingHistory && upcomingItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: ShellStyles.cardDecoration(
                            context,
                            radius: 18,
                            withShadow: false,
                          ),
                          child: Text(
                            context.tr('bill_reminders_empty'),
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: 12.5,
                            ),
                          ),
                        )
                      else if (!isShowingHistory)
                        ...upcomingItems.map((occurrence) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildReminderCard(occurrence),
                          );
                        }),
                      if (isShowingHistory && paidItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: ShellStyles.cardDecoration(
                            context,
                            radius: 18,
                            withShadow: false,
                          ),
                          child: Text(
                            'Paid reminders will appear here after you mark them as paid.',
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      if (isShowingHistory && paidItems.isNotEmpty) ...[
                        ...paidItems.map((occurrence) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildReminderCard(
                              occurrence,
                              isHistory: true,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

enum _BillHistorySort {
  latestPaidAt,
  earliestPaidAt,
  latestDueDate,
  earliestDueDate,
}

enum _ReminderDeleteAction { skipOccurrence, deleteSeries }
