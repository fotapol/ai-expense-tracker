import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/receipt_upload_flow.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';
import 'transaction_edit_screen.dart';

enum _ReceiptPickSource { camera, gallery }

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
  _ReceiptPickSource? _lastPickSource;

  final ImagePicker _picker = ImagePicker();

  bool get _isBusy => _status == 'uploading' || _status == 'processing';

  String _friendlyUploadError(Object error) {
    return friendlyLaunchErrorMessage(
      error,
      fallback: context.tr('error_receipt_extraction_failed'),
    );
  }

  String _processingHeadline() {
    switch (_status) {
      case 'uploading':
        return context.tr('upload_status_uploading');
      case 'processing':
        return context.tr('upload_status_processing');
      default:
        return context.tr('quick_scan_with_ai_review');
    }
  }

  String _processingBody() {
    switch (_status) {
      case 'uploading':
        return context.tr('upload_status_uploading');
      case 'processing':
        return context.tr('upload_status_processing');
      default:
        return context.tr('home_start_subtitle');
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
    final accent = ShellStyles.accent(context);
    final muted = ShellStyles.border(context);

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
              ? Icon(
                  Icons.check,
                  size: 14,
                  color: Theme.of(context).colorScheme.onPrimary,
                )
              : Icon(
                  isActive ? Icons.more_horiz : Icons.circle_outlined,
                  size: 14,
                  color: isActive ? accent : ShellStyles.textMuted(context),
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
                  fontSize: ShellStyles.scaled(context, 13, min: 12, max: 14),
                  fontWeight: FontWeight.w700,
                  color: ShellStyles.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  height: 1.35,
                  fontSize: ShellStyles.scaled(context, 12, min: 11, max: 13),
                  color: ShellStyles.textMuted(context),
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
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file != null) {
        setState(() {
          _pickedFile = file;
          _status = 'idle';
          _error = null;
          _progress = 0;
          _processingPollAttempts = 0;
          _lastPickSource = source == ImageSource.camera
              ? _ReceiptPickSource.camera
              : _ReceiptPickSource.gallery;
        });
      }
    } catch (error) {
      setState(() {
        _error = _friendlyUploadError(
          context.tr('upload_pick_failed', params: {'error': error.toString()}),
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
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      setState(() {
        _status = 'failed';
        _error = formatReceiptUploadError(error);
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
          missingTransactionMessage: context.tr('upload_extraction_failed'),
          extractionFailedFallback: context.tr(
            'error_receipt_extraction_failed',
          ),
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
      } catch (error) {
        if (await maybeHandleExpiredSession(error)) return;
        final permanentMessage = permanentReceiptPollingErrorMessage(error);
        if (permanentMessage != null) {
          setState(() {
            _status = 'failed';
            _error = permanentMessage;
          });
          return;
        }
        debugPrint('Transient poll error: $error');
      }
    }

    if (mounted) {
      setState(() {
        _status = 'failed';
        _error = context.tr('upload_timed_out');
      });
    }
  }

  void _clearFailure({bool keepSelection = true}) {
    setState(() {
      _status = 'idle';
      _error = null;
      _progress = 0;
      _processingPollAttempts = 0;
      if (!keepSelection) {
        _pickedFile = null;
        _lastPickSource = null;
      }
    });
  }

  Widget _buildIntroCard() {
    return Container(
      padding: EdgeInsets.all(
        ShellStyles.scaled(context, 18, min: 16, max: 20),
      ),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: ShellStyles.scaled(context, 22, min: 20, max: 24),
        color: ShellStyles.surfaceAlt(context),
        withShadow: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('quick_scan_with_ai_review'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: ShellStyles.scaled(context, 18, min: 16, max: 20),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('receipts_empty_body'),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: ShellStyles.scaled(context, 13, min: 12, max: 14),
              height: 1.45,
            ),
          ),
          SizedBox(height: ShellStyles.scaled(context, 14, min: 12, max: 16)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHintPill(context.tr('upload_hint_full_receipt')),
              _buildHintPill(context.tr('upload_hint_good_lighting')),
              _buildHintPill(context.tr('upload_hint_size_limit')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHintPill(String label) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ShellStyles.scaled(context, 10, min: 8, max: 12),
        vertical: ShellStyles.scaled(context, 7, min: 6, max: 8),
      ),
      decoration: BoxDecoration(
        color: ShellStyles.surface(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ShellStyles.border(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ShellStyles.textPrimary(context),
          fontSize: ShellStyles.scaled(context, 11, min: 10, max: 12),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final radius = BorderRadius.circular(
      ShellStyles.scaled(context, 24, min: 20, max: 26),
    );

    return Container(
      decoration: ShellStyles.cardDecoration(
        context,
        radius: ShellStyles.scaled(context, 24, min: 20, max: 26),
        color: ShellStyles.surface(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: Container(
              constraints: BoxConstraints(
                minHeight: ShellStyles.scaled(context, 220, min: 200, max: 260),
              ),
              width: double.infinity,
              color: ShellStyles.surfaceAlt(context),
              child: _pickedFile == null
                  ? Padding(
                      padding: EdgeInsets.all(
                        ShellStyles.scaled(context, 22, min: 18, max: 24),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: ShellStyles.scaled(
                              context,
                              62,
                              min: 56,
                              max: 68,
                            ),
                            height: ShellStyles.scaled(
                              context,
                              62,
                              min: 56,
                              max: 68,
                            ),
                            alignment: Alignment.center,
                            decoration: ShellStyles.iconBadgeDecoration(
                              context,
                              color: ShellStyles.surface(context),
                              radius: ShellStyles.scaled(
                                context,
                                20,
                                min: 18,
                                max: 22,
                              ),
                            ),
                            child: Icon(
                              Icons.photo_camera_outlined,
                              size: ShellStyles.scaled(
                                context,
                                28,
                                min: 24,
                                max: 30,
                              ),
                              color: ShellStyles.accent(context),
                            ),
                          ),
                          SizedBox(
                            height: ShellStyles.scaled(
                              context,
                              14,
                              min: 12,
                              max: 16,
                            ),
                          ),
                          Text(
                            context.tr('tools_scan_receipt'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ShellStyles.textPrimary(context),
                              fontSize: ShellStyles.scaled(
                                context,
                                17,
                                min: 15,
                                max: 19,
                              ),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('receipts_empty_body'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: ShellStyles.scaled(
                                context,
                                13,
                                min: 12,
                                max: 14,
                              ),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Image.file(File(_pickedFile!.path), fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(
              ShellStyles.scaled(context, 16, min: 14, max: 18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pickedFile == null
                      ? context.tr('transaction_receipt_photo_title')
                      : _pickedFile!.name,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: ShellStyles.scaled(context, 15, min: 14, max: 16),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pickedFile == null
                      ? context.tr('upload_preview_empty_body')
                      : context.tr('upload_preview_selected_body'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: ShellStyles.scaled(context, 12, min: 11, max: 13),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingCard() {
    return Container(
      padding: EdgeInsets.all(
        ShellStyles.scaled(context, 20, min: 18, max: 22),
      ),
      decoration: ShellStyles.cardDecoration(
        context,
        radius: ShellStyles.scaled(context, 22, min: 20, max: 24),
        color: ShellStyles.surface(context),
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
                  color: ShellStyles.accent(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _processingHeadline(),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: ShellStyles.scaled(
                          context,
                          18,
                          min: 16,
                          max: 20,
                        ),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _processingBody(),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: ShellStyles.scaled(
                          context,
                          13,
                          min: 12,
                          max: 14,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: ShellStyles.scaled(context, 18, min: 16, max: 20)),
          _buildProcessingStep(
            stepIndex: 0,
            title: context.tr('upload_receipt'),
            body: context.tr('upload_status_uploading'),
          ),
          const SizedBox(height: 12),
          _buildProcessingStep(
            stepIndex: 1,
            title: context.tr('read_totals_and_items'),
            body: context.tr('read_totals_and_items'),
          ),
          const SizedBox(height: 12),
          _buildProcessingStep(
            stepIndex: 2,
            title: context.tr('open_review'),
            body: context.tr('open_review'),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _progress,
            color: ShellStyles.accent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard() {
    return Container(
      padding: EdgeInsets.all(
        ShellStyles.scaled(context, 16, min: 14, max: 18),
      ),
      decoration: BoxDecoration(
        color: ShellColors.softRed.withAlpha(10),
        borderRadius: BorderRadius.circular(
          ShellStyles.scaled(context, 20, min: 18, max: 22),
        ),
        border: Border.all(color: ShellColors.softRed.withAlpha(50)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: ShellColors.softRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('upload_try_again'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: ShellStyles.scaled(context, 15, min: 14, max: 16),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _error ?? context.tr('error_receipt_extraction_failed'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: ShellStyles.scaled(
                      context,
                      12.5,
                      min: 12,
                      max: 13.5,
                    ),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomActionBar() {
    if (_isBusy) {
      return null;
    }

    final horizontalPadding = ShellStyles.scaled(context, 16, min: 14, max: 18);
    final verticalPadding = ShellStyles.scaled(context, 12, min: 10, max: 14);

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          verticalPadding,
          horizontalPadding,
          verticalPadding,
        ),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          border: Border(top: BorderSide(color: ShellStyles.border(context))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pickedFile == null) ...[
              FilledButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(
                    ShellStyles.minTapTarget(context),
                  ),
                ),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(context.tr('upload_camera')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(
                    ShellStyles.minTapTarget(context),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.tr('upload_gallery')),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed:
                    canStartReceiptUpload(
                      hasPickedFile: _pickedFile != null,
                      status: _status,
                    )
                    ? _startUpload
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(
                    ShellStyles.minTapTarget(context),
                  ),
                ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(context.tr('upload_action_extract')),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          ShellStyles.minTapTarget(context),
                        ),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        _lastPickSource == _ReceiptPickSource.camera
                            ? context.tr('upload_camera')
                            : context.tr('upload_camera'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(
                          ShellStyles.minTapTarget(context),
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _status == 'failed'
                            ? context.tr('upload_gallery')
                            : context.tr('upload_gallery'),
                      ),
                    ),
                  ),
                ],
              ),
              if (_status == 'failed') ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _clearFailure(keepSelection: true),
                  child: Text(context.tr('keep_this_image_and_try_later')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(title: Text(context.tr('upload_title'))),
      bottomNavigationBar: _buildBottomActionBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            ShellStyles.scaled(context, 16, min: 14, max: 18),
            ShellStyles.scaled(context, 16, min: 14, max: 18),
            ShellStyles.scaled(context, 16, min: 14, max: 18),
            ShellStyles.scaled(context, 24, min: 20, max: 28),
          ),
          children: [
            _buildIntroCard(),
            SizedBox(height: ShellStyles.scaled(context, 16, min: 14, max: 18)),
            _buildPreviewCard(),
            if (_status == 'uploading' || _status == 'processing') ...[
              SizedBox(
                height: ShellStyles.scaled(context, 16, min: 14, max: 18),
              ),
              _buildProcessingCard(),
            ],
            if (_error != null) ...[
              SizedBox(
                height: ShellStyles.scaled(context, 16, min: 14, max: 18),
              ),
              _buildFailureCard(),
            ],
          ],
        ),
      ),
    );
  }
}
