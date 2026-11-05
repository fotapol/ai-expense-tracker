part of '../api_client.dart';

class DuplicateConflictException implements Exception {
  const DuplicateConflictException();
}

class DuplicatesApiClient {
  static Future<http.Response> _request(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final token = await ApiClient._getToken();
    final uri = Uri.parse(
      '${ApiClient.apiBaseUrl}/v1/duplicates$path',
    ).replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await runWithCoreRequestTimeout(
      body == null
          ? http.get(uri, headers: headers)
          : http.post(uri, headers: headers, body: jsonEncode(body)),
      operationName: 'Review duplicate receipts',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 409) throw const DuplicateConflictException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Duplicate review: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
    return response;
  }

  static Future<Map<String, dynamic>> list({
    int page = 1,
    String? transactionId,
  }) async {
    final response = await _request(
      '',
      query: {
        'page': '$page',
        'page_size': '20',
        'transaction_id': ?transactionId,
      },
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> dismiss(String firstId, String secondId) async {
    await _request(
      '/dismiss',
      body: {
        'first_transaction_id': firstId,
        'second_transaction_id': secondId,
      },
    );
  }

  static Future<Map<String, dynamic>> resolve({
    required String keepId,
    required String discardId,
    required String keepUpdatedAt,
    required String discardUpdatedAt,
  }) async {
    final response = await _request(
      '/resolve',
      body: {
        'keep_transaction_id': keepId,
        'discard_transaction_id': discardId,
        'keep_updated_at': keepUpdatedAt,
        'discard_updated_at': discardUpdatedAt,
      },
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
