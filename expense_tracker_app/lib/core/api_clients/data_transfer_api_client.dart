part of '../api_client.dart';

class DataTransferApiClient {
  static Future<Map<String, dynamic>> previewExternalImport(
    Uint8List file,
    String source,
  ) async {
    final token = await ApiClient._getToken();
    final uri = Uri.parse(
      '${ApiClient.apiBaseUrl}/v1/data/external-import/preview',
    );
    final response = await http
        .post(
          uri.replace(queryParameters: {'source': source}),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/octet-stream',
          },
          body: file,
        )
        .timeout(const Duration(minutes: 1));
    return _readExternalResponse(response, 200);
  }

  static Future<Map<String, dynamic>> importExternalData(
    Map<String, dynamic> plan,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http
        .post(
          Uri.parse('${ApiClient.apiBaseUrl}/v1/data/external-import'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(plan),
        )
        .timeout(const Duration(minutes: 1));
    return _readExternalResponse(response, 201);
  }

  static Map<String, dynamic> _readExternalResponse(
    http.Response response,
    int expectedStatus,
  ) {
    if (response.statusCode == expectedStatus) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    // The error body can contain submitted values. Avoid surfacing them to the user.
    throw ExternalImportException(response.statusCode);
  }

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

class ExternalImportException implements Exception {
  const ExternalImportException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'External import failed: $statusCode';
}
