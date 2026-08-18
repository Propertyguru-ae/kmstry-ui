import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';

/// Alt ağacını, cihazın light/dark ayarından bağımsız olarak DAİMA dark
/// modda render eder.
///
/// Auth + onboarding akışı (signup, email OTP, şifre, bio vb.) dark-only
/// tasarlandığı için bu sayfalar bununla sarılır. Uygulamanın geri kalanı
/// (dashboard vb.) etkilenmez; onlar sistem temasını takip etmeye devam eder.
class ForceDark extends StatelessWidget {
  final Widget child;
  const ForceDark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Builder(
        builder: (innerContext) {
          final mq = MediaQuery.of(innerContext);
          return MediaQuery(
            data: mq.copyWith(platformBrightness: Brightness.dark),
            child: child,
          );
        },
      ),
    );
  }
}
