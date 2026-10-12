import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/media/media_cache_identity.dart';
import '../../../core/media/media_reference.dart';
import '../../../core/media/signed_media_resolver.dart';
import '../../../core/storage/secure_storage.dart';

bool isChatPdf(String fileName) =>
    fileName.trim().toLowerCase().endsWith('.pdf');

class ChatPdfPreview {
  const ChatPdfPreview({
    required this.bytes,
    required this.pageCount,
    this.documentBytes,
  });
  final Uint8List bytes;
  final int pageCount;

  /// Size of the whole document (not the thumbnail), shown as "829 KB".
  final int? documentBytes;
}

typedef ChatPdfRenderer = Future<ChatPdfPreview> Function(Uint8List bytes);

/// Private documents are rendered on-device, never by a third-party viewer.
/// Only small thumbnails are cached, in memory, for the lifetime of the chat.
class ChatPdfPreviewService {
  ChatPdfPreviewService({
    http.Client? client,
    SignedMediaResolver? resolver,
    ChatPdfRenderer? renderer,
    DateTime Function()? now,
    Future<Directory> Function()? temporaryDirectory,
  }) : _client = client ?? http.Client(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _resolver = resolver ?? SignedMediaResolver.instance,
       _renderer = renderer ?? _renderFirstPage,
       _now = now ?? DateTime.now {
    _sessionSubscription = SecureStorage.sessionEnded.listen((_) => clear());
  }

  static const maxDocumentBytes = 25 * 1024 * 1024;
  static const _maxPreviewBytes = 8 * 1024 * 1024;
  static const double _previewRenderWidth = 1080;
  static const double _previewRenderMaxHeight = 2400;
  static const _maxEntries = 24;
  final http.Client _client;
  final SignedMediaResolver _resolver;
  final ChatPdfRenderer _renderer;
  final DateTime Function() _now;
  final Future<Directory> Function() _temporaryDirectory;
  final _documentFiles = <String, Future<File>>{};
  // Per-instance folder: closing one chat never deletes another's files.
  final _documentsFolder =
      'chat_documents/${DateTime.now().microsecondsSinceEpoch}';
  final _cache = <String, ({ChatPdfPreview value, DateTime until})>{};
  final _pending = <String, Future<ChatPdfPreview>>{};
  late final StreamSubscription<void> _sessionSubscription;
  Future<void> _queue = Future.value();
  int _generation = 0;
  bool _disposed = false;

  Future<ChatPdfPreview> preview({
    required String source,
    MediaReference? media,
    String? localPreviewPath,
  }) {
    if (_disposed) return Future.error(StateError('Preview closed'));
    final local =
        localPreviewPath ?? (!source.startsWith('http') ? source : null);
    final key = local != null
        ? 'local:$local'
        : '${media?.mediaId ?? ''}:${mediaObjectIdentity(source)}';
    final cached = _cache.remove(key);
    if (cached != null && _now().isBefore(cached.until)) {
      _cache[key] = cached;
      return Future.value(cached.value);
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final generation = _generation;
    // A long chat must not launch dozens of downloads/native renders at once.
    final future = _queue.then((_) async {
      _assertCurrent(generation);
      Uint8List? bytes;
      if (local != null && local.isNotEmpty && await File(local).exists()) {
        final file = File(local);
        if (await file.length() > maxDocumentBytes) {
          throw const FormatException('Document is too large');
        }
        bytes = await file.readAsBytes();
      }
      bytes ??= await _download(source, media);
      _assertCurrent(generation);
      if (bytes.length > maxDocumentBytes || !_isPdf(bytes)) {
        throw const FormatException('PDF preview unavailable');
      }
      final result = await _renderer(bytes);
      _assertCurrent(generation);
      final expires = media == null ? null : _resolver.current(media).expiresAt;
      final limit = _now().add(const Duration(minutes: 10));
      final until = expires != null && expires.isBefore(limit)
          ? expires
          : limit;
      if (result.bytes.length <= _maxPreviewBytes && _now().isBefore(until)) {
        _cache[key] = (value: result, until: until);
        while (_cache.length > _maxEntries ||
            _cache.values.fold<int>(0, (sum, e) => sum + e.value.bytes.length) >
                _maxPreviewBytes) {
          _cache.remove(_cache.keys.first);
        }
      }
      return result;
    });
    _pending[key] = future;
    _queue = future.then<void>(
      (_) => _finishPending(key, future),
      onError: (Object error, StackTrace stackTrace) =>
          _finishPending(key, future),
    );
    return future;
  }

  /// Downloads the whole document into the app's private temp folder so it
  /// can be opened IN the app (PDF viewer / system Quick Look). The signed
  /// storage URL is never handed to a browser, so it is not shown or shared.
  /// Same signed-URL refresh and 25 MB limit as previews; files are cached
  /// for the chat session and deleted when the session ends.
  Future<File> documentFile({
    required String source,
    required String fileName,
    MediaReference? media,
    String? localPath,
  }) async {
    if (_disposed) throw StateError('Preview closed');
    if (localPath != null &&
        localPath.isNotEmpty &&
        await File(localPath).exists()) {
      return File(localPath);
    }
    final key = '${media?.mediaId ?? ''}:${mediaObjectIdentity(source)}';
    final pending = _documentFiles[key];
    if (pending != null) return pending;
    final generation = _generation;
    final future = () async {
      final bytes = await _download(source, media);
      _assertCurrent(generation);
      if (bytes.length > maxDocumentBytes) {
        throw const FormatException('Document is too large');
      }
      // Keep the original name (viewer title / share sheet) inside a folder
      // unique to this document.
      final folder = Directory(
        '${(await _documentsRoot()).path}/'
        '${sha1.convert(key.codeUnits).toString().substring(0, 16)}',
      );
      await folder.create(recursive: true);
      final file = File('${folder.path}/${_safeFileName(fileName)}');
      await file.writeAsBytes(bytes, flush: true);
      _assertCurrent(generation);
      return file;
    }();
    _documentFiles[key] = future;
    // A failed download must be retryable on the next tap.
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_documentFiles[key], future)) {
            _documentFiles.remove(key);
          }
        },
      ),
    );
    return future;
  }

  Future<Directory> _documentsRoot() async =>
      Directory('${(await _temporaryDirectory()).path}/$_documentsFolder');

  static String _safeFileName(String fileName) {
    final cleaned = fileName.trim().replaceAll(
      RegExp(r'[/\\:*?"<>|\x00-\x1F]'),
      '_',
    );
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      return 'Document';
    }
    return cleaned.length > 120
        ? cleaned.substring(cleaned.length - 120)
        : cleaned;
  }

  void _deleteDocumentFiles() {
    _documentFiles.clear();
    unawaited(() async {
      try {
        final root = await _documentsRoot();
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {
        // Best effort: the OS also purges the temp folder.
      }
    }());
  }

  void _finishPending(String key, Future<ChatPdfPreview> future) {
    if (identical(_pending[key], future)) _pending.remove(key);
  }

  Future<Uint8List> _download(String source, MediaReference? media) async {
    var current = media == null ? null : _resolver.current(media);
    var url = current?.url.isNotEmpty == true ? current!.url : source;
    var refreshed = false;
    if (current?.canRefresh == true &&
        (url.isEmpty ||
            current!.expiresAt?.isBefore(
                  _now().add(const Duration(seconds: 10)),
                ) ==
                true)) {
      current = await _resolver.refreshOnce(current!);
      if (current == null) {
        throw const FormatException('Secure link unavailable');
      }
      url = current.url;
      refreshed = true;
    }
    try {
      return await _downloadUrl(url);
    } on _PdfAccessDenied {
      if (refreshed || media?.canRefresh != true) rethrow;
      current = await _resolver.refreshOnce(media!);
      if (current == null) rethrow;
      return _downloadUrl(current.url);
    }
  }

  Future<Uint8List> _downloadUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Secure link unavailable');
    }
    // These are signed storage URLs. Never attach the app's JWT to storage.
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      await response.stream.listen((_) {}).cancel();
      throw const _PdfAccessDenied();
    }
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxDocumentBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('PDF preview unavailable');
    }
    final data = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (data.length + chunk.length > maxDocumentBytes) {
        throw const FormatException('Document is too large');
      }
      data.add(chunk);
    }
    return data.takeBytes();
  }

  static bool _isPdf(Uint8List bytes) {
    // PDF headers can follow a short binary prefix. Do not trust the filename.
    for (var i = 0; i + 4 < bytes.length && i < 1024; i++) {
      if (bytes[i] == 37 &&
          bytes[i + 1] == 80 &&
          bytes[i + 2] == 68 &&
          bytes[i + 3] == 70 &&
          bytes[i + 4] == 45) {
        return true;
      }
    }
    return false;
  }

  static Future<ChatPdfPreview> _renderFirstPage(Uint8List bytes) async {
    final document = await PdfDocument.openData(bytes);
    try {
      if (document.pagesCount < 1) throw const FormatException('Empty PDF');
      final page = await document.getPage(1);
      try {
        // The chat card shows the page at its full width (260pt ≈ 780px on a
        // 3x screen), so scale by width — scaling by the long edge left A4
        // pages ~420px wide and visibly blurry. Very tall pages (receipts)
        // are capped so the bitmap stays small.
        final scale = min(
          _previewRenderWidth / page.width,
          _previewRenderMaxHeight / page.height,
        );
        final image = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        if (image == null) {
          throw const FormatException('PDF preview unavailable');
        }
        return ChatPdfPreview(
          bytes: image.bytes,
          pageCount: document.pagesCount,
          documentBytes: bytes.length,
        );
      } finally {
        await page.close();
      }
    } finally {
      await document.close();
    }
  }

  void _assertCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Session changed');
    }
  }

  void clear() {
    _generation++;
    _cache.clear();
    _pending.clear();
    _deleteDocumentFiles();
  }

  void dispose() {
    _disposed = true;
    clear();
    _client.close();
    unawaited(_sessionSubscription.cancel());
  }
}

class _PdfAccessDenied implements Exception {
  const _PdfAccessDenied();
}
