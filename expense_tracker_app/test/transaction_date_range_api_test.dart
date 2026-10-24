import 'dart:convert';

import 'package:expense_tracker_app/core/api_client.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/authenticated_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installAuthenticatedApiUser);

  test(
    'every list, summary and drill-down request sends both UTC bounds and scope',
    () async {
      final range = PeriodFilter.getRange(
        PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026, 3, 28),
          end: DateTime(2026, 3, 30),
        ),
      );
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await ApiClient.listTransactions(
            fromDate: range.start,
            toDate: range.end,
            merchantNameSearch: 'A & B',
            categoryIds: ['category'],
            subcategoryIds: ['subcategory'],
            labelIds: ['label'],
          );
          await ApiClient.getTransactionsSummary(
            fromDate: range.start,
            toDate: range.end,
            categoryIds: ['category'],
            subcategoryIds: ['subcategory'],
            labelIds: ['label'],
          );
          await ApiClient.getTransactionTrendSummary(
            fromDate: range.start,
            toDate: range.end,
            categoryIds: ['category'],
            subcategoryIds: ['subcategory'],
            labelIds: ['label'],
          );
          await ApiClient.getCategorySubcategorySummary(
            categoryId: 'category',
            fromDate: range.start,
            toDate: range.end,
            categoryIds: ['category'],
            subcategoryIds: ['subcategory'],
            labelIds: ['label'],
          );
          await ApiClient.getSubcategoryItemsSummary(
            subcategoryId: 'subcategory',
            fromDate: range.start,
            toDate: range.end,
            categoryIds: ['category'],
            subcategoryIds: ['subcategory'],
            labelIds: ['label'],
          );
        },
        () => MockClient((request) async {
          requests.add(request);
          return http.Response(
            request.url.path == '/v1/transactions' ? '[]' : '{}',
            200,
          );
        }),
      );
      expect(requests, hasLength(5));
      for (final request in requests) {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(
          request.url.queryParameters['from_occurred_at'],
          range.start!.toUtc().toIso8601String(),
        );
        expect(
          request.url.queryParameters['to_occurred_at'],
          range.end!.toUtc().toIso8601String(),
        );
        expect(request.url.queryParameters['category_ids'], 'category');
        expect(request.url.queryParameters['subcategory_ids'], 'subcategory');
        expect(request.url.queryParameters['label_ids'], 'label');
      }
      expect(
        requests.first.url.queryParameters['merchant_name_search'],
        'A & B',
      );
    },
  );

  test(
    'the receipt request includes boundary transactions and excludes adjacent dates',
    () async {
      final range = PeriodFilter.getRange(
        PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026, 1, 10),
          end: DateTime(2026, 1, 12),
        ),
      );
      final dates = [
        range.start!.subtract(const Duration(microseconds: 1)),
        range.start!,
        DateTime(2026, 1, 11),
        range.end!,
        range.end!.add(const Duration(microseconds: 1)),
      ];
      final results = await http.runWithClient(
        () => ApiClient.listTransactions(
          fromDate: range.start,
          toDate: range.end,
        ),
        () => MockClient((request) async {
          final from = DateTime.parse(
            request.url.queryParameters['from_occurred_at']!,
          );
          final to = DateTime.parse(
            request.url.queryParameters['to_occurred_at']!,
          );
          final matches = [
            for (var index = 0; index < dates.length; index++)
              if (!dates[index].isBefore(from) && !dates[index].isAfter(to))
                {'id': index},
          ];
          return http.Response(jsonEncode(matches), 200);
        }),
      );
      expect(results.map((row) => row['id']), [1, 2, 3]);
    },
  );

  test('omitting optional bounds preserves existing client callers', () async {
    await http.runWithClient(
      () => ApiClient.listTransactions(),
      () => MockClient((request) async {
        expect(
          request.url.queryParameters.containsKey('from_occurred_at'),
          isFalse,
        );
        expect(
          request.url.queryParameters.containsKey('to_occurred_at'),
          isFalse,
        );
        return http.Response('[]', 200);
      }),
    );
  });
}
