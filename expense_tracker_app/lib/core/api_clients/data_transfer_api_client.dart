part of '../api_client.dart';

class DataTransferApiClient {
  static Future<Map<String, dynamic>> importData(
    Map<String, dynamic> payload,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/data/import'),
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

  static Future<Map<String, dynamic>> exportData() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/data/export'),
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
