part of '../api_client.dart';

class ReceiptApiClient {
  static Future<Map<String, dynamic>> createReceipt({
    required String mimeType,
    String? originalFilename,
  }) async {
    final token = await ApiClient._getToken();
    final body = <String, dynamic>{'mime_type': mimeType};
    if (originalFilename != null) {
      body['original_filename'] = originalFilename;
    }

    final response = await runWithCoreRequestTimeout(
      http.post(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/receipts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ),
      operationName: 'Create receipt',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to create receipt: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    required Uint8List fileBytes,
    required Map<String, String> requiredHeaders,
  }) async {
    final response = await runWithCoreRequestTimeout(
      http.put(Uri.parse(uploadUrl), headers: requiredHeaders, body: fileBytes),
      operationName: 'Upload receipt',
      timeout: coreUploadRequestTimeout,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed: ${response.statusCode} ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> confirmUpload(String receiptId) async {
    final token = await ApiClient._getToken();
    final response = await runWithCoreRequestTimeout(
      http.post(
        Uri.parse(
          '${ApiClient.apiBaseUrl}/v1/receipts/$receiptId/confirm-upload',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
      operationName: 'Confirm receipt upload',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

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
                detail['code'] == 'free_rolling_scan_limit_reached') {
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

  static Future<Map<String, dynamic>> getReceiptStatus(String receiptId) async {
    final token = await ApiClient._getToken();
    final response = await runWithCoreRequestTimeout(
      http.get(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/receipts/$receiptId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
      operationName: 'Poll receipt status',
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to get receipt status: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> getReceiptViewUrl(
    String receiptId,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/receipts/$receiptId/view-url'),
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
        'Failed to get receipt view URL: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<void> deleteReceipt(String id) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/receipts/$id'),
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
}
