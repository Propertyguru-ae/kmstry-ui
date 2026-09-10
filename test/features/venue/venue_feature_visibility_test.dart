import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_feature_visibility.dart';

void main() {
  test('menu entry points are temporarily hidden', () {
    expect(VenueFeatureVisibility.menu, isFalse);
  });

  test('only menu permission is hidden without changing stored permissions', () {
    final stored = VenuePermission.values.toSet();
    final visible = stored.where(VenueFeatureVisibility.showPermission).toSet();
    expect(visible, stored.difference({VenuePermission.menuManage}));
    expect(stored, contains(VenuePermission.menuManage));
  });
}
