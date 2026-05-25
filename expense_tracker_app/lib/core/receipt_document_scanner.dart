import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import 'receipt_image_selection.dart';
import 'receipt_scan_variant_builder.dart';

abstract class ReceiptScanner {
  bool get isSupported;

  Future<ReceiptScanVariants?> scanReceipt();
}

abstract class ReceiptDocumentScanLauncher {
  Future<List<String>?> scanJpegPaths();
}

class MlKitDocumentScanLauncher implements ReceiptDocumentScanLauncher {
  @override
  Future<List<String>?> scanJpegPaths() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: 1,
        mode: ScannerMode.full,
        isGalleryImport: false,
      ),
    );

    try {
      final result = await scanner.scanDocument();
      return result.images;
    } finally {
      try {
        await scanner.close();
      } catch (_) {
        // Closing native scanner handles is best-effort after scan/cancel.
      }
    }
  }
}

class ReceiptDocumentScannerService implements ReceiptScanner {
  ReceiptDocumentScannerService({
    ReceiptDocumentScanLauncher? launcher,
    ReceiptScanVariantBuilder? variantBuilder,
    bool Function()? isAndroid,
  }) : _launcher = launcher ?? MlKitDocumentScanLauncher(),
       _variantBuilder = variantBuilder ?? const ReceiptImageVariantBuilder(),
       _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final ReceiptDocumentScanLauncher _launcher;
  final ReceiptScanVariantBuilder _variantBuilder;
  final bool Function() _isAndroid;

  @override
  bool get isSupported => _isAndroid();

  @override
  Future<ReceiptScanVariants?> scanReceipt() async {
    if (!isSupported) {
      throw const ReceiptScannerUnavailableException(
        'Document scanner is only available on Android.',
      );
    }

    List<String>? imagePaths;
    try {
      imagePaths = await _launcher.scanJpegPaths();
    } on PlatformException catch (error) {
      if (isReceiptScannerCancel(error)) return null;
      throw ReceiptScannerUnavailableException(error.message ?? error.code);
    }

    final croppedPath = _firstUsableImagePath(imagePaths);
    if (croppedPath == null) {
      throw const ReceiptScannerException('No scanned receipt image returned.');
    }

    if (kDebugMode) {
      debugPrint('ML Kit scanner returned cropped receipt path: $croppedPath');
    }

    try {
      return await _variantBuilder.buildFromCroppedImagePath(croppedPath);
    } catch (error) {
      throw ReceiptScannerException(error.toString());
    }
  }
}

bool isReceiptScannerCancel(Object error) {
  if (error is! PlatformException) return false;
  final text = '${error.code} ${error.message ?? ''} ${error.details ?? ''}'
      .toLowerCase();
  return text.contains('cancel') || text.contains('cancelled');
}

String? _firstUsableImagePath(List<String>? paths) {
  if (paths == null) return null;
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

class ReceiptScannerUnavailableException implements Exception {
  const ReceiptScannerUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptScannerException implements Exception {
  const ReceiptScannerException(this.message);

  final String message;

  @override
  String toString() => message;
}
