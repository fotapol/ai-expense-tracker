part of '../api_client.dart';

class TaxonomyApiClient {
  static Future<List<dynamic>> listCategories({
    bool includeDisabled = false,
  }) async {
    final token = await ApiClient._getToken();
    final suffix = includeDisabled ? '?include_disabled=true' : '';
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/categories$suffix'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to list categories: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> createCategory(
    String name, {
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final token = await ApiClient._getToken();
    final body = <String, dynamic>{
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
    }..removeWhere((_, value) => value == null);
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/categories'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final limitException = ApiClient._extractCategoryLimitException(response);
      if (limitException != null) throw limitException;
      throw Exception(
        'Failed to create category: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<Map<String, dynamic>> updateCategory(
    String id, {
    String? name,
    String? parentId,
    String? icon,
    String? color,
  }) async {
    final token = await ApiClient._getToken();
    final body = <String, dynamic>{
      'name': name,
      'parent_id': parentId,
      'icon': icon,
      'color': color,
    }..removeWhere((_, value) => value == null);

    final response = await http.put(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/categories/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      final limitException = ApiClient._extractCategoryLimitException(response);
      if (limitException != null) throw limitException;
      throw Exception(
        'Failed to update category: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<void> deleteCategory(String id) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/categories/$id'),
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

  static Future<Map<String, dynamic>> restoreCategory(String id) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/categories/$id/restore'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to restore category: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }
}
