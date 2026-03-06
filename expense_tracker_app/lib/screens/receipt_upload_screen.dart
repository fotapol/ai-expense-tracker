import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'transaction_edit_screen.dart';

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';

/// Receipt upload screen implementing the full presigned-URL upload flow:
/// pick image → create receipt → PUT to MinIO → confirm → poll until done.
class ReceiptUploadScreen extends StatefulWidget {
  const ReceiptUploadScreen({super.key});

  @override
  State<ReceiptUploadScreen> createState() => _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends State<ReceiptUploadScreen> {
  XFile? _pickedFile;
  String _status = 'idle'; // idle | uploading | processing | failed
  String? _receiptId;
  String? _error;
  double _progress = 0;

  final ImagePicker _picker = ImagePicker();

  // -------------------------------------------------------
  // Image picking
  // -------------------------------------------------------

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file != null) {
        setState(() {
          _pickedFile = file;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = context.tr(
          'upload_pick_failed',
          params: {'error': e.toString()},
        );
      });
    }
  }

  // -------------------------------------------------------
  // Upload flow
  // -------------------------------------------------------

  Future<void> _startUpload() async {
    if (_pickedFile == null) return;

    setState(() {
      _status = 'uploading';
      _progress = 0;
      _error = null;
    });

    try {
      // 1. Determine mime type
      final ext = _pickedFile!.path.split('.').last.toLowerCase();
      final mimeType = _mimeForExtension(ext);
      final filename = _pickedFile!.name;

      setState(() => _progress = 0.1);

      // 2. Create receipt → get presigned URL
      final createResult = await ApiClient.createReceipt(
        mimeType: mimeType,
        originalFilename: filename,
      );
      _receiptId = createResult['receipt_id'];
      final uploadUrl = createResult['upload_url'] as String;
      final requiredHeaders = Map<String, String>.from(
        createResult['required_headers'] as Map,
      );

      setState(() => _progress = 0.3);

      // 3. Upload file bytes to presigned URL
      final fileBytes = await _pickedFile!.readAsBytes();
      await ApiClient.uploadToPresignedUrl(
        uploadUrl: uploadUrl,
        fileBytes: fileBytes,
        requiredHeaders: requiredHeaders,
      );

      setState(() => _progress = 0.6);

      // 4. Confirm upload
      await ApiClient.confirmUpload(_receiptId!);

      setState(() {
        _status = 'processing';
        _progress = 0.7;
      });

      // 5. Poll until COMPLETED or FAILED
      await _pollReceiptStatus();
    } catch (e) {
      setState(() {
        _status = 'failed';
        _error = e.toString();
      });
    }
  }

  Future<void> _pollReceiptStatus() async {
    const maxAttempts = 60; // 2 minutes max
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      try {
        final data = await ApiClient.getReceiptStatus(_receiptId!);
        final status = data['status'] as String;

        if (status == 'COMPLETED') {
          final txId = data['transaction_id']?.toString();
          if (txId != null && mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TransactionEditScreen(transactionId: txId),
              ),
            );
          }
          return;
        } else if (status == 'FAILED') {
          setState(() {
            _status = 'failed';
            _error =
                data['failure_reason']?.toString() ??
                context.tr('upload_extraction_failed');
          });
          return;
        }

        // Still processing
        setState(() {
          _progress = 0.7 + (0.25 * (i / maxAttempts));
        });
      } catch (e) {
        // Network hiccup — keep polling
        debugPrint('Poll error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _status = 'failed';
        _error = context.tr('upload_timed_out');
      });
    }
  }

  String _mimeForExtension(String ext) {
    switch (ext) {
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
        return 'image/jpeg';
    }
  }

  // -------------------------------------------------------
  // UI
  // -------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('upload_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image preview
            if (_pickedFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_pickedFile!.path),
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _pickedFile!.name,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],

            // Pick buttons
            if (_status == 'idle') ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: Text(context.tr('upload_gallery')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: Text(context.tr('upload_camera')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_pickedFile != null)
                FilledButton.icon(
                  onPressed: _startUpload,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(context.tr('upload_action_extract')),
                ),
            ],

            // Progress
            if (_status == 'uploading' || _status == 'processing') ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Text(
                _status == 'uploading'
                    ? context.tr('upload_status_uploading')
                    : context.tr('upload_status_processing'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
              const SizedBox(height: 12),
              if (_status == 'failed')
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _status = 'idle';
                      _error = null;
                      _progress = 0;
                    });
                  },
                  child: Text(context.tr('upload_try_again')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
