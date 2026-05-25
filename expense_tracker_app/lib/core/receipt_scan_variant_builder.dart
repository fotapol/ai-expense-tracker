import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'receipt_image_processor.dart';
import 'receipt_image_selection.dart';
import 'receipt_upload_flow.dart';

abstract class ReceiptScanVariantBuilder {
  Future<ReceiptScanVariants> buildFromCroppedImagePath(String imagePath);
}

class ReceiptImageVariantBuilder implements ReceiptScanVariantBuilder {
  const ReceiptImageVariantBuilder({
    this.processor = const ReceiptImageProcessor(),
  });

  final ReceiptImageProcessor processor;

  @override
  Future<ReceiptScanVariants> buildFromCroppedImagePath(
    String imagePath,
  ) async {
    final sourceFile = File(imagePath);
    if (!await sourceFile.exists() || await sourceFile.length() <= 0) {
      throw const ReceiptScanVariantException('Scanned image is empty.');
    }

    final directory = await _receiptScanTempDirectory();
    final token = DateTime.now().microsecondsSinceEpoch.toString();
    final croppedPath = p.join(
      directory.path,
      'receipt_scan_${token}_crop.jpg',
    );
    final processedPath = p.join(
      directory.path,
      'receipt_scan_${token}_processed.jpg',
    );

    await sourceFile.copy(croppedPath);
    await _deleteSourceScannerFile(sourceFile, copiedPath: croppedPath);
    final croppedSize = await File(croppedPath).length();

    ReceiptProcessedImage? processed;
    try {
      processed = await processor.processCroppedScan(
        croppedImagePath: croppedPath,
        processedImagePath: processedPath,
        maxFileSizeBytes: maxReceiptUploadBytes,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Receipt scan processing failed: $error');
      }
      await deleteReceiptTemporaryFiles(<String>[processedPath]);
    }

    if (kDebugMode) {
      debugPrint(
        'Receipt scan variants: cropped=$croppedPath processed=${processed?.path}',
      );
    }

    return ReceiptScanVariants(
      croppedImagePath: croppedPath,
      processedImagePath: processed?.path,
      width: processed?.width,
      height: processed?.height,
      croppedFileSizeBytes: croppedSize,
      processedFileSizeBytes: processed?.fileSizeBytes,
      source: ReceiptImageSource.mlKitDocumentScanner,
    );
  }

  Future<void> _deleteSourceScannerFile(
    File sourceFile, {
    required String copiedPath,
  }) async {
    if (p.equals(sourceFile.path, copiedPath)) return;
    try {
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    } catch (_) {
      // The copied cropped variant is now app-owned; source cleanup is best-effort.
    }
  }

  Future<Directory> _receiptScanTempDirectory() async {
    final tempDirectory = await getTemporaryDirectory();
    final directory = Directory(p.join(tempDirectory.path, 'receipt_scans'));
    return directory.create(recursive: true);
  }
}

class ReceiptScanVariantException implements Exception {
  const ReceiptScanVariantException(this.message);

  final String message;

  @override
  String toString() => message;
}
