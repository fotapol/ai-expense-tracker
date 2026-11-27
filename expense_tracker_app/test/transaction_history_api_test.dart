import 'dart:convert';

import 'package:expense_tracker_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/authenticated_api.dart';

http.Response _backendResponse(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: {'expense-amount-filter': 'display-v1'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installAuthenticatedApiUser);

  test(
    'an older backend cannot silently ignore displayed amount bounds',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.listTransactions(minAmount: '5', page: 1),
            throwsStateError,
          );
        },
        () => MockClient(
          (_) async => http.Response('[{"id":"outside-range"}]', 200),
        ),
      );
    },
  );

  test('existing callers load every page and preserve filters', () async {
    final requests = <http.Request>[];
    final result = await http.runWithClient(
      () => ApiClient.listTransactions(
        merchantNameSearch: 'A & B',
        search: '50% milk & coffee_\\',
        minAmount: '-0.25',
        maxAmount: '99.99',
        currency: 'EUR',
        source: 'MANUAL',
        status: 'CONFIRMED',
        categoryIds: ['category'],
        needsReview: true,
        sortBy: 'oldest',
        pageSize: 50,
      ),
      () => MockClient((request) async {
        requests.add(request);
        final page = int.parse(request.url.queryParameters['page']!);
        return _backendResponse(
          jsonEncode([
            for (var i = (page - 1) * 50; i < page * 50 && i < 125; i++)
              {'id': i},
          ]),
          200,
        );
      }),
    );
    expect(result.map((row) => row['id']), List.generate(125, (i) => i));
    expect(requests.map((r) => r.url.queryParameters['page']), ['1', '2', '3']);
    for (final request in requests) {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['merchant_name_search'], 'A & B');
      expect(request.url.queryParameters['category_ids'], 'category');
      expect(request.url.queryParameters['search'], '50% milk & coffee_\\');
      expect(request.url.queryParameters['min_display_amount'], '-0.25');
      expect(request.url.queryParameters['max_display_amount'], '99.99');
      expect(request.url.queryParameters['currency'], 'EUR');
      expect(request.url.queryParameters['source'], 'MANUAL');
      expect(request.url.queryParameters['status'], 'CONFIRMED');
      expect(request.url.queryParameters['sort_by'], 'oldest');
      expect(request.url.queryParameters['needs_review'], 'true');
    }
  });

  test('explicit page fetches only that page, even when full', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        final rows = await ApiClient.listTransactions(page: 2, pageSize: 50);
        expect(rows, hasLength(50));
      },
      () => MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['page'], '2');
        return _backendResponse(
          jsonEncode(List.generate(50, (i) => {'id': i})),
          200,
        );
      }),
    );
    expect(calls, 1);
  });

  test(
    'a failed later page never returns an incomplete history as success',
    () async {
      await http.runWithClient(
        () => expectLater(
          ApiClient.listTransactions(pageSize: 1),
          throwsA(isA<Exception>()),
        ),
        () => MockClient((request) async {
          return request.url.queryParameters['page'] == '1'
              ? _backendResponse('[{"id": 1}]', 200)
              : _backendResponse('unavailable', 503);
        }),
      );
    },
  );
}
