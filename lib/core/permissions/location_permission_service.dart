import 'package:permission_handler/permission_handler.dart';

class LocationPermissionService {
  Future<PermissionStatus> status() {
    return Permission.locationWhenInUse.status;
  }

  Future<PermissionStatus> request() {
    return Permission.locationWhenInUse.request();
  }

  Future<bool> isGranted() async {
    final current = await status();
    return current.isGranted;
  }
}
