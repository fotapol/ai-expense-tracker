import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_session.dart';
import 'core_request_timeout.dart';
import 'session_invalidation.dart';

part 'api_clients/billing_api_client.dart';
part 'api_clients/data_transfer_api_client.dart';
part 'api_clients/feature_requests_api_client.dart';
part 'api_clients/households_api_client.dart';
part 'api_clients/item_translations_api_client.dart';
part 'api_clients/labels_api_client.dart';
part 'api_clients/planning_api_client.dart';
part 'api_clients/receipts_api_client.dart';
part 'api_clients/taxonomy_api_client.dart';
part 'api_clients/transactions_api_client.dart';
part 'api_clients/user_api_client.dart';

class ApiCategoryLimitException implements Exception {
  const ApiCategoryLimitException({
    required this.code,
    required this.message,
    this.used,
    this.limit,
    this.remaining,
  });

  final String code;
  final String message;
  final int? used;
  final int? limit;
  final int? remaining;

  @override
  String toString() => message;
}

class ApiClient {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  static const String devBillingSecret = String.fromEnvironment(
    'DEV_BILLING_INTERNAL_SECRET',
    defaultValue: '',
  );

  /// Get a Firebase ID token for the current user.
  ///
  /// Network-aware refresh strategy:
  /// - Returns the cached token immediately when it is not near expiry.
  /// - Forces a refresh when the token is within the 5-min expiry window.
  /// - If the network refresh fails due to a transient error
  ///   ([SocketException] / [TimeoutException]) but a cached token still
  ///   exists, the cached token is returned so the request can proceed
  ///   without logging the user out.
  /// - Only calls [invalidateExpiredSession] when [currentUser] is null,
  ///   which is the one condition that unambiguously means the session is gone.
  static Future<String> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await invalidateExpiredSession();
      throw StateError(expiredSessionMessage);
    }
    try {
      final tokenResult = await user.getIdTokenResult();
      final cachedToken = tokenResult.token;
      final shouldRefresh =
          (cachedToken ?? '').trim().isEmpty ||
          shouldForceSessionTokenRefresh(tokenResult.expirationTime);
      if (!shouldRefresh) {
        return requireAuthenticatedSessionToken(cachedToken);
      }

      try {
        final refreshedToken = await user.getIdToken(true);
        return requireAuthenticatedSessionToken(refreshedToken);
      } on SocketException {
        // Transient network failure — fall back to the cached token if it
        // still exists so we do not log the user out unnecessarily.
        if ((cachedToken ?? '').trim().isNotEmpty) {
          return requireAuthenticatedSessionToken(cachedToken);
        }
        rethrow;
      } on TimeoutException {
        if ((cachedToken ?? '').trim().isNotEmpty) {
          return requireAuthenticatedSessionToken(cachedToken);
        }
        rethrow;
      } catch (_) {
        // For any other refresh failure also try the cached token first.
        if ((cachedToken ?? '').trim().isNotEmpty) {
          return requireAuthenticatedSessionToken(cachedToken);
        }
        rethrow;
      }
    } on StateError {
      // requireAuthenticatedSessionToken threw — token is genuinely missing.
      // Do NOT call invalidateExpiredSession here; the caller's
      // _handleUnauthorizedResponse will deal with it after a retry.
      rethrow;
    }
  }

  /// Force-refresh the token without falling back to the cache.
  ///
  /// Used by the 401-retry path to get a guaranteed-fresh token.
  static Future<String?> _forceRefreshToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(true);
    } catch (_) {
      return null;
    }
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail;
        }
        if (detail is Map<String, dynamic>) {
          final detailMessage = detail['message']?.toString();
          if (detailMessage != null && detailMessage.trim().isNotEmpty) {
            return detailMessage;
          }
        }
      }
    } catch (_) {}
    return response.body;
  }

  static ApiCategoryLimitException? _extractCategoryLimitException(
    http.Response response,
  ) {
    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return null;
      final detail = payload['detail'];
      if (detail is! Map<String, dynamic>) return null;
      final code = detail['code']?.toString();
      if (code != 'free_plan_category_limit_reached' &&
          code != 'free_plan_subcategory_limit_reached') {
        return null;
      }
      int? parseInt(Object? value) => int.tryParse(value?.toString() ?? '');
      return ApiCategoryLimitException(
        code: code!,
        message:
            detail['message']?.toString() ?? _extractErrorMessage(response),
        used: parseInt(detail['used']),
        limit: parseInt(detail['limit']),
        remaining: parseInt(detail['remaining']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Handle a 401 response with a single token-refresh retry.
  ///
  /// Strategy:
  /// 1. If the response is not 401 → do nothing.
  /// 2. Force-refresh the Firebase ID token.
  /// 3. Retry the original request with the new token.
  /// 4a. Retry succeeds (non-401) → return the new response.
  /// 4b. Retry is also 401 → the session is genuinely invalid;
  ///     call [invalidateExpiredSession] and throw.
  /// 4c. No token after refresh (user signed out) → same as 4b.
  ///
  /// This prevents the app from logging the user out when the backend
  /// returns a transient 401 (e.g. Redis unavailable, network partition
  /// between backend and Firebase token endpoint).
  static Future<http.Response> _handleUnauthorizedResponse(
    http.Response response, {
    required Future<http.Response> Function(String freshToken) retry,
  }) async {
    if (response.statusCode != 401) return response;

    final freshToken = await _forceRefreshToken();
    if (freshToken == null || freshToken.trim().isEmpty) {
      // Could not get a fresh token — session is gone.
      await invalidateExpiredSession();
      throw StateError(expiredSessionMessage);
    }

    final retried = await retry(freshToken);
    if (retried.statusCode == 401) {
      // Still 401 after a fresh token → genuinely invalid session.
      await invalidateExpiredSession();
      throw StateError(expiredSessionMessage);
    }
    return retried;
  }

  // ---------------------------------------------------------------------------
  // Legacy helper kept for callers that do not yet use _handleUnauthorizedResponse.
  // It now uses clearFirebaseSession (does not clear Google Sign-In) when a
  // retry is not possible (e.g. multipart / presigned-URL requests).
  // ---------------------------------------------------------------------------
  static Future<void> _throwIfUnauthorizedResponse(
    http.Response response,
  ) async {
    if (response.statusCode != 401) return;
    // For callers that cannot easily supply a retry callback we still
    // clear the Firebase session, but we do NOT clear the Google account
    // so the user can silently re-authenticate on the login screen.
    await clearFirebaseSession();
    throw StateError(expiredSessionMessage);
  }

  static Future<Map<String, dynamic>> getMe() => UserApiClient.getMe();

  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> payload) =>
      UserApiClient.updateMe(payload);

  static Future<void> deleteMe() => UserApiClient.deleteMe();

  static Future<Map<String, dynamic>> createHousehold({required String name}) =>
      HouseholdApiClient.createHousehold(name: name);

  static Future<Map<String, dynamic>> getCurrentHousehold() =>
      HouseholdApiClient.getCurrentHousehold();

  static Future<Map<String, dynamic>> updateCurrentHousehold({
    required String name,
  }) => HouseholdApiClient.updateCurrentHousehold(name: name);

  static Future<List<dynamic>> listCurrentHouseholdMembers() =>
      HouseholdApiClient.listCurrentHouseholdMembers();

  static Future<void> leaveCurrentHousehold() =>
      HouseholdApiClient.leaveCurrentHousehold();

  static Future<void> deleteCurrentHousehold() =>
      HouseholdApiClient.deleteCurrentHousehold();

  static Future<List<dynamic>> listCurrentHouseholdInvites() =>
      HouseholdApiClient.listCurrentHouseholdInvites();

  static Future<Map<String, dynamic>> createHouseholdInvite({
    String? invitedEmail,
    String? invitedUserId,
  }) => HouseholdApiClient.createHouseholdInvite(
    invitedEmail: invitedEmail,
    invitedUserId: invitedUserId,
  );

  static Future<Map<String, dynamic>> revokeHouseholdInvite(String inviteId) =>
      HouseholdApiClient.revokeHouseholdInvite(inviteId);

  static Future<Map<String, dynamic>> removeHouseholdMember(String memberId) =>
      HouseholdApiClient.removeHouseholdMember(memberId);

  static Future<Map<String, dynamic>> acceptHouseholdInvite(
    String inviteToken,
  ) => HouseholdApiClient.acceptHouseholdInvite(inviteToken);

  static Future<Map<String, dynamic>> createReceipt({
    required String mimeType,
    String? originalFilename,
  }) => ReceiptApiClient.createReceipt(
    mimeType: mimeType,
    originalFilename: originalFilename,
  );

  static Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    required Uint8List fileBytes,
    required Map<String, String> requiredHeaders,
  }) => ReceiptApiClient.uploadToPresignedUrl(
    uploadUrl: uploadUrl,
    fileBytes: fileBytes,
    requiredHeaders: requiredHeaders,
  );

  static Future<Map<String, dynamic>> confirmUpload(String receiptId) =>
      ReceiptApiClient.confirmUpload(receiptId);

  static Future<Map<String, dynamic>> getReceiptStatus(String receiptId) =>
      ReceiptApiClient.getReceiptStatus(receiptId);

  static Future<Map<String, dynamic>> getReceiptViewUrl(String receiptId) =>
      ReceiptApiClient.getReceiptViewUrl(receiptId);

  static Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> payload, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) => TransactionApiClient.createTransaction(
    payload,
    targetCurrency: targetCurrency,
    itemLanguage: itemLanguage,
    appLanguage: appLanguage,
  );

  static Future<Map<String, dynamic>> getTransaction(
    String id, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) => TransactionApiClient.getTransaction(
    id,
    targetCurrency: targetCurrency,
    itemLanguage: itemLanguage,
    appLanguage: appLanguage,
  );

  static Future<void> deleteTransaction(String id) =>
      TransactionApiClient.deleteTransaction(id);

  static Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload, {
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) => TransactionApiClient.updateTransaction(
    id,
    payload,
    targetCurrency: targetCurrency,
    itemLanguage: itemLanguage,
    appLanguage: appLanguage,
  );

  static Future<void> deleteTransactionItem(
    String transactionId,
    String itemId,
  ) => TransactionApiClient.deleteTransactionItem(transactionId, itemId);

  static Future<List<dynamic>> listTransactions({
    DateTime? fromDate,
    String? merchantNameSearch,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? labelId,
    String? targetCurrency,
  }) => TransactionApiClient.listTransactions(
    fromDate: fromDate,
    merchantNameSearch: merchantNameSearch,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    labelId: labelId,
    targetCurrency: targetCurrency,
  );

  static Future<Map<String, dynamic>> getTransactionsSummary({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
    String? groupBy,
  }) => TransactionApiClient.getTransactionsSummary(
    fromDate: fromDate,
    toDate: toDate,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    targetCurrency: targetCurrency,
    groupBy: groupBy,
  );

  static Future<Map<String, dynamic>> getTransactionTrendSummary({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) => TransactionApiClient.getTransactionTrendSummary(
    fromDate: fromDate,
    toDate: toDate,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    targetCurrency: targetCurrency,
  );

  static Future<Map<String, dynamic>> getHouseholdAnalyticsSummary({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) => TransactionApiClient.getHouseholdAnalyticsSummary(
    fromDate: fromDate,
    toDate: toDate,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    targetCurrency: targetCurrency,
  );

  static Future<Map<String, dynamic>> getCategorySubcategorySummary({
    required String categoryId,
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
  }) => TransactionApiClient.getCategorySubcategorySummary(
    categoryId: categoryId,
    fromDate: fromDate,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    targetCurrency: targetCurrency,
  );

  static Future<Map<String, dynamic>> getSubcategoryItemsSummary({
    required String subcategoryId,
    DateTime? fromDate,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
    String? targetCurrency,
    String? itemLanguage,
    String? appLanguage,
  }) => TransactionApiClient.getSubcategoryItemsSummary(
    subcategoryId: subcategoryId,
    fromDate: fromDate,
    categoryIds: categoryIds,
    subcategoryIds: subcategoryIds,
    labelIds: labelIds,
    targetCurrency: targetCurrency,
    itemLanguage: itemLanguage,
    appLanguage: appLanguage,
  );

  static String _dateOnlyIso(DateTime value) {
    final normalized = DateTime(value.year, value.month, value.day);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  static Future<Map<String, dynamic>> getBudgetPlan() =>
      PlanningApiClient.getBudgetPlan();

  static Future<Map<String, dynamic>> updateBudgetPlan({
    required String currency,
    double? monthlyIncome,
    required List<Map<String, dynamic>> categoryLimits,
  }) => PlanningApiClient.updateBudgetPlan(
    currency: currency,
    monthlyIncome: monthlyIncome,
    categoryLimits: categoryLimits,
  );

  static Future<List<dynamic>> listBillReminders() =>
      PlanningApiClient.listBillReminders();

  static Future<Map<String, dynamic>> createBillReminder({
    required String name,
    required double amount,
    required String currency,
    required String recurrence,
    required DateTime firstDueDate,
    int remindDaysBefore = 3,
    bool isActive = true,
  }) => PlanningApiClient.createBillReminder(
    name: name,
    amount: amount,
    currency: currency,
    recurrence: recurrence,
    firstDueDate: firstDueDate,
    remindDaysBefore: remindDaysBefore,
    isActive: isActive,
  );

  static Future<Map<String, dynamic>> markBillReminderPaid({
    required String billId,
    required DateTime dueDate,
  }) =>
      PlanningApiClient.markBillReminderPaid(billId: billId, dueDate: dueDate);

  static Future<Map<String, dynamic>> skipBillReminder({
    required String billId,
    required DateTime dueDate,
  }) => PlanningApiClient.skipBillReminder(billId: billId, dueDate: dueDate);

  static Future<void> deleteBillReminder(String billId) =>
      PlanningApiClient.deleteBillReminder(billId);

  static Future<List<dynamic>> listCategories({bool includeDisabled = false}) =>
      TaxonomyApiClient.listCategories(includeDisabled: includeDisabled);

  static Future<Map<String, dynamic>> createCategory(
    String name, {
    String? parentId,
    String? icon,
    String? color,
  }) => TaxonomyApiClient.createCategory(
    name,
    parentId: parentId,
    icon: icon,
    color: color,
  );

  static Future<Map<String, dynamic>> updateCategory(
    String id, {
    String? name,
    String? parentId,
    String? icon,
    String? color,
  }) => TaxonomyApiClient.updateCategory(
    id,
    name: name,
    parentId: parentId,
    icon: icon,
    color: color,
  );

  static Future<void> deleteCategory(String id) =>
      TaxonomyApiClient.deleteCategory(id);

  static Future<Map<String, dynamic>> restoreCategory(String id) =>
      TaxonomyApiClient.restoreCategory(id);

  static Future<void> deleteReceipt(String id) =>
      ReceiptApiClient.deleteReceipt(id);

  static Future<List<dynamic>> listLabels() => LabelApiClient.listLabels();

  static Future<Map<String, dynamic>> createLabel(
    String name, {
    String? color,
  }) => LabelApiClient.createLabel(name, color: color);

  static Future<void> deleteLabel(String id) => LabelApiClient.deleteLabel(id);

  static Future<Map<String, dynamic>> assignLabel({
    required String transactionId,
    required String labelId,
  }) => LabelApiClient.assignLabel(
    transactionId: transactionId,
    labelId: labelId,
  );

  static Future<Map<String, dynamic>> unassignLabel({
    required String transactionId,
    required String labelId,
  }) => LabelApiClient.unassignLabel(
    transactionId: transactionId,
    labelId: labelId,
  );

  static Future<List<dynamic>> listFeatureRequests() =>
      FeatureRequestApiClient.listFeatureRequests();

  static Future<List<dynamic>> listMyFeatureRequests() =>
      FeatureRequestApiClient.listMyFeatureRequests();

  static Future<Map<String, dynamic>> createFeatureRequest({
    required String title,
    required String category,
    required String description,
  }) => FeatureRequestApiClient.createFeatureRequest(
    title: title,
    category: category,
    description: description,
  );

  static Future<Map<String, dynamic>> updateFeatureRequestVote({
    required String featureRequestId,
    required bool voted,
  }) => FeatureRequestApiClient.updateFeatureRequestVote(
    featureRequestId: featureRequestId,
    voted: voted,
  );

  static Future<Map<String, dynamic>> getMeSubscription() =>
      BillingApiClient.getMeSubscription();

  static Future<Map<String, dynamic>> getMeEntitlements() =>
      BillingApiClient.getMeEntitlements();

  static Future<Map<String, dynamic>> syncRevenueCatSubscription() =>
      BillingApiClient.syncRevenueCatSubscription();

  static Future<Map<String, dynamic>> applyDevManualSubscriptionAction({
    required String targetUserId,
    required String action,
    String productId = 'personal_premium',
    DateTime? expiresAt,
    String? reason,
  }) => BillingApiClient.applyDevManualSubscriptionAction(
    targetUserId: targetUserId,
    action: action,
    productId: productId,
    expiresAt: expiresAt,
    reason: reason,
  );

  static Future<Map<String, dynamic>> postItemTranslationsBatch(
    List<Map<String, String>> items,
  ) => ItemTranslationApiClient.postItemTranslationsBatch(items);

  static Future<Map<String, dynamic>> importData(
    Map<String, dynamic> payload,
  ) => DataTransferApiClient.importData(payload);

  static Future<Map<String, dynamic>> exportData() =>
      DataTransferApiClient.exportData();
}
