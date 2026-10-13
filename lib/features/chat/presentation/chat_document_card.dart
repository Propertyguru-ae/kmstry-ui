import 'package:flutter/material.dart';

import '../../../core/media/media_reference.dart';
import '../data/chat_pdf_preview_service.dart';

/// Sohbetteki belge balonunun içeriği (WhatsApp düzeni):
/// PDF ise üstte ilk sayfanın üst kısmı, altında renkli rozet + dosya adı +
/// "3 pages • 829 KB • PDF" satırı olan bilgi paneli, en altta saat/tik.
class ChatDocumentCard extends StatefulWidget {
  const ChatDocumentCard({
    super.key,
    required this.fileName,
    required this.source,
    required this.service,
    required this.width,
    required this.isDark,
    required this.textColor,
    required this.meta,
    this.media,
    this.localPreviewPath,
    this.uploading = false,
  });

  static const double previewHeight = 140;

  final String fileName;
  final String source;
  final ChatPdfPreviewService service;
  final double width;
  final bool isDark;
  final Color textColor;

  /// Saat + okundu bilgisi satırı (balonun diğer türleriyle aynı widget).
  final Widget meta;
  final MediaReference? media;
  final String? localPreviewPath;
  final bool uploading;

  @override
  State<ChatDocumentCard> createState() => _ChatDocumentCardState();
}

class _ChatDocumentCardState extends State<ChatDocumentCard> {
  Future<ChatPdfPreview>? _preview;

  bool get _isPdf => isChatPdf(widget.fileName);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatDocumentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.fileName != widget.fileName ||
        oldWidget.localPreviewPath != widget.localPreviewPath ||
        oldWidget.service != widget.service ||
        oldWidget.media?.mediaId != widget.media?.mediaId) {
      _load();
    }
  }

  void _load() {
    _preview = _isPdf
        ? widget.service.preview(
            source: widget.source,
            media: widget.media,
            localPreviewPath: widget.localPreviewPath,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: FutureBuilder<ChatPdfPreview>(
        future: _preview,
        builder: (context, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isPdf) _buildPreview(snapshot),
            _buildInfoPanel(snapshot.data),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 6, 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.meta,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AsyncSnapshot<ChatPdfPreview> snapshot) {
    final Widget content;
    if (snapshot.hasData) {
      // WhatsApp gibi: sayfa genişliğe sığar, üst kısmı görünür.
      content = Image.memory(
        snapshot.data!.bytes,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _previewUnavailable(),
      );
    } else if (snapshot.hasError) {
      content = _previewUnavailable();
    } else {
      content = const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF9AA3B2),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: SizedBox(
        key: const ValueKey('chat-pdf-preview-frame'),
        height: ChatDocumentCard.previewHeight,
        child: ColoredBox(color: Colors.white, child: content),
      ),
    );
  }

  Widget _previewUnavailable() => const Center(
    child: Icon(
      Icons.picture_as_pdf_rounded,
      color: Color(0xFFB4BAC4),
      size: 40,
    ),
  );

  Widget _buildInfoPanel(ChatPdfPreview? preview) {
    final ext = documentExtensionLabel(widget.fileName);
    final badgeColor = documentBadgeColor(widget.fileName);
    final panelColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.045);
    final radius = _isPdf
        ? const BorderRadius.vertical(bottom: Radius.circular(12))
        : BorderRadius.circular(12);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(color: panelColor, borderRadius: radius),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        ext,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.uploading
                      ? 'Uploading…'
                      : documentDetailsLine(
                          extension: ext,
                          pageCount: preview?.pageCount,
                          documentBytes: preview?.documentBytes,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "PDF", "DOCX" … uzantı yoksa "FILE".
String documentExtensionLabel(String fileName) {
  final name = fileName.trim();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'FILE';
  final ext = name.substring(dot + 1).toUpperCase();
  return ext.length > 4 ? ext.substring(0, 4) : ext;
}

Color documentBadgeColor(String fileName) {
  return switch (documentExtensionLabel(fileName)) {
    'PDF' => const Color(0xFFE5484D),
    'DOC' || 'DOCX' || 'RTF' || 'PAGE' => const Color(0xFF2B6CD9),
    'XLS' || 'XLSX' || 'CSV' || 'NUMB' => const Color(0xFF1E9E5A),
    'PPT' || 'PPTX' || 'KEY' => const Color(0xFFE8743B),
    _ => const Color(0xFF7A8699),
  };
}

/// "1 page • 829 KB • PDF" — bilinmeyen parçalar atlanır.
String documentDetailsLine({
  required String extension,
  int? pageCount,
  int? documentBytes,
}) {
  return [
    if (pageCount != null) '$pageCount ${pageCount == 1 ? 'page' : 'pages'}',
    if (documentBytes != null) formatDocumentSize(documentBytes),
    extension,
  ].join(' • ');
}

String formatDocumentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
