import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// `Image.network` yerine kullanılan disk+bellek cache'li görsel bileşeni.
/// Aynı URL bir daha indirilmez → liste/harita/profil fotoğrafları scroll ve
/// rebuild'lerde anında gelir, network churn'ü ve jank azalır.
///
/// API bilinçli olarak `Image.network`'e yakın tutuldu ki çağrı yerleri kolay
/// dönüştürülsün: [url] + [fit] + [width]/[height] + opsiyonel [errorWidget]
/// (eski `errorBuilder`'ın karşılığı) ve [placeholder].
class CachedImage extends StatelessWidget {
  const CachedImage(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorWidget,
    this.placeholder,
    this.fadeInDuration = const Duration(milliseconds: 150),
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

  @override
  Widget build(BuildContext context) {
    // Boş/geçersiz URL → doğrudan fallback (CachedNetworkImage boş url'de atar).
    if (url.trim().isEmpty) {
      return _fallback(context);
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      fadeInDuration: fadeInDuration,
      placeholder: (context, _) =>
          placeholder?.call(context) ?? _defaultPlaceholder(context),
      errorWidget: (context, _, _) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    if (errorWidget != null) return errorWidget!(context);
    return _defaultPlaceholder(context);
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      color: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFEAF1F4),
    );
  }
}
