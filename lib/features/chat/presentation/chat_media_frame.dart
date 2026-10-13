import 'dart:math';

import 'package:flutter/material.dart';

/// Sohbetteki medya balonlarının (fotoğraf + belge) ortak genişlik üst sınırı.
const double kChatMediaMaxWidth = 260;

/// Balon iç boşluğu (3px) + vurgulanmış kenarlık (1.6px), iki yan için.
const double _maxBubbleInsets = 2 * (3 + 1.6);

/// Fotoğrafın gösterileceği sabit çerçeve tipi. Her fotoğraf bu üç sabit
/// boyuttan birinde, çerçeveyi dolduracak şekilde gösterilir.
enum ChatMediaShape { portrait, square, landscape }

ChatMediaShape chatMediaShapeFor({int? imageWidth, int? imageHeight}) {
  if (imageWidth == null ||
      imageWidth <= 0 ||
      imageHeight == null ||
      imageHeight <= 0) {
    // Boyutu bilinmeyen eski mesajlar: kare çerçeve, yüklenince zıplamaz.
    return ChatMediaShape.square;
  }
  final ratio = imageWidth / imageHeight;
  if (ratio < 0.85) return ChatMediaShape.portrait;
  if (ratio > 1.18) return ChatMediaShape.landscape;
  return ChatMediaShape.square;
}

/// Sohbetteki medya balonlarının ortak genişliği (fotoğraf ve belge aynı).
double chatMediaWidth(Size screen) =>
    min(max(0.0, screen.width * 0.68 - _maxBubbleInsets), kChatMediaMaxWidth);

/// Fotoğraf balonunun sabit çerçeve boyutu: ortak genişlik + oran tipine göre
/// sabit yükseklik (dikey 260×330, kare 260×260, yatay 260×195).
Size chatMediaFrameSize(Size screen, {int? imageWidth, int? imageHeight}) {
  final width = chatMediaWidth(screen);
  final factor = switch (chatMediaShapeFor(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  )) {
    ChatMediaShape.portrait => 330 / 260,
    ChatMediaShape.square => 1.0,
    ChatMediaShape.landscape => 0.75,
  };
  return Size(width, min(width * factor, screen.height * 0.45));
}

/// Fotoğrafı sabit çerçevede WhatsApp gibi gösterir: fotoğraf çerçeveyi
/// dolduracak kadar yakınlaştırılır (cover), taşan kenarlar kırpılır. Fotoğrafın
/// tamamı dokununca açılan tam ekran görüntüleyicide görünür.
class ChatImageFrame extends StatelessWidget {
  const ChatImageFrame({
    super.key,
    required this.size,
    required this.imageBuilder,
  });

  final Size size;
  final Widget Function(BoxFit fit) imageBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ColoredBox(
        color: const Color(0xFF1B2230),
        child: imageBuilder(BoxFit.cover),
      ),
    );
  }
}
