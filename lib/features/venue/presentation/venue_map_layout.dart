import 'package:flutter/widgets.dart';

/// Reserves room for the native map attribution above the draggable list.
/// The SDK draws its own logo; no replacement attribution is painted here.
class VenueMapLayout {
  static const minSheetExtent = 0.18;
  static const defaultSheetExtent = 0.48;
  static const defaultMaxSheetExtent = 0.94;

  const VenueMapLayout({required this.height, required this.hideSearch});

  final double height;
  final bool hideSearch;

  double get maxSheetExtent {
    if (!height.isFinite || height <= 0) return minSheetExtent;
    // Search/chips occupy the first 102 logical pixels. Leave a separate
    // strip below them for the SDK's logo even when the list is expanded.
    final visibleMapHeight = hideSearch ? 44.0 : 144.0;
    return (1 - visibleMapHeight / height).clamp(
      minSheetExtent,
      defaultMaxSheetExtent,
    );
  }

  double get initialSheetExtent =>
      defaultSheetExtent.clamp(minSheetExtent, maxSheetExtent);

  EdgeInsets padding({
    required bool sheetVisible,
    required double sheetExtent,
  }) {
    if (!sheetVisible || !height.isFinite || height <= 0) {
      return EdgeInsets.zero;
    }
    final extent = sheetExtent.isFinite
        ? sheetExtent.clamp(minSheetExtent, maxSheetExtent)
        : initialSheetExtent;
    return EdgeInsets.only(bottom: height * extent + 6);
  }
}
