import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:provider/provider.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_routes.dart';
import 'features/auth/presentation/reset_password_page.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/push/push_background_handler.dart';
import 'core/push/push_manager.dart';
import 'core/push/push_deep_link_handler.dart';
import 'core/linking/app_links_bootstrap.dart';

late List<CameraDescription> cameras;

/// Global navigator key — PushDeepLinkHandler ve AppLinksBootstrap tarafından
/// paylaşılır.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must be registered before Firebase.initializeApp so the background isolate
  // can find the handler when the app is terminated.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Firebase initialize (push notif icin)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firebase App Check — istekleri gerçek, değiştirilmemiş uygulamamızdan
  // geldiğini kanıtlar (iOS: App Attest, Android: Play Integrity). Backend'in
  // App Check guard'ı bu token'ı doğrular ve bot/script kayıtlarını engeller.
  // Debug build'lerde App Attest/Play Integrity çalışmadığı için debug
  // provider kullanılır (konsola çıkan debug token'ı Firebase'e eklemek gerekir).
  try {
    // NOT: appleProvider/androidProvider parametreleri deprecated ama çalışıyor;
    // yeni sınıf-tabanlı API'ye geçince buradaki enum kullanımı güncellenebilir.
    // ignore: deprecated_member_use
    await FirebaseAppCheck.instance.activate(
      // ignore: deprecated_member_use
      appleProvider: kReleaseMode
          ? AppleProvider.appAttest
          : AppleProvider.debug,
      // ignore: deprecated_member_use
      androidProvider: kReleaseMode
          ? AndroidProvider.playIntegrity
          : AndroidProvider.debug,
    );
    // Token'ı otomatik tazele — süresi dolunca istekler token'sız kalmasın.
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    // Token'ı önceden ISIT: App Attest ilk üretimi gecikmeli/asenkron olduğu
    // için, açılıştaki ilk /auth/me isteği token'dan önce gidip "missing"
    // görünüyordu. Burada bir kez zorla çekip cache'e alıyoruz ki auth
    // isteklerine token yetişsin. Fire-and-forget; hatayı KENDİ içinde yut —
    // aksi halde reject olan Future dıştaki try/catch'e düşmeyip "unhandled
    // exception" olarak loglanıyordu. (Başarısızlığı auto-refresh sonra halleder.)
    unawaited(() async {
      try {
        await FirebaseAppCheck.instance.getToken(true);
      } catch (_) {
        debugPrint(
          '⚠️ App Check warm-up failed; automatic refresh will retry.',
        );
      }
    }());
  } catch (e) {
    debugPrint('⚠️ App Check activate failed: $e');
  }

  await PushManager.instance.init();

  // FCM bildirim tap routing — uygulamanın ömrü boyunca aktif kalır
  PushDeepLinkHandler.instance.init(navigatorKey);

  //Kameraları yükle
  cameras = await availableCameras();

  //Notifications
  await initNotifications(navigatorKey: navigatorKey);

  // Wire up silent 401 token-refresh interceptor.
  AuthRepository.init(navigatorKey: navigatorKey);

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return AppLinksBootstrap(
      navigatorKey: navigatorKey,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'KMSTRY',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeProvider.themeMode,
        initialRoute: AuthRoutes.startupGate,
        routes: AuthRoutes.routes,
        onGenerateRoute: (RouteSettings settings) {
          if (settings.name == AuthRoutes.resetPassword) {
            final args = settings.arguments;
            String? token;
            if (args is String) {
              token = args;
            } else if (args is Map && args['token'] is String) {
              token = args['token'] as String;
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => ResetPasswordPage(resetToken: token),
            );
          }
          return null;
        },
      ),
    );
  }
}
