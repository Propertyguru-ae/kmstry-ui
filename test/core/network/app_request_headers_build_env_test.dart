import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';

void main() {
  test(
    'release BUILD_ENV is carried in shared JSON/multipart metadata',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'KMSTRY',
        packageName: 'com.brightminds.kmstry',
        version: '1.0.1',
        buildNumber: '95',
        buildSignature: '',
      );
      final headers = await AppRequestHeaders.appMetadata();
      expect(headers['x-kmstry-build-number'], '95');
      expect(headers['x-kmstry-app-version'], '1.0.1');
      if (AppConfig.buildEnv.isNotEmpty) {
        expect(headers['x-kmstry-build-env'], AppConfig.buildEnv);
      } else {
        expect(headers.containsKey('x-kmstry-build-env'), false);
      }
    },
  );
}
