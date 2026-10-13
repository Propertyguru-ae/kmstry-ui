import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../media/media_network_url.dart';
import '../media/media_reference.dart';
import '../media/media_cache_identity.dart';
import '../media/signed_media_resolver.dart';
import '../media/google_photo_updates.dart';

typedef CachedImageContentBuilder =
    Widget Function(BuildContext context, Widget content, bool imageLoaded);

/// `Image.network` yerine kullanılan görsel bileşeni. KMSTRY-owned media uses
/// disk + memory caching. Google Places proxy images intentionally use only
/// Flutter's in-memory cache so provider content is not persisted on device.
///
/// API bilinçli olarak `Image.network`'e yakın tutuldu ki çağrı yerleri kolay
/// dönüştürülsün: [url] + [fit] + [width]/[height] + opsiyonel [errorWidget]
/// (eski `errorBuilder`'ın karşılığı) ve [placeholder].
class CachedImage extends StatefulWidget {
  const CachedImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholder,
    this.fadeInDuration = const Duration(milliseconds: 150),
    this.mediaReference,
    this.contentBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;

  /// Yükleme başarısız olursa gösterilecek widget (eski `errorBuilder` yerine).
  final WidgetBuilder? errorWidget;

  /// Yüklenirken gösterilecek widget. Verilmezse hafif bir placeholder çizilir.
  final WidgetBuilder? placeholder;

  final Duration fadeInDuration;
  final MediaReference? mediaReference;

  /// Decorates the rendered content without extra network requests or state
  /// callbacks. [imageLoaded] is true only for a successfully decoded frame;
  /// loading placeholders, empty URLs and errors always report false.
  final CachedImageContentBuilder? contentBuilder;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  late String _url;
  bool _refreshAttempted = false;
  String _photoRevision = '';

  @override
  void initState() {
    super.initState();
    _url = resolveMediaNetworkUrl(
      SignedMediaResolver.instance
          .current(widget.mediaReference ?? _legacyReference())
          .url,
    );
    _scheduleRefreshIfNeeded();
    _photoRevision = GooglePhotoUpdates.instance.revisionFor(_url);
    GooglePhotoUpdates.instance.addListener(_onPhotoUpdated);
  }

  void _onPhotoUpdated() {
    final revision = GooglePhotoUpdates.instance.revisionFor(_url);
    if (!mounted || revision == _photoRevision) return;
    setState(() => _photoRevision = revision);
  }

  @override
  void dispose() {
    GooglePhotoUpdates.instance.removeListener(_onPhotoUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.mediaReference?.mediaId != widget.mediaReference?.mediaId) {
      _url = resolveMediaNetworkUrl(
        SignedMediaResolver.instance
            .current(widget.mediaReference ?? _legacyReference())
            .url,
      );
      _refreshAttempted = false;
      _photoRevision = GooglePhotoUpdates.instance.revisionFor(_url);
      _scheduleRefreshIfNeeded();
    }
  }

  MediaReference _legacyReference() =>
      MediaReference(mediaId: widget.url, url: widget.url);

  String? get _cacheKey =>
      mediaCacheIdentity(_url, mediaId: widget.mediaReference?.mediaId);

  @override
  Widget build(BuildContext context) {
    // Resolve again during build as well. Besides guarding against a stale
    // SignedMediaResolver entry, this makes a development hot reload recover
    // immediately from a previously advertised localhost proxy URL.
    final networkUrl = GooglePhotoUpdates.instance.networkUrl(_url);

    // Boş/geçersiz URL → doğrudan fallback (CachedNetworkImage boş url'de atar).
    if (networkUrl.isEmpty) {
      _scheduleRefreshIfNeeded();
      return _fallback(context);
    }

    // Google Places photos are streamed through the KMSTRY proxy and must not
    // be persisted in the app's disk cache. Image.network still benefits from
    // Flutter's in-memory ImageCache during the current screen/app session.
    if (isGooglePlacePhotoProxyUrl(networkUrl)) {
      return Image.network(
        networkUrl,
        key: ValueKey(
          '${widget.mediaReference?.mediaId ?? networkUrl}:$networkUrl',
        ),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        frameBuilder: widget.contentBuilder == null
            ? null
            : (context, child, frame, synchronouslyLoaded) => _decorate(
                context,
                child,
                imageLoaded: synchronouslyLoaded || frame != null,
              ),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(context),
        errorBuilder: (context, _, _) {
          _refreshSignedUrlOnce();
          return _fallback(context);
        },
      );
    }

    return CachedNetworkImage(
      key: ValueKey(
        '${widget.mediaReference?.mediaId ?? networkUrl}:$networkUrl',
      ),
      imageUrl: networkUrl,
      cacheKey: _cacheKey,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: widget.fadeInDuration,
      imageBuilder: widget.contentBuilder == null
          ? null
          : (context, provider) => _decorate(
              context,
              Image(
                image: provider,
                fit: widget.fit,
                width: widget.width,
                height: widget.height,
              ),
              imageLoaded: true,
            ),
      placeholder: (context, _) => _placeholder(context),
      errorWidget: (context, _, _) {
        _refreshSignedUrlOnce();
        return _fallback(context);
      },
    );
  }

  Future<void> _refreshSignedUrlOnce() async {
    final reference = widget.mediaReference;
    if (_refreshAttempted || reference == null || !reference.canRefresh) return;
    _refreshAttempted = true;
    final refreshed = await SignedMediaResolver.instance.refreshOnce(reference);
    if (!mounted || refreshed == null || refreshed.url == _url) return;
    setState(() => _url = resolveMediaNetworkUrl(refreshed.url));
  }

  void _scheduleRefreshIfNeeded() {
    if (_url.trim().isNotEmpty ||
        _refreshAttempted ||
        widget.mediaReference?.canRefresh != true) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshSignedUrlOnce();
    });
  }

  Widget _fallback(BuildContext context) {
    return _decorate(
      context,
      widget.errorWidget?.call(context) ?? _defaultPlaceholder(context),
    );
  }

  Widget _placeholder(BuildContext context) => _decorate(
    context,
    widget.placeholder?.call(context) ?? _defaultPlaceholder(context),
  );

  Widget _decorate(
    BuildContext context,
    Widget child, {
    bool imageLoaded = false,
  }) => widget.contentBuilder?.call(context, child, imageLoaded) ?? child;

  Widget _defaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.width,
      height: widget.height,
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFEAF1F4),
    );
  }
}
