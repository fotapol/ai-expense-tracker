part of '../api_client.dart';

class PlanningApiClient {
  static Future<Map<String, dynamic>> getBudgetPlan() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/budget'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to load budget plan: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> updateBudgetPlan({
    required String currency,
    double? monthlyIncome,
    required List<Map<String, dynamic>> categoryLimits,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.put(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/budget'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'monthly_income': monthlyIncome,
        'currency': currency.toUpperCase(),
        'category_limits': categoryLimits,
      }),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to update budget plan: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<List<dynamic>> listBillReminders() async {
    final token = await ApiClient._getToken();
    final response = await http.get(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/bills'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(
      'Failed to list bill reminders: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> createBillReminder({
    required String name,
    required double amount,
    required String currency,
    required String recurrence,
    required DateTime firstDueDate,
    int remindDaysBefore = 3,
    bool isActive = true,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.post(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/bills'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name.trim(),
        'amount': amount,
        'currency': currency.toUpperCase(),
        'recurrence': recurrence.trim().toLowerCase(),
        'first_due_date': ApiClient._dateOnlyIso(firstDueDate),
        'remind_days_before': remindDaysBefore,
        'is_active': isActive,
      }),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to create bill reminder: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> markBillReminderPaid({
    required String billId,
    required DateTime dueDate,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.patch(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/bills/$billId/mark-paid'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'due_date': ApiClient._dateOnlyIso(dueDate)}),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to mark bill reminder as paid: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<Map<String, dynamic>> skipBillReminder({
    required String billId,
    required DateTime dueDate,
  }) async {
    final token = await ApiClient._getToken();
    final response = await http.patch(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/bills/$billId/skip'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'due_date': ApiClient._dateOnlyIso(dueDate)}),
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(
      'Failed to skip bill reminder: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
    );
  }

  static Future<void> deleteBillReminder(String billId) async {
    final token = await ApiClient._getToken();
    final response = await http.delete(
      Uri.parse('${ApiClient.apiBaseUrl}/v1/planning/bills/$billId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    await ApiClient._throwIfUnauthorizedResponse(response);
    if (response.statusCode != 204) {
      throw Exception(
        'Failed to delete bill reminder: ${response.statusCode} ${ApiClient._extractErrorMessage(response)}',
      );
    }
  }
}
