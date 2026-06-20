part of '../api_client.dart';

class HouseholdApiClient {
  static Future<Map<String, dynamic>> createHousehold({
    required String name,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create household: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> getCurrentHousehold() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to load current household: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> updateCurrentHousehold({
    required String name,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.patch(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to update household: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<List<dynamic>> listCurrentHouseholdMembers() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current/members'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to list household members: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<void> leaveCurrentHousehold() async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current/leave'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to leave household: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<void> deleteCurrentHousehold() async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete household: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }

  static Future<List<dynamic>> listCurrentHouseholdInvites() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current/invites'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to list household invites: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> createHouseholdInvite({
    String? invitedEmail,
    String? invitedUserId,
  }) async {
    final token = await ApiClient._getToken();
    final payload = <String, dynamic>{};
    if (invitedEmail != null && invitedEmail.trim().isNotEmpty) {
      payload['invited_email'] = invitedEmail.trim();
    }
    if (invitedUserId != null && invitedUserId.trim().isNotEmpty) {
      payload['invited_user_id'] = invitedUserId.trim();
    }
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/households/current/invites'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create invite: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> revokeHouseholdInvite(
    String inviteId,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse(
        '${ApiClient.apiBaseUrl}/v1/households/current/invites/$inviteId/revoke',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to revoke invite: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> removeHouseholdMember(
    String memberId,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse(
        '${ApiClient.apiBaseUrl}/v1/households/current/members/$memberId/remove',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to remove member: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> acceptHouseholdInvite(
    String inviteToken,
  ) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse(
        '${ApiClient.apiBaseUrl}/v1/household-invites/$inviteToken/accept',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to accept invite: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }
}
