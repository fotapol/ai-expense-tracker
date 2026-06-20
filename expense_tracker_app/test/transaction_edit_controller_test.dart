import 'package:expense_tracker_app/screens/transaction_edit/transaction_edit_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionEditController', () {
    test('applies fetched transaction state and builds save payload', () {
      final controller = TransactionEditController()..transactionId = 'tx-1';
      addTearDown(controller.dispose);

      controller.applyTransactionState(
        txData: {
          'id': 'tx-1',
          'user_id': 'user-1',
          'receipt_id': 'receipt-1',
          'occurred_at': '2026-01-02T10:20:00.000',
          'amount_total': 10.0,
          'currency': 'EUR',
          'merchant_name': 'Market',
          'category_id': 'cat-1',
          'items': [
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'description': 'Milk',
              'amount': 10.0,
              'qty': 2,
              'unit_price': 6,
              'discount_amount': 2,
              'category_id': 'cat-2',
              'unit': 'pc',
            },
          ],
          'labels': [
            {'id': 'label-1', 'name': 'Groceries'},
          ],
          'extraction_warnings': ['line_total_mismatch'],
          'display_currency': 'RSD',
          'display_amount_total': 1170.0,
        },
        categories: const [],
        labels: const [],
        appLanguage: 'en',
        effectiveItemsLanguage: 'sr',
      );

      expect(controller.receiptId, 'receipt-1');
      expect(controller.merchantController.text, 'Market');
      expect(controller.selectedLabelIds, contains('label-1'));
      expect(controller.serverWarnings, hasLength(1));
      expect(controller.displayCurrency, 'RSD');
      expect(controller.toDisplayAmount(10), 1170);
      expect(controller.computeLineMismatches(), isEmpty);

      final payload = controller.buildSavePayload()!;
      expect(payload['merchant_name'], 'Market');
      expect(payload['amount_total'], 10.0);
      expect(payload['occurred_at'], '2026-01-02T10:20:00.000');

      final items = payload['items'] as List<dynamic>;
      expect(items, hasLength(1));
      expect(items.single['id'], '11111111-1111-4111-8111-111111111111');
      expect(items.single['discount_amount'], 2.0);
      expect(items.single['amount_before_discount'], 12.0);
    });

    test('keeps manual total until force-syncing to item subtotal', () {
      final controller = TransactionEditController()..transactionId = 'tx-1';
      addTearDown(controller.dispose);

      controller.applyTransactionState(
        txData: {
          'amount_total': 5.0,
          'currency': 'RSD',
          'items': [
            {'id': 'item-1', 'description': 'A', 'amount': 2.0},
            {'id': 'item-2', 'description': 'B', 'amount': 3.0},
          ],
          'labels': const [],
          'extraction_warnings': const [],
        },
        categories: const [],
        labels: const [],
        appLanguage: 'en',
        effectiveItemsLanguage: 'en',
      );

      controller.applyManualTotal(8);
      expect(controller.amountController.text, '8.00');
      expect(controller.hasManualTotalOverride, isTrue);

      controller.itemAmountControllers['item-1']!.text = '4.00';
      controller.syncTotalToItems();
      expect(controller.amountController.text, '8.00');

      controller.syncTotalToItems(force: true);
      expect(controller.amountController.text, '7.00');
      expect(controller.hasManualTotalOverride, isFalse);
    });

    test('builds draft payload while skipping blank draft items', () {
      final controller = TransactionEditController();
      addTearDown(controller.dispose);

      final blank = controller.buildDraftItem(id: 'blank');
      blank['qty'] = null;
      blank['unit_price'] = null;
      blank['unit'] = '';
      final filled = controller.buildDraftItem(id: 'local-1');
      filled['description'] = 'Bread';
      filled['amount'] = 4.5;

      controller.applyTransactionState(
        txData: {
          'amount_total': 4.5,
          'currency': 'RSD',
          'items': [blank, filled],
          'labels': const [],
          'extraction_warnings': const [],
        },
        categories: const [],
        labels: const [],
        appLanguage: 'en',
        effectiveItemsLanguage: 'en',
      );
      controller.itemUnits['blank'] = '';

      final payload = controller.buildSavePayload()!;
      final items = payload['items'] as List<dynamic>;

      expect(items, hasLength(1));
      expect(items.single['description'], 'Bread');
      expect(items.single['line_no'], 1);
      expect(items.single.containsKey('id'), isFalse);
    });

    test('tracks labels, receipt preview state, dates, and item removal', () {
      final controller = TransactionEditController();
      addTearDown(controller.dispose);

      controller.setLabelSelection(labelId: 'label-1', selected: true);
      controller.setLabelSelection(labelId: 'label-2', selected: true);
      controller.setLabelSelection(labelId: 'label-1', selected: false);
      controller.appendLabel({'id': 'label-3', 'name': 'Travel'});
      expect(controller.selectedLabelIds, {'label-2'});
      expect(controller.labels.single['name'], 'Travel');

      controller.beginReceiptPreviewLoad();
      expect(controller.isLoadingReceiptPreview, isTrue);
      controller.finishReceiptPreviewLoad('https://example.test/receipt.jpg');
      expect(controller.isLoadingReceiptPreview, isFalse);
      expect(controller.receiptPreviewUrl, contains('receipt.jpg'));
      controller.clearReceiptPreview();
      expect(controller.receiptPreviewUrl, isNull);

      controller.occurredAt = DateTime(2026, 1, 2, 9, 30);
      controller.applyOccurredDate(DateTime(2026, 2, 3));
      controller.applyOccurredTime(const TimeOfDay(hour: 14, minute: 45));
      expect(controller.occurredAt, DateTime(2026, 2, 3, 14, 45));

      final item = controller.buildDraftItem(id: 'item-1');
      controller.items.add(item);
      controller.syncItemControllersFromData(item);
      expect(controller.itemDescControllers, contains('item-1'));
      controller.removeItemLocally('item-1');
      expect(controller.items, isEmpty);
      expect(controller.itemDescControllers, isNot(contains('item-1')));
    });
  });
}
