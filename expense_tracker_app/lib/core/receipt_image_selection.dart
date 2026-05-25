import 'dart:io';

import 'receipt_upload_flow.dart';

enum ReceiptImageSource { camera, gallery, mlKitDocumentScanner }

class ReceiptScanVariants {
  const ReceiptScanVariants({
    required this.croppedImagePath,
    required this.croppedFileSizeBytes,
    required this.source,
    this.processedImagePath,
    this.processedFileSizeBytes,
    this.width,
    this.height,
  });

  final String croppedImagePath;
  final String? processedImagePath;
  final int? width;
  final int? height;
  final int croppedFileSizeBytes;
  final int? processedFileSizeBytes;
  final ReceiptImageSource source;

  List<String> get ownedTemporaryPaths {
    final paths = <String>[croppedImagePath];
    final processedPath = processedImagePath;
    if (processedPath != null && processedPath != croppedImagePath) {
      paths.add(processedPath);
    }
    return paths;
  }
}

class ReceiptImageSelection {
  const ReceiptImageSelection({
    required this.previewImagePath,
    required this.uploadImagePath,
    required this.uploadFilename,
    required this.uploadFileSizeBytes,
    required this.source,
    this.scanVariants,
    this.ownedTemporaryPaths = const <String>[],
  });

  factory ReceiptImageSelection.fromScan(
    ReceiptScanVariants variants, {
    int maxUploadBytes = maxReceiptUploadBytes,
  }) {
    final processedPath = variants.processedImagePath;
    final processedSize = variants.processedFileSizeBytes;
    final useProcessed =
        processedPath != null &&
        processedPath.isNotEmpty &&
        processedSize != null &&
        processedSize > 0 &&
        processedSize <= maxUploadBytes;

    return ReceiptImageSelection(
      previewImagePath: variants.croppedImagePath,
      uploadImagePath: useProcessed ? processedPath : variants.croppedImagePath,
      uploadFilename: safeReceiptUploadFilenameForSource(
        ReceiptImageSource.mlKitDocumentScanner,
      ),
      uploadFileSizeBytes: useProcessed
          ? processedSize
          : variants.croppedFileSizeBytes,
      source: ReceiptImageSource.mlKitDocumentScanner,
      scanVariants: variants,
      ownedTemporaryPaths: variants.ownedTemporaryPaths,
    );
  }

  factory ReceiptImageSelection.fromPickedImage({
    required String imagePath,
    required String originalFilename,
    required int fileSizeBytes,
    required ReceiptImageSource source,
  }) {
    return ReceiptImageSelection(
      previewImagePath: imagePath,
      uploadImagePath: imagePath,
      uploadFilename: safeReceiptUploadFilenameForSource(
        source,
        originalFilename: originalFilename,
      ),
      uploadFileSizeBytes: fileSizeBytes,
      source: source,
    );
  }

  final String previewImagePath;
  final String uploadImagePath;
  final String uploadFilename;
  final int uploadFileSizeBytes;
  final ReceiptImageSource source;
  final ReceiptScanVariants? scanVariants;
  final List<String> ownedTemporaryPaths;

  bool get usesProcessedUpload =>
      scanVariants?.processedImagePath != null &&
      uploadImagePath == scanVariants?.processedImagePath;
}

String safeReceiptUploadFilenameForSource(
  ReceiptImageSource source, {
  String? originalFilename,
}) {
  switch (source) {
    case ReceiptImageSource.mlKitDocumentScanner:
      return 'receipt-scan.jpg';
    case ReceiptImageSource.camera:
      return 'receipt-camera.jpg';
    case ReceiptImageSource.gallery:
      return 'receipt-gallery.${_safeReceiptImageExtension(originalFilename)}';
  }
}

String _safeReceiptImageExtension(String? filename) {
  final normalized = filename?.trim().toLowerCase() ?? '';
  final extension = normalized.contains('.')
      ? normalized.split('.').last
      : 'jpg';
  if (extension == 'pdf') return 'jpg';
  if (supportedReceiptUploadExtensions.contains(extension)) {
    return extension == 'jpeg' ? 'jpg' : extension;
  }
  return 'jpg';
}

Future<void> deleteReceiptTemporaryFiles(Iterable<String> paths) async {
  final uniquePaths = <String>{
    for (final path in paths)
      if (path.trim().isNotEmpty) path,
  };

  for (final path in uniquePaths) {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cache cleanup must not interrupt upload or navigation.
    }
  }
}
