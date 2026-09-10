import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../media/media_reference.dart';
import '../media/signed_media_resolver.dart';

/// `Image.network` yerine kullanılan disk+bellek cache'li görsel bileşeni.
/// Aynı URL bir daha indirilmez → liste/harita/profil fotoğrafları scroll ve
/// rebuild'lerde anında gelir, network churn'ü ve jank azalır.
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

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  late String _url;
  bool _refreshAttempted = false;

  @override
  void initState() {
    super.initState();
    _url = SignedMediaResolver.instance
        .current(widget.mediaReference ?? _legacyReference())
        .url;
    _scheduleRefreshIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.mediaReference?.mediaId != widget.mediaReference?.mediaId) {
      _url = SignedMediaResolver.instance
          .current(widget.mediaReference ?? _legacyReference())
          .url;
      _refreshAttempted = false;
      _scheduleRefreshIfNeeded();
    }
  }

  MediaReference _legacyReference() =>
      MediaReference(mediaId: widget.url, url: widget.url);

  @override
  Widget build(BuildContext context) {
    // Boş/geçersiz URL → doğrudan fallback (CachedNetworkImage boş url'de atar).
    if (_url.trim().isEmpty) {
      _scheduleRefreshIfNeeded();
      return _fallback(context);
    }

    return CachedNetworkImage(
      key: ValueKey('${widget.mediaReference?.mediaId ?? _url}:$_url'),
      imageUrl: _url,
      cacheKey: widget.mediaReference?.mediaId,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      fadeInDuration: widget.fadeInDuration,
      placeholder: (context, _) =>
          widget.placeholder?.call(context) ?? _defaultPlaceholder(context),
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
    setState(() => _url = refreshed.url);
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
    if (widget.errorWidget != null) return widget.errorWidget!(context);
    return _defaultPlaceholder(context);
  }

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
