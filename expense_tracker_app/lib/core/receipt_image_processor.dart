import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'receipt_upload_flow.dart';

class ReceiptProcessedImage {
  const ReceiptProcessedImage({
    required this.path,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
  });

  final String path;
  final int fileSizeBytes;
  final int width;
  final int height;
}

class ReceiptImageProcessor {
  const ReceiptImageProcessor();

  Future<ReceiptProcessedImage?> processCroppedScan({
    required String croppedImagePath,
    required String processedImagePath,
    int maxFileSizeBytes = maxReceiptUploadBytes,
  }) {
    return Isolate.run(
      () => _processCroppedScanSync(
        croppedImagePath: croppedImagePath,
        processedImagePath: processedImagePath,
        maxFileSizeBytes: maxFileSizeBytes,
      ),
    );
  }
}

ReceiptProcessedImage? _processCroppedScanSync({
  required String croppedImagePath,
  required String processedImagePath,
  required int maxFileSizeBytes,
}) {
  final inputFile = File(croppedImagePath);
  if (!inputFile.existsSync() || inputFile.lengthSync() <= 0) {
    return null;
  }

  final decoded = img.decodeImage(inputFile.readAsBytesSync());
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    return null;
  }

  final oriented = img.bakeOrientation(decoded);
  var working = img.Image.from(oriented);
  final averageLuminance = _averageLuminance(working);

  working = img.histogramStretch(
    working,
    outputRangeMin: 0,
    outputRangeMax: 246,
    stretchClipRatio: 0.006,
  );

  final brightness = averageLuminance < 96
      ? 1.045
      : averageLuminance < 122
      ? 1.02
      : 1.0;
  working = img.adjustColor(
    working,
    brightness: brightness,
    contrast: 1.02,
    amount: 0.5,
  );
  working = img.smooth(working, weight: 1.04);

  final outputFile = File(processedImagePath);
  outputFile.parent.createSync(recursive: true);

  for (final quality in const <int>[90, 86, 82]) {
    final encoded = img.encodeJpg(working, quality: quality);
    if (encoded.isEmpty) continue;

    outputFile.writeAsBytesSync(encoded, flush: true);
    final size = outputFile.lengthSync();
    if (size > 0 && size <= maxFileSizeBytes) {
      return ReceiptProcessedImage(
        path: processedImagePath,
        fileSizeBytes: size,
        width: working.width,
        height: working.height,
      );
    }
  }

  if (outputFile.existsSync()) {
    outputFile.deleteSync();
  }
  return null;
}

double _averageLuminance(img.Image image) {
  final stepX = math.max(1, image.width ~/ 80);
  final stepY = math.max(1, image.height ~/ 80);
  var total = 0.0;
  var count = 0;

  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      final pixel = image.getPixel(x, y);
      total += (0.2126 * pixel.r) + (0.7152 * pixel.g) + (0.0722 * pixel.b);
      count += 1;
    }
  }

  return count == 0 ? 128 : total / count;
}
