import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';

void main() {
  test('configuration is usable with debug defaults or explicit release origins', () {
    expect(AppConfig.baseUrl, isNotEmpty);
    expect(AppConfig.siteBaseUrl, isNotEmpty);
    expect(AppConfig.validateForStartup, returnsNormally);
  });
}
