import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_upload_progress_dialog.dart';

void main() {
  testWidgets(
    'Keep browsing hides progress; late completion cannot pop the next page',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext homeContext;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) {
              homeContext = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      final progress = MediaUploadProgressController(
        title: 'Uploading story',
        message: 'Uploading…',
        allowBackground: true,
      );
      final shown = progress.show(homeContext);
      await tester.pump();
      await shown;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Keep browsing'));
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      );
      await tester.pumpAndSettle();
      progress.update(progress: .8);
      await progress.close();
      progress.dispose();
      await tester.pumpAndSettle();
      expect(find.text('Another page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion removes only its dialog when a new route is above it',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext homeContext;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) {
              homeContext = context;
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      );
      final progress = MediaUploadProgressController(
        title: 'Uploading',
        message: 'Please wait',
      );
      final shown = progress.show(homeContext);
      await tester.pump();
      await shown;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Text('Opened from notification')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await progress.close();
      await tester.pumpAndSettle();
      progress.dispose();
      expect(find.text('Opened from notification'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Uploading'), findsNothing);
    },
  );
}
