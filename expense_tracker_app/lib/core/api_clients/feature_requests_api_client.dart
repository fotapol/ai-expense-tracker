part of '../api_client.dart';

class FeatureRequestApiClient {
  static Future<List<dynamic>> listFeatureRequests() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/feature-requests'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to load feature requests: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<List<dynamic>> listMyFeatureRequests() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/feature-requests/mine'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to load your feature requests: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> createFeatureRequest({
    required String title,
    required String category,
    required String description,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/feature-requests'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'category': category,
        'description': description,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create feature request: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> updateFeatureRequestVote({
    required String featureRequestId,
    required bool voted,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.put(
      Uri.parse(
        '${ApiClient.apiBaseUrl}/v1/feature-requests/$featureRequestId/vote',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'voted': voted}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to update vote: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }
}
