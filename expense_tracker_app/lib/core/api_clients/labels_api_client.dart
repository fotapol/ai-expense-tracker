part of '../api_client.dart';

class LabelApiClient {
  static Future<List<dynamic>> listLabels() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/labels'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to list labels: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> createLabel(
    String name, {
    String? color,
  }) async {
    final token = await ApiClient._getToken();
    final body = {'name': name};
    if (color != null) body['color'] = color;
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/labels'),
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

  static Future<void> deleteLabel(String id) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/labels/$id'),
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

  static Future<Map<String, dynamic>> assignLabel({
    required String transactionId,
    required String labelId,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/labels/assign'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'transaction_id': transactionId, 'label_id': labelId}),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to assign label: ${response.statusCode} ${response.body}',
      );
    }
  }

  static Future<Map<String, dynamic>> unassignLabel({
    required String transactionId,
    required String labelId,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/labels/unassign'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'transaction_id': transactionId, 'label_id': labelId}),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to unassign label: ${response.statusCode} ${response.body}',
      );
    }
  }
}
