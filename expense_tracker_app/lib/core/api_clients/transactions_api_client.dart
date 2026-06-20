part of '../api_client.dart';

class TransactionApiClient {
  static Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> payload, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await ApiClient._getToken();
    String url = '${ApiClient.apiBaseUrl}/v1/transactions';
    final params = <String>[];
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (itemLanguage != null && itemLanguage.isNotEmpty) {
      params.add('item_language=${Uri.encodeComponent(itemLanguage)}');
    }
    if (appLanguage != null && appLanguage.isNotEmpty) {
      params.add('app_language=${Uri.encodeComponent(appLanguage)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await runWithCoreRequestTimeout(
      http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
      operationName: 'Create transaction',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to create transaction: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<Map<String, dynamic>> getTransaction(
    String id, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await ApiClient._getToken();
    String url = '${ApiClient.apiBaseUrl}/v1/transactions/$id';
    final params = <String>[];
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (itemLanguage != null && itemLanguage.isNotEmpty) {
      params.add('item_language=${Uri.encodeComponent(itemLanguage)}');
    }
    if (appLanguage != null && appLanguage.isNotEmpty) {
      params.add('app_language=${Uri.encodeComponent(appLanguage)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to get transaction: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> deleteTransaction(String id) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/transactions/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete transaction: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await ApiClient._getToken();
    String url = '${ApiClient.apiBaseUrl}/v1/transactions/$id';
    final params = <String>[];
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (itemLanguage != null && itemLanguage.isNotEmpty) {
      params.add('item_language=${Uri.encodeComponent(itemLanguage)}');
    }
    if (appLanguage != null && appLanguage.isNotEmpty) {
      params.add('app_language=${Uri.encodeComponent(appLanguage)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    final response = await runWithCoreRequestTimeout(
      http.put(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
      operationName: 'Update transaction',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update transaction: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> deleteTransactionItem(
    String transactionId,
    String itemId,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse(
        '${ApiClient.apiBaseUrl}/v1/transactions/$transactionId/items/$itemId',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete transaction item: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<List<dynamic>> listTransactions({
    DateTime? fromDate,
    String? merchantNameSearch,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? labelId,
    String? targetCurrency,
  }) async {
    final token = await ApiClient._getToken();

    // Build query params — do not cap page_size here; backend determines page size.
    // M-1 fix: removing the hardcoded page_size=100 prevents silent truncation for users
    // with more than 100 transactions.
    final params = <String>[];
    if (fromDate != null) {
      params.add('from_occurred_at=${fromDate.toUtc().toIso8601String()}');
    }
    if (merchantNameSearch != null && merchantNameSearch.isNotEmpty) {
      params.add(
        'merchant_name_search=${Uri.encodeComponent(merchantNameSearch)}',
      );
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params.add('category_ids=${categoryIds.join(',')}');
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      params.add('subcategory_ids=${subcategoryIds.join(',')}');
    }
    if (labelId != null) {
      params.add('label_id=$labelId');
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      params.add('label_ids=${labelIds.join(',')}');
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    var url = '${ApiClient.apiBaseUrl}/v1/transactions';
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    // M-2 fix: add a 30 s timeout so the app never hangs indefinitely on a slow network.
    final response = await http
        .get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 30));
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(
        'Failed to list transactions: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> getTransactionsSummary({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
    String? groupBy,
  }) async {
    final token = await ApiClient._getToken();

    // Build query params
    String url = '${ApiClient.apiBaseUrl}/v1/transactions/summary';
    final params = <String>[];

    if (fromDate != null) {
      params.add('from_occurred_at=${fromDate.toUtc().toIso8601String()}');
    }
    if (toDate != null) {
      params.add('to_occurred_at=${toDate.toUtc().toIso8601String()}');
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params.add('category_ids=${categoryIds.join(',')}');
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      params.add('subcategory_ids=${subcategoryIds.join(',')}');
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      params.add('label_ids=${labelIds.join(',')}');
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (groupBy != null && groupBy.isNotEmpty) {
      params.add('group_by=${Uri.encodeComponent(groupBy)}');
    }

    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to fetch summary: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> getTransactionTrendSummary({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) async {
    final token = await ApiClient._getToken();

    String url = '${ApiClient.apiBaseUrl}/v1/transactions/summary/trends';
    final params = <String>[];
    if (fromDate != null) {
      params.add('from_occurred_at=${fromDate.toUtc().toIso8601String()}');
    }
    if (toDate != null) {
      params.add('to_occurred_at=${toDate.toUtc().toIso8601String()}');
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params.add('category_ids=${categoryIds.join(',')}');
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      params.add('subcategory_ids=${subcategoryIds.join(',')}');
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      params.add('label_ids=${labelIds.join(',')}');
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to fetch trend summary: ${response.statusCode} ${response.body}',
    );
  }

  static Future<Map<String, dynamic>> getCategorySubcategorySummary({
    required String categoryId,
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) async {
    final token = await ApiClient._getToken();

    String url =
        '${ApiClient.apiBaseUrl}/v1/transactions/summary/categories/$categoryId/subcategories';
    final params = <String>[];
    if (fromDate != null) {
      params.add('from_occurred_at=${fromDate.toUtc().toIso8601String()}');
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params.add('category_ids=${categoryIds.join(',')}');
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      params.add('subcategory_ids=${subcategoryIds.join(',')}');
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      params.add('label_ids=${labelIds.join(',')}');
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to fetch subcategories summary: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> getSubcategoryItemsSummary({
    required String subcategoryId,
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await ApiClient._getToken();

    String url =
        '${ApiClient.apiBaseUrl}/v1/transactions/summary/subcategories/$subcategoryId/items';
    final params = <String>[];
    if (fromDate != null) {
      params.add('from_occurred_at=${fromDate.toUtc().toIso8601String()}');
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      params.add('category_ids=${categoryIds.join(',')}');
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      params.add('subcategory_ids=${subcategoryIds.join(',')}');
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      params.add('label_ids=${labelIds.join(',')}');
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      params.add('target_currency=${Uri.encodeComponent(targetCurrency)}');
    }
    if (itemLanguage != null && itemLanguage.isNotEmpty) {
      params.add('item_language=${Uri.encodeComponent(itemLanguage)}');
    }
    if (appLanguage != null && appLanguage.isNotEmpty) {
      params.add('app_language=${Uri.encodeComponent(appLanguage)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to fetch subcategory items: ${response.statusCode} ${response.body}',
      );
    }
  }
}
