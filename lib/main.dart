import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'features/auth/presentation/auth_routes.dart';
import 'features/auth/presentation/reset_password_page.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/push/push_manager.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialize (push notif icin)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushManager.instance.init();

  //Kameraları yükle
  cameras = await availableCameras();

  //Notifications
  await initNotifications();

  if (kDebugMode) {
    await SecureStorage.clearSession();
  }

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

    return MaterialApp(
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
    );
  }
}
