import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

/// Yuvarlatılmış kare (profil) avatarların etrafındaki story halkası.
/// Kendi profilin ve başkasının profili aynı görünümü kullanır.
class RoundedStoryRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;

  /// İzlenmemiş story: logo renkleri.
  static const logoColors = [
    AppColors.magenta,
    AppColors.teal,
    AppColors.blue,
    AppColors.orange,
    AppColors.brand,
  ];

  /// Hepsi izlenmiş: gri.
  static final seenColors = [Colors.grey.shade400, Colors.grey.shade500];

  const RoundedStoryRingPainter({
    required this.colors,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant RoundedStoryRingPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
