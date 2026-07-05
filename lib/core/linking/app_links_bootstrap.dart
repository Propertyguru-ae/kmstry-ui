import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

/// E-postadaki `${APP_URL}/auth/reset-password?token=...` linkini yakalayıp
/// [AuthRoutes.resetPassword] ekranına yönlendirir. Android App Links / iOS
/// Universal Links alan adı eşlemesi ayrıca yapılandırılmalıdır.
///
/// [app_links] bazen (hot reload, eksik pod derlemesi vb.) [MissingPluginException]
/// verir; bu durumda sessizce devre dışı kalır, uygulama çalışmaya devam eder.
class AppLinksBootstrap extends StatefulWidget {
  const AppLinksBootstrap({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppLinksBootstrap> createState() => _AppLinksBootstrapState();
}

class _AppLinksBootstrapState extends State<AppLinksBootstrap> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _handledInitial = false;

  @override
  void initState() {
    super.initState();
    // Yerel kanalın hazır olması için bir kare gecikme; MissingPlugin riskini azaltır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeInitAppLinks();
    });
  }

  Future<void> _safeInitAppLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_handledInitial && mounted) {
            _handledInitial = true;
            _handleUri(initial);
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLinks getInitialLink kullanılamadı: $e');
      }
    }

    if (!mounted) return;

    try {
      _sub = _appLinks.uriLinkStream.listen(
        _handleUri,
        onError: (Object e, StackTrace _) {
          if (kDebugMode) {
            debugPrint('AppLinks uriLinkStream: $e');
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AppLinks uriLinkStream dinlenemedi: $e');
      }
    }
  }

  void _handleUri(Uri uri) {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;

    final segments = uri.pathSegments;

    // NOT: /invite/:token linki artık web-only (kmstry-site kayıt formu).
    // Uygulama bu linki ele almaz; kasıtlı olarak yönlendirme yapılmıyor.

    // /auth/reset-password?token=...
    if (segments.any((s) => s.toLowerCase() == 'reset-password')) {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        nav.pushNamed(AuthRoutes.resetPassword, arguments: token);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
