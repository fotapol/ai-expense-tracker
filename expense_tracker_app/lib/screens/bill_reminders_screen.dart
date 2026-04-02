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
  String? _savingBillId;
  String? _error;
  String _currency = 'EUR';
  String _selectedRecurrence = billReminderRecurrenceMonthly;
  DateTime? _selectedDueDate;
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

  List<BillReminderOccurrence> _visibleOccurrences() {
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
      case billReminderRecurrenceDaily:
        return context.tr('bill_reminders_recurring_daily');
      case billReminderRecurrenceYearly:
        return context.tr('bill_reminders_recurring_yearly');
      case billReminderRecurrenceMonthly:
      default:
        return context.tr('bill_reminders_recurring_monthly');
    }
  }

  String _dueDateFieldLabel() {
    return _selectedRecurrence == billReminderRecurrenceDaily
        ? context.tr('bill_reminders_start_date')
        : context.tr('bill_reminders_first_due_date');
  }

  String _dueDateFieldHint() {
    return _selectedRecurrence == billReminderRecurrenceDaily
        ? context.tr('bill_reminders_pick_start_date')
        : context.tr('bill_reminders_pick_first_due_date');
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
    );
    if (picked == null) return;
    setState(() => _selectedDueDate = picked);
  }

  void _toggleComposer() {
    setState(() {
      _showComposer = !_showComposer;
      if (!_showComposer) {
        _nameController.clear();
        _amountController.clear();
        _selectedRecurrence = billReminderRecurrenceMonthly;
        _selectedDueDate = null;
      }
    });
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
        _selectedDueDate = null;
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
    if (_savingBillId != null) return;
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1B), Color(0xFF313131)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(AppIcons.notifications, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('bill_reminders_total_upcoming'),
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatAmount(upcomingBillsTotal(items)),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
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

    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('bill_reminders_add_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: context.tr('bill_reminders_name_hint'),
              hintStyle: TextStyle(color: ShellStyles.textMuted(context)),
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
              labelText: context.tr('bill_reminders_recurring'),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final recurrence in <String>[
                  billReminderRecurrenceDaily,
                  billReminderRecurrenceMonthly,
                  billReminderRecurrenceYearly,
                ])
                  ChoiceChip(
                    label: Text(_recurrenceLabel(recurrence)),
                    selected: _selectedRecurrence == recurrence,
                    showCheckmark: false,
                    backgroundColor: ShellStyles.surface(context),
                    selectedColor: ShellStyles.surfaceAlt(context),
                    side: BorderSide(color: ShellStyles.border(context)),
                    labelStyle: TextStyle(
                      color: _selectedRecurrence == recurrence
                          ? ShellStyles.textPrimary(context)
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
                    backgroundColor: ShellStyles.textPrimary(context),
                    foregroundColor: ShellStyles.surface(context),
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

  Widget _buildReminderCard(BillReminderOccurrence occurrence) {
    final statusColor = _statusColor(occurrence.status);
    final isSaving = _savingBillId == occurrence.reminder.id;
    final borderColor = occurrence.isOverdue
        ? ShellColors.softRed.withAlpha(90)
        : ShellStyles.border(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShellStyles.surface(context),
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
                  _statusLabel(occurrence.status),
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
                child: Text(
                  DateFormat.yMMMd().format(occurrence.dueDate),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: isSaving ? null : () => _markAsPaid(occurrence),
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
          ),
        ],
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
    final visibleItems = _visibleOccurrences();

    return SettingsDetailScaffold(
      title: context.tr('tools_bill_reminders'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: FilledButton(
              onPressed: _toggleComposer,
              style: FilledButton.styleFrom(
                backgroundColor: ShellStyles.textPrimary(context),
                foregroundColor: ShellStyles.surface(context),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(
                _showComposer
                    ? context.tr('common_cancel')
                    : '+ ${context.tr('common_new')}',
              ),
            ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    Text(
                      _subtitle(visibleItems.length),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryCard(visibleItems),
                    if (_showComposer) ...[
                      const SizedBox(height: 16),
                      _buildComposerCard(),
                    ],
                    const SizedBox(height: 16),
                    if (visibleItems.isEmpty)
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
                    else
                      ...visibleItems.map((occurrence) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildReminderCard(occurrence),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}
