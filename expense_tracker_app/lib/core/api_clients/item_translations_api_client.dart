part of '../api_client.dart';

class ItemTranslationApiClient {
  static Future<Map<String, dynamic>> postItemTranslationsBatch(
    List<Map<String, String>> items,
  ) async {
    if (items.isEmpty) {
      return {'inserted_count': 0, 'updated_count': 0, 'provider': 'mlkit'};
    }

    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/item-translations/batch'),
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
}
