import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

class ReceiptPhotoViewScreen extends StatelessWidget {
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'expense_tracker_app/media_store',
  );

  const ReceiptPhotoViewScreen({
    super.key,
    required this.title,
    required this.viewUrl,
    required this.mimeType,
  });

  final String title;
  final String viewUrl;
  final String mimeType;

  bool get _isImage => mimeType.toLowerCase().startsWith('image/');

  String _resolvedFilename() {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final uri = Uri.tryParse(viewUrl);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return lastSegment.isNotEmpty ? lastSegment : 'receipt';
  }

  Future<String?> _saveToPublicAndroidMediaStore(Uint8List bytes) async {
    try {
      return await _mediaStoreChannel.invokeMethod<String>(
        'saveFile',
        <String, dynamic>{
          'bytes': bytes,
          'filename': _resolvedFilename(),
          'mimeType': mimeType.isNotEmpty
              ? mimeType
              : 'application/octet-stream',
        },
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> _downloadFile(BuildContext context) async {
    final uri = Uri.tryParse(viewUrl);
    final invalidUrlText = context.tr('receipt_photo_invalid_url');
    final galleryLabel = context.tr('upload_gallery');
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(invalidUrlText)),
      );
      return;
    }

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      String savedLocation;
      if (Platform.isAndroid) {
        final publicUri = await _saveToPublicAndroidMediaStore(
          response.bodyBytes,
        );
        if (publicUri != null && publicUri.isNotEmpty) {
          savedLocation = _isImage ? galleryLabel : 'Downloads';
        } else {
          final downloadsDirectory = await getDownloadsDirectory();
          final fallbackDirectory = await getApplicationDocumentsDirectory();
          final targetDirectory = downloadsDirectory ?? fallbackDirectory;
          final file = File('${targetDirectory.path}/${_resolvedFilename()}');
          await file.writeAsBytes(response.bodyBytes, flush: true);
          savedLocation = file.path;
        }
      } else {
        final downloadsDirectory = await getDownloadsDirectory();
        final fallbackDirectory = await getApplicationDocumentsDirectory();
        final targetDirectory = downloadsDirectory ?? fallbackDirectory;
        final file = File('${targetDirectory.path}/${_resolvedFilename()}');
        await file.writeAsBytes(response.bodyBytes, flush: true);
        savedLocation = file.path;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'receipt_photo_downloaded',
              params: {'path': savedLocation},
            ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openExternally(BuildContext context) async {
    final uri = Uri.tryParse(viewUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('receipt_photo_invalid_url'))),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return;

    await Clipboard.setData(ClipboardData(text: viewUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('receipt_photo_open_fallback'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              onPressed: () => _downloadFile(context),
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              onPressed: () => _openExternally(context),
              icon: const Icon(Icons.open_in_new),
            ),
          ],
        ),
        body: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Center(
            child: Image.network(
              viewUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stackTrace) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image_outlined, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        context.tr('receipt_photo_load_failed'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openExternally(context),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(context.tr('receipt_photo_open_external')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                context.tr('receipt_photo_non_image_hint'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                mimeType,
                style: TextStyle(color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _downloadFile(context),
                icon: const Icon(Icons.download_outlined),
                label: Text(context.tr('receipt_photo_download')),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openExternally(context),
                icon: const Icon(Icons.open_in_new),
                label: Text(context.tr('receipt_photo_open_external')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
