import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'auth_routes.dart';

/// One foreground exit across Personal, Venue and Settings. Keep the current
/// surface stable while credentials are cleared; never navigate on cleanup
/// failure, and never leave an authenticated route below Login.
class LogoutFlow {
  static final ValueNotifier<bool> busy = ValueNotifier(false);
  static Future<void>? _flight;

  static Future<void> run(
    BuildContext context, {
    required Future<void> Function() logout,
  }) {
    final current = _flight;
    if (current != null) return current;
    final navigator = Navigator.of(context, rootNavigator: true);
    busy.value = true;
    return _flight = _run(navigator, logout).whenComplete(() {
      busy.value = false;
      _flight = null;
    });
  }

  static Future<void> _run(
    NavigatorState navigator,
    Future<void> Function() logout,
  ) async {
    try {
      await logout();
      if (!navigator.mounted) return;
      navigator.pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
      // Keep interaction locked until the Login route has its first frame.
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {
      busy.value = false;
      if (!navigator.mounted) return;
      await showPremiumErrorDialog(
        navigator.context,
        message: 'Could not finish signing out. Please try again.',
      );
    }
  }
}

/// The existing row's only visual change: a small, non-modal progress indicator.
class LogoutProgress extends StatelessWidget {
  const LogoutProgress({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: LogoutFlow.busy,
    builder: (context, busy, _) => busy
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.error,
              semanticsLabel: 'Signing out',
            ),
          )
        : const SizedBox.shrink(),
  );
}

/// Also prevents switching Personal/Venue or dismissing the account sheet
/// during exit. No additional screen, popup or loading overlay.
class LogoutGuard extends StatelessWidget {
  const LogoutGuard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: LogoutFlow.busy,
    child: child,
    builder: (_, busy, child) => PopScope(
      canPop: !busy,
      child: AbsorbPointer(absorbing: busy, child: child),
    ),
  );
}
