import 'dart:async';

const Duration coreApiRequestTimeout = Duration(seconds: 20);
const Duration coreUploadRequestTimeout = Duration(seconds: 60);
const Duration coreBillingRequestTimeout = Duration(seconds: 15);

Future<T> runWithCoreRequestTimeout<T>(
  Future<T> future, {
  required String operationName,
  Duration timeout = coreApiRequestTimeout,
}) {
  return future.timeout(
    timeout,
    onTimeout: () {
      throw TimeoutException(
        '$operationName timed out after ${timeout.inSeconds} seconds.',
      );
    },
  );
}
