import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Android'de bazı OEM'ler (Xiaomi, Huawei, Samsung, Oppo, vb.) agresif
/// battery optimization uygular ve bu, uygulama arka plandayken FCM
/// bağlantısının/push teslimatının OS tarafından kesilmesine yol açabilir.
/// iOS'ta bu kavram yok — bu servis sadece Android içindir.
class BatteryOptimizationService {
  /// true → optimizasyon devre dışı (push için güvenli)
  /// false → optimizasyon hâlâ aktif (push gecikebilir/kaybolabilir)
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Sistem diyaloğunu açar — kullanıcı "Allow"/"Don't allow" seçer.
  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
