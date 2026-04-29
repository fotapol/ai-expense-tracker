import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';

class ReceiptPhotoViewScreen extends StatefulWidget {
  const ReceiptPhotoViewScreen({
    super.key,
    required this.title,
    required this.viewUrl,
    required this.mimeType,
  });

  final String title;
  final String viewUrl;
  final String mimeType;

  @override
  State<ReceiptPhotoViewScreen> createState() => _ReceiptPhotoViewScreenState();
}

class _ReceiptPhotoViewScreenState extends State<ReceiptPhotoViewScreen> {
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'expense_tracker_app/media_store',
  );
  static const double _dismissDistance = 120;
  static const double _dismissVelocity = 850;

  final TransformationController _transformationController =
      TransformationController();

  double _dragOffset = 0;
  bool _isZoomed = false;

  bool get _isImage => widget.mimeType.toLowerCase().startsWith('image/');

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_syncZoomState);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_syncZoomState);
    _transformationController.dispose();
    super.dispose();
  }

  void _syncZoomState() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed == _isZoomed) return;
    setState(() {
      _isZoomed = zoomed;
      if (zoomed) {
        _dragOffset = 0;
      }
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (_isZoomed || delta <= 0) return;
    setState(() {
      _dragOffset = (_dragOffset + delta)
          .clamp(0.0, _dismissDistance * 1.45)
          .toDouble();
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset >= _dismissDistance || velocity >= _dismissVelocity) {
      Navigator.pop(context);
      return;
    }
    _resetDragOffset();
  }

  void _resetDragOffset() {
    if (_dragOffset == 0) return;
    setState(() {
      _dragOffset = 0;
    });
  }

  String _resolvedFilename() {
    final trimmed = widget.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final uri = Uri.tryParse(widget.viewUrl);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    return lastSegment.isNotEmpty ? lastSegment : 'receipt';
  }

  Future<String?> _saveToPublicAndroidMediaStore(Uint8List bytes) async {
    try {
      return await _mediaStoreChannel
          .invokeMethod<String>('saveFile', <String, dynamic>{
            'bytes': bytes,
            'filename': _resolvedFilename(),
            'mimeType': widget.mimeType.isNotEmpty
                ? widget.mimeType
                : 'application/octet-stream',
          });
    } on PlatformException {
      return null;
    }
  }

  Future<void> _downloadFile(BuildContext context) async {
    final uri = Uri.tryParse(widget.viewUrl);
    final invalidUrlText = context.tr('receipt_photo_invalid_url');
    final galleryLabel = context.tr('upload_gallery');
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(invalidUrlText)));
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
    final uri = Uri.tryParse(widget.viewUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('receipt_photo_invalid_url'))),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return;

    await Clipboard.setData(ClipboardData(text: widget.viewUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('receipt_photo_open_fallback'))),
    );
  }

  Color _viewerBackground(BuildContext context) {
    return Color.lerp(
      ShellStyles.background(context),
      ShellStyles.surfaceAlt(context),
      ShellStyles.isDark(context) ? 0.5 : 0.78,
    )!;
  }

  Widget _buildImageViewer(BuildContext context) {
    final background = _viewerBackground(context);
    final foreground = ShellStyles.textPrimary(context);
    final dragProgress = (_dragOffset / _dismissDistance)
        .clamp(0.0, 1.0)
        .toDouble();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: ShellStyles.isDark(context)
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
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
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background,
                    Color.lerp(
                      background,
                      ShellStyles.surface(context),
                      ShellStyles.isDark(context) ? 0.18 : 0.42,
                    )!,
                  ],
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _isZoomed ? null : _handleVerticalDragUpdate,
            onVerticalDragEnd: _isZoomed ? null : _handleVerticalDragEnd,
            onVerticalDragCancel: _isZoomed ? null : _resetDragOffset,
            child: AnimatedContainer(
              duration: _dragOffset == 0
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, _dragOffset, 0),
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18 * dragProgress),
                    child: Image.network(
                      widget.viewUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            color: ShellStyles.accent(context),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                color: ShellStyles.textMuted(context),
                                size: 56,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.tr('receipt_photo_load_failed'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => _openExternally(context),
                                icon: const Icon(Icons.open_in_new),
                                label: Text(
                                  context.tr('receipt_photo_open_external'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isZoomed ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ShellStyles.textMuted(context).withAlpha(150),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return _buildImageViewer(context);
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                widget.mimeType,
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
