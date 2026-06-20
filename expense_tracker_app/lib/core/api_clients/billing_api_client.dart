part of '../api_client.dart';

class BillingApiClient {
  static Future<Map<String, dynamic>> getMeSubscription() async {
    final token = await ApiClient._getToken();
    final response = await runWithCoreRequestTimeout(
      http.get(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/me/subscription'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
      operationName: 'Load subscription',
      timeout: coreBillingRequestTimeout,
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load subscription: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> getMeEntitlements() async {
    final token = await ApiClient._getToken();
    final response = await runWithCoreRequestTimeout(
      http.get(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/me/entitlements'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ),
      operationName: 'Load entitlements',
      timeout: coreBillingRequestTimeout,
    );
    await ApiClient._throwIfUnauthorizedResponse(response);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load entitlements: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> syncRevenueCatSubscription() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // Re-fetch token on each attempt so that if a 5xx happens near token
      // expiry the retry doesn't reuse an already-expired token.
      final token = await ApiClient._getToken();
      final response = await runWithCoreRequestTimeout(
        http.post(
          Uri.parse('${ApiClient.apiBaseUrl}/v1/billing/revenuecat/sync'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        operationName: 'Sync subscription',
        timeout: coreBillingRequestTimeout,
      );
      await ApiClient._throwIfUnauthorizedResponse(response);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode >= 500 && attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        continue;
      }
      throw Exception(
        'Failed to sync subscription: ${response.statusCode} ${response.body}',
      );
    }
    throw Exception('Failed to sync subscription: request retry exhausted.');
  }

  static Future<Map<String, dynamic>> applyDevManualSubscriptionAction({
    required String targetUserId,
    required String action,
    String productId = 'personal_premium',
    DateTime? expiresAt,
    String? reason,
  }) async {
    final token = await ApiClient._getToken();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    if (ApiClient.devBillingSecret.trim().isNotEmpty) {
      headers['X-Internal-Dev-Key'] = ApiClient.devBillingSecret.trim();
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
      Uri.parse(
        '${ApiClient.apiBaseUrl}/internal/dev/billing/subscriptions/manual',
      ),
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
}
