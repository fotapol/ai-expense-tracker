import 'dart:io';

import 'package:expense_tracker_app/core/receipt_document_scanner.dart';
import 'package:expense_tracker_app/core/receipt_image_processor.dart';
import 'package:expense_tracker_app/core/receipt_image_selection.dart';
import 'package:expense_tracker_app/core/receipt_scan_variant_builder.dart';
import 'package:expense_tracker_app/core/receipt_upload_flow.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/receipt_upload_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('receipt document scanner service', () {
    test('returns scan variants after successful ML Kit scan', () async {
      final variants = ReceiptScanVariants(
        croppedImagePath: 'cropped.jpg',
        processedImagePath: 'processed.jpg',
        croppedFileSizeBytes: 100,
        processedFileSizeBytes: 90,
        width: 320,
        height: 640,
        source: ReceiptImageSource.mlKitDocumentScanner,
      );
      final builder = _FakeVariantBuilder(variants);
      final service = ReceiptDocumentScannerService(
        launcher: _FakeDocumentScanLauncher(() async => ['cropped.jpg']),
        variantBuilder: builder,
        isAndroid: () => true,
      );

      final result = await service.scanReceipt();

      expect(result?.croppedImagePath, 'cropped.jpg');
      expect(result?.processedImagePath, 'processed.jpg');
      expect(builder.paths, ['cropped.jpg']);
    });

    test('returns null when scanner is cancelled', () async {
      final service = ReceiptDocumentScannerService(
        launcher: _FakeDocumentScanLauncher(
          () async => throw PlatformException(
            code: 'DocumentScanner',
            message: 'Operation cancelled',
          ),
        ),
        variantBuilder: _FakeVariantBuilder(
          const ReceiptScanVariants(
            croppedImagePath: 'unused.jpg',
            croppedFileSizeBytes: 1,
            source: ReceiptImageSource.mlKitDocumentScanner,
          ),
        ),
        isAndroid: () => true,
      );

      expect(await service.scanReceipt(), isNull);
    });

    test('throws unavailable when scanner is not supported', () async {
      final service = ReceiptDocumentScannerService(
        launcher: _FakeDocumentScanLauncher(() async => ['unused.jpg']),
        variantBuilder: _FakeVariantBuilder(
          const ReceiptScanVariants(
            croppedImagePath: 'unused.jpg',
            croppedFileSizeBytes: 1,
            source: ReceiptImageSource.mlKitDocumentScanner,
          ),
        ),
        isAndroid: () => false,
      );

      await expectLater(
        service.scanReceipt(),
        throwsA(isA<ReceiptScannerUnavailableException>()),
      );
    });
  });

  group('receipt image selection', () {
    test('uses cropped scan for preview and processed scan for upload', () {
      final selection = ReceiptImageSelection.fromScan(
        const ReceiptScanVariants(
          croppedImagePath: 'scan-crop.jpg',
          processedImagePath: 'scan-processed.jpg',
          croppedFileSizeBytes: 500,
          processedFileSizeBytes: 450,
          source: ReceiptImageSource.mlKitDocumentScanner,
        ),
      );

      expect(selection.previewImagePath, 'scan-crop.jpg');
      expect(selection.uploadImagePath, 'scan-processed.jpg');
      expect(selection.uploadFilename, 'receipt-scan.jpg');
      expect(selection.usesProcessedUpload, isTrue);
    });

    test('falls back to cropped scan when processed scan is oversized', () {
      final selection = ReceiptImageSelection.fromScan(
        const ReceiptScanVariants(
          croppedImagePath: 'scan-crop.jpg',
          processedImagePath: 'scan-processed.jpg',
          croppedFileSizeBytes: 500,
          processedFileSizeBytes: maxReceiptUploadBytes + 1,
          source: ReceiptImageSource.mlKitDocumentScanner,
        ),
      );

      expect(selection.previewImagePath, 'scan-crop.jpg');
      expect(selection.uploadImagePath, 'scan-crop.jpg');
      expect(selection.usesProcessedUpload, isFalse);
    });

    test('camera and gallery upload filenames do not expose cache names', () {
      final gallery = ReceiptImageSelection.fromPickedImage(
        imagePath: '/cache/scaled_12345.jpg',
        originalFilename: 'scaled_12345.jpg',
        fileSizeBytes: 100,
        source: ReceiptImageSource.gallery,
      );
      final camera = ReceiptImageSelection.fromPickedImage(
        imagePath: '/cache/image_picker_987.jpg',
        originalFilename: 'image_picker_987.jpg',
        fileSizeBytes: 100,
        source: ReceiptImageSource.camera,
      );

      expect(gallery.uploadFilename, 'receipt-gallery.jpg');
      expect(camera.uploadFilename, 'receipt-camera.jpg');
      expect(gallery.uploadFilename, isNot(contains('scaled_')));
      expect(camera.uploadFilename, isNot(contains('image_picker')));
    });
  });

  test('receipt image processor creates a valid conservative JPEG', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'receipt_processor_test_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final input = File('${tempDir.path}/input.jpg');
    final output = File('${tempDir.path}/processed.jpg');
    final source = img.Image(width: 64, height: 96);
    for (final pixel in source) {
      pixel
        ..r = 210
        ..g = 210
        ..b = 205;
    }
    await input.writeAsBytes(img.encodeJpg(source, quality: 95));

    final processed = await const ReceiptImageProcessor().processCroppedScan(
      croppedImagePath: input.path,
      processedImagePath: output.path,
    );

    expect(processed, isNotNull);
    expect(await output.exists(), isTrue);
    expect(processed!.fileSizeBytes, greaterThan(0));
    expect(processed.fileSizeBytes, lessThanOrEqualTo(maxReceiptUploadBytes));
    expect(processed.width, 64);
    expect(processed.height, 96);
  });

  group('receipt upload screen preview', () {
    testWidgets('shows user-facing preview copy without internal filenames', (
      tester,
    ) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('receipt_upload_preview_test_'),
      );
      expect(tempDir, isNotNull);
      addTearDown(() async {
        if (await tempDir!.exists()) await tempDir.delete(recursive: true);
      });
      final imageFile = await tester.runAsync(
        () => _writeTestJpeg(File('${tempDir!.path}/scaled_cache_receipt.jpg')),
      );
      expect(imageFile, isNotNull);
      final imageFileSize = await tester.runAsync(() => imageFile!.length());
      expect(imageFileSize, isNotNull);

      await tester.pumpWidget(
        _localizedApp(
          ReceiptUploadScreen(
            initialSelection: ReceiptImageSelection.fromPickedImage(
              imagePath: imageFile!.path,
              originalFilename: 'scaled_cache_receipt.jpg',
              fileSizeBytes: imageFileSize!,
              source: ReceiptImageSource.gallery,
            ),
            scanner: _FakeReceiptScanner(isSupported: false),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Receipt selected'), findsOneWidget);
      expect(
        find.text(
          'Review the image, choose another photo, or start extraction.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('scaled_'), findsNothing);
      expect(find.textContaining(tempDir!.path), findsNothing);
    });

    testWidgets('keeps scanner, camera, and gallery entrypoints available', (
      tester,
    ) async {
      await tester.pumpWidget(
        _localizedApp(
          ReceiptUploadScreen(scanner: _FakeReceiptScanner(isSupported: true)),
        ),
      );
      await tester.pump();

      expect(find.text('Scan receipt'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
    });
  });
}

Widget _localizedApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

Future<File> _writeTestJpeg(File file) async {
  final image = img.Image(width: 16, height: 24);
  for (final pixel in image) {
    pixel
      ..r = 235
      ..g = 235
      ..b = 230;
  }
  await file.writeAsBytes(img.encodeJpg(image, quality: 90), flush: true);
  return file;
}

class _FakeDocumentScanLauncher implements ReceiptDocumentScanLauncher {
  const _FakeDocumentScanLauncher(this.scan);

  final Future<List<String>?> Function() scan;

  @override
  Future<List<String>?> scanJpegPaths() => scan();
}

class _FakeVariantBuilder implements ReceiptScanVariantBuilder {
  _FakeVariantBuilder(this.variants);

  final ReceiptScanVariants variants;
  final List<String> paths = <String>[];

  @override
  Future<ReceiptScanVariants> buildFromCroppedImagePath(
    String imagePath,
  ) async {
    paths.add(imagePath);
    return variants;
  }
}

class _FakeReceiptScanner implements ReceiptScanner {
  const _FakeReceiptScanner({required this.isSupported});

  @override
  final bool isSupported;

  @override
  Future<ReceiptScanVariants?> scanReceipt() async => null;
}
