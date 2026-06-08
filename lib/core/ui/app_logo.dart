import 'package:flutter/material.dart';

/// Uygulama logosu — AppBar actions veya herhangi bir yerde kullanılabilir.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Image.asset(
        'assets/images/kmstrylogo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}
