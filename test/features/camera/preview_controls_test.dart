import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/camera/presentation/preview_controls.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: child),
    ),
  ),
);

Color? _fillOf(WidgetTester tester, String label) {
  final box = tester.widget<DecoratedBox>(
    find
        .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('confirm is the blue app CTA, retake is the dark pill', (
    tester,
  ) async {
    var confirmed = 0;
    var cancelled = 0;
    await _pump(
      tester,
      PreviewBottomActions(
        cancelLabel: 'Retake',
        confirmLabel: 'Use',
        onCancel: () => cancelled++,
        onConfirm: () => confirmed++,
      ),
    );

    expect(_fillOf(tester, 'Use'), AppColors.blue);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(_fillOf(tester, 'Retake'), isNot(AppColors.blue));
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    await tester.tap(find.text('Use'));
    await tester.tap(find.text('Retake'));
    expect(confirmed, 1);
    expect(cancelled, 1);
  });

  testWidgets('confirming shows a spinner instead of the label', (
    tester,
  ) async {
    await _pump(
      tester,
      const PreviewBottomActions(
        cancelLabel: 'Retake',
        confirmLabel: 'Use',
        onCancel: null,
        onConfirm: null,
        confirming: true,
      ),
    );

    expect(find.text('Use'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('tool button exposes its tooltip (X / Tt / download)', (
    tester,
  ) async {
    await _pump(
      tester,
      PreviewToolButton(
        tooltip: 'Close',
        icon: Icons.close_rounded,
        onTap: () {},
      ),
    );
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
