import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiClient {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const String devBillingSecret = String.fromEnvironment(
    'DEV_BILLING_INTERNAL_SECRET',
    defaultValue: '',
  );

  /// Get a Firebase ID token for the current user.
  static Future<String> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return await user.getIdToken() ?? '';
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
        if (detail is Map<String, dynamic>) {
          final detailMessage = detail['message']?.toString();
          if (detailMessage != null && detailMessage.trim().isNotEmpty) {
            return detailMessage;
          }
        }
      }
    } catch (_) {}
    return response.body;
  }

  /// GET /v1/me
  static Future<Map<String, dynamic>> getMe() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }
  }

  /// PATCH /v1/me
  static Future<Map<String, dynamic>> updateMe(
    Map<String, dynamic> payload,
  ) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update profile: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/households
  static Future<Map<String, dynamic>> createHousehold({
    required String name,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/households'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create household: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// GET /v1/households/current
  static Future<Map<String, dynamic>> getCurrentHousehold() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/households/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to load current household: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// PATCH /v1/households/current
  static Future<Map<String, dynamic>> updateCurrentHousehold({
    required String name,
  }) async {
    final token = await _getToken();
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/v1/households/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to update household: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// GET /v1/households/current/members
  static Future<List<dynamic>> listCurrentHouseholdMembers() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/households/current/members'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to list household members: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// GET /v1/households/current/invites
  static Future<List<dynamic>> listCurrentHouseholdInvites() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/households/current/invites'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to list household invites: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// POST /v1/households/current/invites
  static Future<Map<String, dynamic>> createHouseholdInvite({
    String? invitedEmail,
    String? invitedUserId,
  }) async {
    final token = await _getToken();
    final payload = <String, dynamic>{};
    if (invitedEmail != null && invitedEmail.trim().isNotEmpty) {
      payload['invited_email'] = invitedEmail.trim();
    }
    if (invitedUserId != null && invitedUserId.trim().isNotEmpty) {
      payload['invited_user_id'] = invitedUserId.trim();
    }
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/households/current/invites'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create invite: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// POST /v1/households/current/invites/{inviteId}/revoke
  static Future<Map<String, dynamic>> revokeHouseholdInvite(String inviteId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/households/current/invites/$inviteId/revoke'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to revoke invite: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// POST /v1/households/current/members/{id}/remove
  static Future<Map<String, dynamic>> removeHouseholdMember(String memberId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/households/current/members/$memberId/remove'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to remove member: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// POST /v1/household-invites/{token}/accept
  static Future<Map<String, dynamic>> acceptHouseholdInvite(String inviteToken) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/household-invites/$inviteToken/accept'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to accept invite: ${response.statusCode} ${_extractErrorMessage(response)}',
    );
  }

  /// POST /v1/receipts — create receipt and get presigned upload URL.
  static Future<Map<String, dynamic>> createReceipt({
    required String mimeType,
    String? originalFilename,
  }) async {
    final token = await _getToken();
    final body = <String, dynamic>{'mime_type': mimeType};
    if (originalFilename != null) {
      body['original_filename'] = originalFilename;
    }

    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/receipts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to create receipt: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// PUT image bytes to the presigned upload URL.
  static Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    required Uint8List fileBytes,
    required Map<String, String> requiredHeaders,
  }) async {
    final response = await http.put(
      Uri.parse(uploadUrl),
      headers: requiredHeaders,
      body: fileBytes,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed: ${response.statusCode} ${response.body}');
    }
  }

  /// POST /v1/receipts/{id}/confirm-upload
  static Future<Map<String, dynamic>> confirmUpload(String receiptId) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/receipts/$receiptId/confirm-upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      if (response.statusCode == 403) {
        String? limitMessage;
        try {
          final payload = jsonDecode(response.body);
          if (payload is Map<String, dynamic>) {
            final detail = payload['detail'];
            if (detail is Map<String, dynamic> &&
                detail['code'] == 'free_monthly_scan_limit_reached') {
              limitMessage = detail['message']?.toString();
            }
          }
        } catch (_) {}
        if (limitMessage != null && limitMessage.trim().isNotEmpty) {
          throw Exception(limitMessage);
        }
      }
      throw Exception(
        'Confirm upload failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/receipts/{id} — poll receipt status.
  static Future<Map<String, dynamic>> getReceiptStatus(String receiptId) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/receipts/$receiptId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to get receipt status: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/transactions/{id}
  static Future<Map<String, dynamic>> getTransaction(
    String id, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await _getToken();
    String url = '$apiBaseUrl/v1/transactions/$id';
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

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to get transaction: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// PUT /v1/transactions/{id}
  static Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) async {
    final token = await _getToken();
    String url = '$apiBaseUrl/v1/transactions/$id';
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
    final response = await http.put(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update transaction: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// DELETE /v1/transactions/{transactionId}/items/{itemId}
  static Future<void> deleteTransactionItem(
    String transactionId,
    String itemId,
  ) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/v1/transactions/$transactionId/items/$itemId'),
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

  /// GET /v1/transactions
  static Future<List<dynamic>> listTransactions({
    DateTime? fromDate,
    String? merchantNameSearch,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? labelId,
    String? targetCurrency,
  }) async {
    final token = await _getToken();

    // Build query params
    String url = '$apiBaseUrl/v1/transactions?page_size=100';
    if (fromDate != null) {
      url += '&from_occurred_at=${fromDate.toUtc().toIso8601String()}';
    }
    if (merchantNameSearch != null && merchantNameSearch.isNotEmpty) {
      url += '&merchant_name_search=${Uri.encodeComponent(merchantNameSearch)}';
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      url += '&category_ids=${categoryIds.join(',')}';
    }
    if (subcategoryIds != null && subcategoryIds.isNotEmpty) {
      url += '&subcategory_ids=${subcategoryIds.join(',')}';
    }
    if (labelId != null) {
      url += '&label_id=$labelId';
    }
    if (labelIds != null && labelIds.isNotEmpty) {
      url += '&label_ids=${labelIds.join(',')}';
    }
    if (targetCurrency != null && targetCurrency.isNotEmpty) {
      url += '&target_currency=${Uri.encodeComponent(targetCurrency)}';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception(
        'Failed to list transactions: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/transactions/summary
  static Future<Map<String, dynamic>> getTransactionsSummary({
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) async {
    final token = await _getToken();

    // Build query params
    String url = '$apiBaseUrl/v1/transactions/summary';
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
        'Failed to fetch summary: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/transactions/summary/categories/{categoryId}/subcategories
  static Future<Map<String, dynamic>> getCategorySubcategorySummary({
    required String categoryId,
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) async {
    final token = await _getToken();

    String url =
        '$apiBaseUrl/v1/transactions/summary/categories/$categoryId/subcategories';
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

  /// GET /v1/transactions/summary/subcategories/{subcategoryId}/items
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
    final token = await _getToken();

    String url =
        '$apiBaseUrl/v1/transactions/summary/subcategories/$subcategoryId/items';
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

  /// GET /v1/categories
  static Future<List<dynamic>> listCategories() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/categories'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to list categories: ${response.statusCode}');
    }
  }

  /// POST /v1/categories
  static Future<Map<String, dynamic>> createCategory(
    String name, {
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final token = await _getToken();
    final body = <String, dynamic>{
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
    }..removeWhere((_, value) => value == null);
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/categories'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to create category: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// PUT /v1/categories/{id}
  static Future<Map<String, dynamic>> updateCategory(
    String id, {
    String? name,
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final token = await _getToken();
    final body = <String, dynamic>{
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
    }..removeWhere((_, value) => value == null);

    final response = await http.put(
      Uri.parse('$apiBaseUrl/v1/categories/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update category: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// DELETE /v1/categories/{id}
  static Future<void> deleteCategory(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/v1/categories/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete category: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// DELETE /v1/receipts/{id}
  static Future<void> deleteReceipt(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/v1/receipts/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete receipt: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/labels
  static Future<List<dynamic>> listLabels() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/labels'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to list labels: ${response.statusCode}');
    }
  }

  /// POST /v1/labels
  static Future<Map<String, dynamic>> createLabel(
    String name, {
    String? color,
  }) async {
    final token = await _getToken();
    final body = {'name': name};
    if (color != null) body['color'] = color;
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/labels'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to create label: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// DELETE /v1/labels/{id}
  static Future<void> deleteLabel(String id) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/v1/labels/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete label: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/labels/assign
  static Future<Map<String, dynamic>> assignLabel({
    required String transactionId,
    required String labelId,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/labels/assign'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'transaction_id': transactionId, 'label_id': labelId}),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to assign label: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/labels/unassign
  static Future<Map<String, dynamic>> unassignLabel({
    required String transactionId,
    required String labelId,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/labels/unassign'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'transaction_id': transactionId, 'label_id': labelId}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to unassign label: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/me/subscription
  static Future<Map<String, dynamic>> getMeSubscription() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/me/subscription'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load subscription: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/me/entitlements
  static Future<Map<String, dynamic>> getMeEntitlements() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/me/entitlements'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load entitlements: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/billing/revenuecat/sync
  static Future<Map<String, dynamic>> syncRevenueCatSubscription() async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/billing/revenuecat/sync'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to sync subscription: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /internal/dev/billing/subscriptions/manual
  static Future<Map<String, dynamic>> applyDevManualSubscriptionAction({
    required String targetUserId,
    required String action,
    String productId = 'personal_premium',
    DateTime? expiresAt,
    String? reason,
  }) async {
    final token = await _getToken();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    if (devBillingSecret.trim().isNotEmpty) {
      headers['X-Internal-Dev-Key'] = devBillingSecret.trim();
    }

    final payload = <String, dynamic>{
      'target_user_id': targetUserId,
      'action': action,
      'product_id': productId,
    };
    if (expiresAt != null) {
      payload['expires_at'] = expiresAt.toUtc().toIso8601String();
    }
    if (reason != null && reason.trim().isNotEmpty) {
      payload['reason'] = reason.trim();
    }

    final response = await http.post(
      Uri.parse('$apiBaseUrl/internal/dev/billing/subscriptions/manual'),
      headers: headers,
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to apply dev subscription action: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/item-translations/batch
  static Future<Map<String, dynamic>> postItemTranslationsBatch(
    List<Map<String, String>> items,
  ) async {
    if (items.isEmpty) {
      return {'inserted_count': 0, 'updated_count': 0, 'provider': 'mlkit'};
    }

    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/item-translations/batch'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'items': items}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to upsert item translations: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// POST /v1/data/import
  static Future<Map<String, dynamic>> importData(Map<String, dynamic> payload) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/data/import'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to import data: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// GET /v1/data/export
  static Future<Map<String, dynamic>> exportData() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/data/export'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to export data: ${response.statusCode} ${response.body}',
      );
    }
  }
}
