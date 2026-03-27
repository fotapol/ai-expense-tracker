import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/receipt_upload_flow.dart';
import '../l10n/app_localizations.dart';
import 'transaction_edit_screen.dart';

/// Receipt upload screen implementing the full presigned-URL upload flow:
/// pick image -> create receipt -> PUT to storage -> confirm -> poll until done.
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

  Future<void> _startUpload() async {
    if (!canStartReceiptUpload(hasPickedFile: _pickedFile != null, status: _status)) {
      return;
    }

    setState(() {
      _status = 'uploading';
      _progress = 0;
      _error = null;
    });

    try {
      final filename = _pickedFile!.name;
      final fileSizeBytes = await _pickedFile!.length();
      final upload = prepareReceiptUpload(
        filename: filename,
        fileSizeBytes: fileSizeBytes,
      );

      setState(() => _progress = 0.1);

      final createResult = await ApiClient.createReceipt(
        mimeType: upload.mimeType,
        originalFilename: upload.filename,
      );
      _receiptId = createResult['receipt_id'];
      final uploadUrl = createResult['upload_url'] as String;
      final requiredHeaders = Map<String, String>.from(
        createResult['required_headers'] as Map,
      );

      setState(() => _progress = 0.3);

      final fileBytes = await _pickedFile!.readAsBytes();
      await ApiClient.uploadToPresignedUrl(
        uploadUrl: uploadUrl,
        fileBytes: fileBytes,
        requiredHeaders: requiredHeaders,
      );

      setState(() => _progress = 0.6);

      await ApiClient.confirmUpload(_receiptId!);

      setState(() {
        _status = 'processing';
        _progress = 0.7;
      });

      await _pollReceiptStatus();
    } catch (e) {
      setState(() {
        _status = 'failed';
        _error = formatReceiptUploadError(e);
      });
    }
  }

  Future<void> _pollReceiptStatus() async {
    const maxAttempts = 60;
    for (int i = 0; i < maxAttempts; i++) {
      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      try {
        final data = await ApiClient.getReceiptStatus(_receiptId!);
        if (!mounted) return;
        final decision = interpretReceiptPollingPayload(
          data,
          missingTransactionMessage:
              'Receipt processing finished, but no transaction was returned.',
          extractionFailedFallback: context.tr('upload_extraction_failed'),
        );

        if (decision.action == ReceiptPollingAction.completed) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  TransactionEditScreen(transactionId: decision.transactionId!),
            ),
          );
          return;
        }

        if (decision.action == ReceiptPollingAction.failed) {
          setState(() {
            _status = 'failed';
            _error = decision.errorMessage;
          });
          return;
        }

        setState(() {
          _progress = 0.7 + (0.25 * (i / maxAttempts));
        });
      } catch (e) {
        final permanentMessage = permanentReceiptPollingErrorMessage(e);
        if (permanentMessage != null) {
          setState(() {
            _status = 'failed';
            _error = permanentMessage;
          });
          return;
        }
        debugPrint('Transient poll error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _status = 'failed';
        _error = context.tr('upload_timed_out');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('upload_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  onPressed:
                      canStartReceiptUpload(
                        hasPickedFile: _pickedFile != null,
                        status: _status,
                      )
                      ? _startUpload
                      : null,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(context.tr('upload_action_extract')),
                ),
            ],
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
