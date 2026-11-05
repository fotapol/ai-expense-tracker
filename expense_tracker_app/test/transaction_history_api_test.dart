import 'dart:convert';

import 'package:expense_tracker_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/authenticated_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installAuthenticatedApiUser);

  test('existing callers load every page and preserve filters', () async {
    final requests = <http.Request>[];
    final result = await http.runWithClient(
      () => ApiClient.listTransactions(
        merchantNameSearch: 'A & B',
        categoryIds: ['category'],
        needsReview: true,
        sortBy: 'oldest',
        pageSize: 50,
      ),
      () => MockClient((request) async {
        requests.add(request);
        final page = int.parse(request.url.queryParameters['page']!);
        return http.Response(
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
        return http.Response(
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
              ? http.Response('[{"id": 1}]', 200)
              : http.Response('unavailable', 503);
        }),
      );
    },
  );
}
