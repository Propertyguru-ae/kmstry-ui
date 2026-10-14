import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_map_layout.dart';

void main() {
  test(
    'native attribution stays above the initial, collapsed and expanded list',
    () {
      const layout = VenueMapLayout(height: 700, hideSearch: false);
      for (final extent in [
        VenueMapLayout.minSheetExtent,
        layout.initialSheetExtent,
        layout.maxSheetExtent,
      ]) {
        final padding = layout.padding(sheetVisible: true, sheetExtent: extent);
        expect(padding.bottom, greaterThan(700 * extent));
        expect(padding.left, 0);
        expect(padding.right, 0);
      }
    },
  );

  test('expanded list leaves attribution below search and filter controls', () {
    for (final height in [300.0, 500.0, 700.0, 900.0]) {
      final layout = VenueMapLayout(height: height, hideSearch: false);
      final visibleHeight = height * (1 - layout.maxSheetExtent);
      expect(visibleHeight, closeTo(144, 0.001));
      expect(
        layout.initialSheetExtent,
        lessThanOrEqualTo(layout.maxSheetExtent),
      );
    }
  });

  test('hidden results during search do not leave a stale map inset', () {
    const layout = VenueMapLayout(height: 700, hideSearch: false);
    expect(
      layout.padding(sheetVisible: false, sheetExtent: layout.maxSheetExtent),
      EdgeInsets.zero,
    );
  });

  test('small layouts keep valid draggable sheet bounds', () {
    const layout = VenueMapLayout(height: 200, hideSearch: false);
    expect(layout.initialSheetExtent, layout.maxSheetExtent);
    expect(
      layout.maxSheetExtent,
      greaterThanOrEqualTo(VenueMapLayout.minSheetExtent),
    );
  });

  test('screen without search still leaves room for native attribution', () {
    const layout = VenueMapLayout(height: 500, hideSearch: true);
    expect(500 * (1 - layout.maxSheetExtent), closeTo(44, 0.001));
  });

  test('invalid and out-of-range sizes cannot create invalid map padding', () {
    const layout = VenueMapLayout(height: 700, hideSearch: false);
    expect(
      layout.padding(sheetVisible: true, sheetExtent: 1).bottom,
      layout
          .padding(sheetVisible: true, sheetExtent: layout.maxSheetExtent)
          .bottom,
    );
    expect(
      layout.padding(sheetVisible: true, sheetExtent: double.nan).bottom,
      layout
          .padding(sheetVisible: true, sheetExtent: layout.initialSheetExtent)
          .bottom,
    );
    for (final height in [0.0, double.infinity, double.nan]) {
      expect(
        VenueMapLayout(
          height: height,
          hideSearch: false,
        ).padding(sheetVisible: true, sheetExtent: 0.48),
        EdgeInsets.zero,
      );
    }
  });
}
