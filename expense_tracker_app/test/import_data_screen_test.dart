import 'dart:convert';

import 'package:expense_tracker_app/screens/import_data_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'support/authenticated_api.dart';

void _pickFile(String name, Uint8List bytes) {
  const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (method) async {
    expect(method.method, 'any');
    return [
      {'name': name, 'bytes': bytes, 'size': bytes.length},
    ];
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Future<void> _chooseFile(WidgetTester tester) async {
  fixture.phone(tester, width: 360);
  await tester.pumpWidget(
    fixture.app(const ImportDataScreen(), systemText: 1.3),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose file'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(installAuthenticatedApiUser);

  testWidgets(
    'Money Manager is previewed before its normalized expenses are saved',
    (tester) async {
      final bytes = Uint8List.fromList([8, 8, 8]);
      _pickFile('example.mmbackup', bytes);
      const expense = {
        'uid': 'expense-1',
        'day': '2026-06-18',
        'currency': 'EUR',
        'description': 'Sample expense',
        'amount': '24.50',
      };
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await _chooseFile(tester);
          expect(requests, hasLength(1));
          expect(requests.single.bodyBytes, bytes);
          expect(
            requests.single.url.queryParameters['source'],
            'money_manager',
          );
          expect(find.text('Expenses to import'), findsOneWidget);
          expect(find.textContaining('Sample expense'), findsOneWidget);
          expect(find.text('Already imported'), findsOneWidget);
          final confirm = find.widgetWithText(FilledButton, 'Import Data');
          await tester.ensureVisible(confirm);
          await tester.tap(confirm);
          await tester.pumpAndSettle();

          expect(requests, hasLength(2));
          expect(requests.last.url.path, '/v1/data/external-import');
          final plan = jsonDecode(requests.last.body) as Map<String, dynamic>;
          final sent =
              (plan['expenses'] as List).single as Map<String, dynamic>;
          expect(sent['amount'], '24.50');
          expect(
            sent['utc_offset_minutes'],
            DateTime(2026, 6, 18, 12).timeZoneOffset.inMinutes,
          );
          expect(find.text('Imported expenses'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/preview')) {
            return http.Response(
              jsonEncode({
                'plan': {
                  'source': 'money_manager',
                  'categories': [],
                  'expenses': [expense],
                },
                'already_imported': 0,
                'skipped': 1,
                'totals': {'EUR': '24.50'},
                'samples': [expense],
              }),
              200,
            );
          }
          return http.Response('{"imported":1,"already_imported":0}', 201);
        }),
      );
    },
  );

  testWidgets('native JSON still goes to the existing import endpoint', (
    tester,
  ) async {
    const payload = {'version': 1, 'categories': [], 'transactions': []};
    _pickFile(
      'export.json',
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await _chooseFile(tester);
        expect(requests, isEmpty);
        final confirm = find.widgetWithText(FilledButton, 'Import Data');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(requests.single.url.path, '/v1/data/import');
        expect(jsonDecode(requests.single.body), payload);
        expect(find.text('Data imported successfully.'), findsOneWidget);
      },
      () => MockClient((request) async {
        requests.add(request);
        return http.Response('{"message":"Import successful"}', 201);
      }),
    );
  });
}
