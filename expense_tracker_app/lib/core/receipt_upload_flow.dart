import 'dart:async';
import 'dart:io';

enum ReceiptPollingAction { pending, completed, failed }

const int maxReceiptUploadBytes = 10 * 1024 * 1024;
const Set<String> supportedReceiptUploadExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'pdf',
};

class ReceiptUploadValidationException implements Exception {
  const ReceiptUploadValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PreparedReceiptUpload {
  const PreparedReceiptUpload({
    required this.filename,
    required this.mimeType,
    required this.fileSizeBytes,
  });

  final String filename;
  final String mimeType;
  final int fileSizeBytes;
}

bool canStartReceiptUpload({
  required bool hasPickedFile,
  required String status,
}) {
  return hasPickedFile && status == 'idle';
}

PreparedReceiptUpload prepareReceiptUpload({
  required String filename,
  required int fileSizeBytes,
  int maximumFileSizeBytes = maxReceiptUploadBytes,
}) {
  final normalizedFilename = filename.trim();
  final extension = normalizedFilename.contains('.')
      ? normalizedFilename.split('.').last.toLowerCase()
      : '';

  if (!supportedReceiptUploadExtensions.contains(extension)) {
    throw const ReceiptUploadValidationException(
      'Unsupported receipt file type. Please upload a JPG, PNG, WEBP, HEIC, HEIF, or PDF file.',
    );
  }

  if (fileSizeBytes <= 0) {
    throw const ReceiptUploadValidationException(
      'The selected receipt file is empty. Please choose a different file.',
    );
  }

  if (fileSizeBytes > maximumFileSizeBytes) {
    final maxSizeMb = (maximumFileSizeBytes / (1024 * 1024)).toStringAsFixed(0);
    throw ReceiptUploadValidationException(
      'Receipt files larger than $maxSizeMb MB are not supported in this launch build.',
    );
  }

  return PreparedReceiptUpload(
    filename: normalizedFilename,
    mimeType: _mimeForReceiptExtension(extension),
    fileSizeBytes: fileSizeBytes,
  );
}

String _mimeForReceiptExtension(String extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'pdf':
      return 'application/pdf';
    default:
      throw const ReceiptUploadValidationException(
        'Unsupported receipt file type.',
      );
  }
}

String formatReceiptUploadError(Object error) {
  if (error is ReceiptUploadValidationException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'The receipt upload timed out. Please check your connection and try again.';
  }
  if (error is SocketException) {
    return 'You appear to be offline. Please reconnect and try the upload again.';
  }

  final message = error.toString().trim();
  final normalized = message.toLowerCase();
  if (normalized.contains('socketexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network is unreachable')) {
    return 'You appear to be offline. Please reconnect and try the upload again.';
  }
  if (normalized.contains('timed out')) {
    return 'The receipt upload timed out. Please check your connection and try again.';
  }
  return message;
}

class ReceiptPollingDecision {
  const ReceiptPollingDecision._({
    required this.action,
    this.transactionId,
    this.errorMessage,
  });

  const ReceiptPollingDecision.pending()
    : this._(action: ReceiptPollingAction.pending);

  const ReceiptPollingDecision.completed(String transactionId)
    : this._(
        action: ReceiptPollingAction.completed,
        transactionId: transactionId,
      );

  const ReceiptPollingDecision.failed(String errorMessage)
    : this._(
        action: ReceiptPollingAction.failed,
        errorMessage: errorMessage,
      );

  final ReceiptPollingAction action;
  final String? transactionId;
  final String? errorMessage;
}

ReceiptPollingDecision interpretReceiptPollingPayload(
  Map<String, dynamic> payload, {
  required String missingTransactionMessage,
  required String extractionFailedFallback,
}) {
  final status = payload['status']?.toString().toUpperCase() ?? '';
  switch (status) {
    case 'COMPLETED':
      final transactionId = payload['transaction_id']?.toString().trim();
      if (transactionId == null || transactionId.isEmpty) {
        return ReceiptPollingDecision.failed(missingTransactionMessage);
      }
      return ReceiptPollingDecision.completed(transactionId);
    case 'FAILED':
      final failureReason = payload['failure_reason']?.toString().trim();
      if (failureReason != null && failureReason.isNotEmpty) {
        return ReceiptPollingDecision.failed(failureReason);
      }
      return ReceiptPollingDecision.failed(extractionFailedFallback);
    default:
      return const ReceiptPollingDecision.pending();
  }
}

String? permanentReceiptPollingErrorMessage(Object error) {
  final message = error.toString();
  final normalized = message.toLowerCase();
  if (normalized.contains('no authenticated user') ||
      normalized.contains(' 401') ||
      normalized.contains(': 401')) {
    return 'Your session expired. Please sign in again.';
  }
  if (normalized.contains(' 403') || normalized.contains(': 403')) {
    return 'This receipt is no longer accessible. Please refresh and try again.';
  }
  if (normalized.contains(' 404') || normalized.contains(': 404')) {
    return 'This receipt could not be found anymore. Please upload it again.';
  }
  return null;
}
