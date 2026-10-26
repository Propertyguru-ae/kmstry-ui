import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Forms without an AppBar still need legible OS status/navigation icons.
/// Individual screens (such as the branded splash) may override this region.
class AppearanceSystemUi extends StatelessWidget {
  const AppearanceSystemUi({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: isDark ? Colors.black : Colors.white,
          ),
      child: child,
    );
  }
}
