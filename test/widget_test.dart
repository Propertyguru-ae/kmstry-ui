import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/main.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app startup smoke test', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues(const <String, String>{});

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
