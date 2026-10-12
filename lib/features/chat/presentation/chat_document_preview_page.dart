import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../data/chat_pdf_preview_service.dart';

/// Selecting a document never uploads or sends it. Only explicit confirmation
/// returns true to the sending page; Back/Cancel discards the selection.
///
/// [viewOnly]: opening a received/sent document from the chat — same in-app
/// viewer (like WhatsApp, no browser / storage link), with Share instead of
/// Send.
class ChatDocumentPreviewPage extends StatefulWidget {
  const ChatDocumentPreviewPage({
    super.key,
    required this.file,
    required this.fileName,
    required this.fileSize,
    this.viewOnly = false,
  });

  final File file;
  final String fileName;
  final int fileSize;
  final bool viewOnly;

  @override
  State<ChatDocumentPreviewPage> createState() =>
      _ChatDocumentPreviewPageState();
}

class _ChatDocumentPreviewPageState extends State<ChatDocumentPreviewPage> {
  PdfControllerPinch? _controller;
  Future<PdfDocument>? _document;
  int? _pageCount;

  @override
  void initState() {
    super.initState();
    if (isChatPdf(widget.fileName)) {
      _document = PdfDocument.openFile(widget.file.path);
      _controller = PdfControllerPinch(document: _document!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    final document = _document;
    if (document != null) {
      // The pinch controller releases textures, but not the document handle.
      // Also close documents whose asynchronous opening finishes after Back.
      unawaited(
        document
            .then<void>((value) async {
              if (!value.isClosed) await value.close();
            }, onError: (Object error, StackTrace stackTrace) {})
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  String get _sizeText => widget.fileSize >= 1024 * 1024
      ? '${(widget.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(widget.fileSize / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.viewOnly ? widget.fileName : 'Preview document',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      leading: IconButton(
        tooltip: widget.viewOnly ? 'Close' : 'Cancel',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: _controller == null
              ? _documentPlaceholder('Document ready to send')
              : PdfViewPinch(
                  controller: _controller!,
                  onDocumentLoaded: (document) {
                    if (mounted) {
                      setState(() => _pageCount = document.pagesCount);
                    }
                  },
                  builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    documentLoaderBuilder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                    pageLoaderBuilder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_, _) => _documentPlaceholder(
                      widget.viewOnly
                          ? 'Preview unavailable for this document.'
                          : 'Preview unavailable. You can still send this document.',
                    ),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_sizeText${_pageCount == null ? '' : ' · $_pageCount ${_pageCount == 1 ? 'page' : 'pages'}'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.viewOnly) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    key: const ValueKey('chat-document-send'),
                    style: _buttonStyle,
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send'),
                  ),
                ] else if (_shareEnabled) ...[
                  const SizedBox(width: 16),
                  Builder(
                    builder: (buttonContext) => FilledButton.icon(
                      key: const ValueKey('chat-document-share'),
                      style: _buttonStyle,
                      onPressed: () => unawaited(_share(buttonContext)),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  /// Share is hidden for now (product decision); flip to bring it back.
  static const bool _shareEnabled = false;

  static final ButtonStyle _buttonStyle = FilledButton.styleFrom(
    backgroundColor: AppColors.blue,
    foregroundColor: Colors.white,
    // The app theme gives filled buttons full width (Size.fromHeight) —
    // inside this Row that is an infinite width and the whole page fails to
    // lay out (blank page, Cancel unreachable).
    minimumSize: const Size(0, 46),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.file.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Widget _documentPlaceholder(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isChatPdf(widget.fileName)
                ? Icons.picture_as_pdf_rounded
                : Icons.description_rounded,
            size: 64,
            color: AppColors.blue,
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
