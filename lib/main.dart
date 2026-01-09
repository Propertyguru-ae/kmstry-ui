import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'features/auth/presentation/auth_routes.dart';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initNotifications();
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    await SecureStorage.clear();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: AuthRoutes.authGate,
      routes: AuthRoutes.routes,
    );
  }
}
