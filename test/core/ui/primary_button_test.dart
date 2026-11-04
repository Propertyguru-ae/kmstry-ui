import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryButton(label: 'Continue', onPressed: () {}),
        ),
      ),
    );
  }

  testWidgets('Ink carries no shadow, so Material cannot clip it to a square', (
    tester,
  ) async {
    await pumpButton(tester);

    final ink = tester.widget<Ink>(
      find.descendant(
        of: find.byType(PrimaryButton),
        matching: find.byType(Ink),
      ),
    );
    final decoration = ink.decoration! as BoxDecoration;

    expect(decoration.boxShadow, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(14));
  });

  testWidgets('shadow is painted outside the Material with the same radius', (
    tester,
  ) async {
    await pumpButton(tester);

    final material = find.descendant(
      of: find.byType(PrimaryButton),
      matching: find.byType(Material),
    );
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: material, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;

    expect(decoration.boxShadow, isNotEmpty);
    expect(decoration.borderRadius, BorderRadius.circular(14));
  });
}
