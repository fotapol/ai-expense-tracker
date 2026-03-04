import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiClient {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Get a Firebase ID token for the current user.
  static Future<String> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    return await user.getIdToken() ?? '';
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

  /// POST /v1/receipts — create receipt and get presigned upload URL.
  static Future<Map<String, dynamic>> createReceipt({
    required String mimeType,
    String? originalFilename,
  }) async {
    final token = await _getToken();
    final body = <String, dynamic>{
      'mime_type': mimeType,
    };
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
          'Failed to create receipt: ${response.statusCode} ${response.body}');
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
      throw Exception(
          'Upload failed: ${response.statusCode} ${response.body}');
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
      throw Exception(
          'Confirm upload failed: ${response.statusCode} ${response.body}');
    }
  }

  /// GET /v1/receipts/{id} — poll receipt status.
  static Future<Map<String, dynamic>> getReceiptStatus(
      String receiptId) async {
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
          'Failed to get receipt status: ${response.statusCode} ${response.body}');
    }
  }

  /// GET /v1/transactions/{id}
  static Future<Map<String, dynamic>> getTransaction(String id) async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$apiBaseUrl/v1/transactions/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to get transaction: ${response.statusCode} ${response.body}');
    }
  }

  /// PUT /v1/transactions/{id}
  static Future<Map<String, dynamic>> updateTransaction(
      String id, Map<String, dynamic> payload) async {
    final token = await _getToken();
    final response = await http.put(
      Uri.parse('$apiBaseUrl/v1/transactions/$id'),
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
          'Failed to update transaction: ${response.statusCode} ${response.body}');
    }
  }

  /// GET /v1/transactions
  static Future<List<dynamic>> listTransactions({
    DateTime? fromDate,
    String? merchantNameSearch,
    String? categoryId,
    String? labelId,
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
    if (categoryId != null) {
      url += '&category_id=$categoryId';
    }
    if (labelId != null) {
      url += '&label_id=$labelId';
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
          'Failed to list transactions: ${response.statusCode} ${response.body}');
    }
  }

  /// GET /v1/transactions/summary
  static Future<Map<String, dynamic>> getTransactionsSummary({DateTime? fromDate}) async {
    final token = await _getToken();
    
    // Build query params
    String url = '$apiBaseUrl/v1/transactions/summary';
    if (fromDate != null) {
      url += '?from_occurred_at=${fromDate.toUtc().toIso8601String()}';
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
          'Failed to fetch summary: ${response.statusCode} ${response.body}');
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
  static Future<Map<String, dynamic>> createCategory(String name) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$apiBaseUrl/v1/categories'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to create category: ${response.statusCode} ${response.body}');
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
      throw Exception('Failed to delete category: ${response.statusCode} ${response.body}');
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
      throw Exception('Failed to delete receipt: ${response.statusCode} ${response.body}');
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
  static Future<Map<String, dynamic>> createLabel(String name, {String? color}) async {
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
      throw Exception('Failed to create label: ${response.statusCode} ${response.body}');
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
      throw Exception('Failed to delete label: ${response.statusCode} ${response.body}');
    }
  }
}
