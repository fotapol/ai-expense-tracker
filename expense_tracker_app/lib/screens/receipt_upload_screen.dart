import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/receipt_upload_flow.dart';
import '../core/session_invalidation.dart';
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
  int _processingPollAttempts = 0;

  final ImagePicker _picker = ImagePicker();

  String _friendlyUploadError(Object error) {
    return friendlyLaunchErrorMessage(
      error,
      fallback: 'We could not finish the receipt upload. Please try again.',
    );
  }

  String _processingHeadline() {
    switch (_status) {
      case 'uploading':
        return 'Uploading your receipt...';
      case 'processing':
        return 'Processing your receipt...';
      default:
        return 'Ready to scan';
    }
  }

  String _processingBody() {
    switch (_status) {
      case 'uploading':
        return 'We are sending the photo to your account now. This usually only takes a moment.';
      case 'processing':
        return 'This can take a few seconds. We will show the extracted merchant, total, and items for review before anything is saved.';
      default:
        return 'Choose a clear receipt photo and review the extracted details before saving.';
    }
  }

  int _currentProcessingStage() {
    switch (_status) {
      case 'uploading':
        return 0;
      case 'processing':
        return _processingPollAttempts < 2 ? 1 : 2;
      default:
        return -1;
    }
  }

  Widget _buildProcessingStep({
    required int stepIndex,
    required String title,
    required String body,
  }) {
    final currentStep = _currentProcessingStage();
    final isComplete = currentStep > stepIndex;
    final isActive = currentStep == stepIndex;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color muted = Theme.of(context).colorScheme.outline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isComplete || isActive
                ? accent.withAlpha(isComplete ? 255 : 24)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: isComplete || isActive ? accent : muted),
          ),
          child: isComplete
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Icon(
                  isActive ? Icons.more_horiz : Icons.circle_outlined,
                  size: 14,
                  color: isActive ? accent : muted,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  height: 1.35,
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
        _error = _friendlyUploadError(
          context.tr('upload_pick_failed', params: {'error': e.toString()}),
        );
      });
    }
  }

  Future<void> _startUpload() async {
    if (!canStartReceiptUpload(
      hasPickedFile: _pickedFile != null,
      status: _status,
    )) {
      return;
    }

    setState(() {
      _status = 'uploading';
      _progress = 0;
      _error = null;
      _processingPollAttempts = 0;
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
      if (await maybeHandleExpiredSession(e)) return;
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
      _processingPollAttempts = i + 1;

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
            _error = _friendlyUploadError(
              decision.errorMessage ?? context.tr('upload_extraction_failed'),
            );
          });
          return;
        }

        setState(() {
          _progress = 0.7 + (0.25 * (i / maxAttempts));
        });
      } catch (e) {
        if (await maybeHandleExpiredSession(e)) return;
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
        _error =
            'We could not finish reading this receipt in time. Please try again.';
      });
    }
  }

  Widget _buildGuidanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Scan with confidence',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            'Use a clear, flat photo with the full receipt in frame. Files up to 10 MB are supported, and you will review every extracted detail before anything is saved.',
            style: TextStyle(height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  value: _status == 'processing' ? null : _progress,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _processingHeadline(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _processingBody(),
                      style: const TextStyle(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildProcessingStep(
            stepIndex: 0,
            title: 'Upload receipt',
            body: 'Store the photo securely in your account.',
          ),
          const SizedBox(height: 12),
          _buildProcessingStep(
            stepIndex: 1,
            title: 'Read totals and items',
            body: 'Extract the merchant, total, and line items.',
          ),
          const SizedBox(height: 12),
          _buildProcessingStep(
            stepIndex: 2,
            title: 'Open review',
            body: 'Prepare the editable review screen before saving.',
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
        ],
      ),
    );
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
            if (_status == 'idle') ...[
              _buildGuidanceCard(),
              const SizedBox(height: 18),
            ],
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
              _buildProcessingCard(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.red.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
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
                      _processingPollAttempts = 0;
                    });
                  },
                  child: const Text('Try this receipt again'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
