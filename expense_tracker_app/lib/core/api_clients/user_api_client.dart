part of '../api_client.dart';

class UserApiClient {
  static Future<Map<String, dynamic>> getMe() async {
    final token = await ApiClient._getToken();
    http.Response response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    response = await ApiClient._handleUnauthorizedResponse(
      response,
      retry: (freshToken) => http.get(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
        headers: {
          'Authorization': 'Bearer $freshToken',
          'Content-Type': 'application/json',
        },
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> updateMe(
    Map<String, dynamic> payload,
  ) async {
    final token = await ApiClient._getToken();
    http.Response response = await http.patch(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );
    response = await ApiClient._handleUnauthorizedResponse(
      response,
      retry: (freshToken) => http.patch(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
        headers: {
          'Authorization': 'Bearer $freshToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to update profile: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<void> deleteMe() async {
    final token = await ApiClient._getToken();
    http.Response response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    response = await ApiClient._handleUnauthorizedResponse(
      response,
      retry: (freshToken) => http.delete(
        Uri.parse('${ApiClient.apiBaseUrl}/v1/me'),
        headers: {
          'Authorization': 'Bearer $freshToken',
          'Content-Type': 'application/json',
        },
      ),
    );

    if (response.statusCode == 204) return;
    throw Exception(
      'Failed to delete account: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }
}
