import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/media/placed_overlay_text.dart';

/// Editörlerdeki gibi durumu tutan küçük bir sarmalayıcı.
class _Harness extends StatefulWidget {
  final VoidCallback onTap;
  const _Harness({required this.onTap});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Offset? center;
  double scale = 1.0;
  double rotation = 0.0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: PlacedOverlayText(
                text: 'Hi',
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
                center: center,
                scale: scale,
                rotation: rotation,
                onTap: widget.onTap,
                onTransform: (c, s, r) => setState(() {
                  center = c;
                  scale = s;
                  rotation = r;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  late _HarnessState state;
  late int taps;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    taps = 0;
    await tester.pumpWidget(_Harness(onTap: () => taps++));
    state = tester.state(find.byType(_Harness));
  }

  Offset textCenter(WidgetTester tester) => tester.getCenter(find.text('Hi'));

  testWidgets('one finger drag starting on the text moves it', (tester) async {
    await pump(tester);
    final start = textCenter(tester);
    await tester.dragFrom(start, const Offset(40, 90));
    await tester.pump();

    expect(state.center, isNotNull);
    expect(textCenter(tester).dx, closeTo(start.dx + 40, 2));
    expect(textCenter(tester).dy, closeTo(start.dy + 90, 2));
  });

  testWidgets('one finger drag on empty space does not move the text', (
    tester,
  ) async {
    await pump(tester);
    final start = textCenter(tester);
    await tester.dragFrom(const Offset(30, 700), const Offset(60, -120));
    await tester.pump();

    expect(textCenter(tester), start);
  });

  testWidgets('two finger pinch works anywhere on screen, not only on text', (
    tester,
  ) async {
    await pump(tester);
    // Parmaklar yazıdan uzakta, ekranın alt kısmında.
    final a = await tester.startGesture(const Offset(150, 650), pointer: 1);
    final b = await tester.startGesture(const Offset(250, 650), pointer: 2);
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await a.moveTo(Offset(150 - i * 10.0, 650));
      await b.moveTo(Offset(250 + i * 10.0, 650));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();

    // 100px → 200px aralık: ~2x büyüdü.
    expect(state.scale, closeTo(2.0, 0.05));
  });

  testWidgets('scale is clamped to a sane range', (tester) async {
    await pump(tester);
    final a = await tester.startGesture(const Offset(100, 600), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 600), pointer: 2);
    await tester.pump();
    for (var i = 1; i <= 9; i++) {
      await a.moveTo(Offset(100 + i * 11.0, 600));
      await b.moveTo(Offset(300 - i * 11.0, 600));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();

    expect(state.scale, greaterThanOrEqualTo(0.4));
  });

  testWidgets('tapping the text opens the editor; tapping elsewhere does not', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapAt(const Offset(30, 750));
    await tester.pump();
    expect(taps, 0);

    await tester.tapAt(textCenter(tester));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('text cannot be dragged off screen', (tester) async {
    await pump(tester);
    await tester.dragFrom(textCenter(tester), const Offset(0, 2000));
    await tester.pump();

    expect(state.center!.dy, lessThanOrEqualTo(800));
  });
}
