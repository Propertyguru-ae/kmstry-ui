import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/session_environment_coordinator.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

void main() {
  const staging = 'https://api.kmstry.net';
  const preprod = 'https://pre-prod-api.kmstry.net';

  test('an empty session stays empty', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: false,
        stored: const StoredSessionEnvironment(
          apiOrigin: staging,
          buildEnv: 'staging',
        ),
        currentApiOrigin: preprod,
        currentBuildEnv: 'pre-prod',
      ),
      SessionEnvironmentAction.keep,
    );
  });

  test('a correctly bound session is kept', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: true,
        stored: const StoredSessionEnvironment(
          apiOrigin: preprod,
          buildEnv: 'pre-prod',
        ),
        currentApiOrigin: preprod,
        currentBuildEnv: 'pre-prod',
      ),
      SessionEnvironmentAction.keep,
    );
  });

  test('an old staging session is cleared before reaching pre-prod', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: true,
        stored: const StoredSessionEnvironment(
          apiOrigin: staging,
          buildEnv: 'staging',
        ),
        currentApiOrigin: preprod,
        currentBuildEnv: 'pre-prod',
      ),
      SessionEnvironmentAction.clearForSwitch,
    );
    expect(
      SessionEnvironmentPolicy.oldApiOrigin(
        stored: const StoredSessionEnvironment(
          apiOrigin: staging,
          buildEnv: 'staging',
        ),
        currentBuildEnv: 'pre-prod',
      ),
      staging,
    );
  });

  test('legacy internal-test session is bound on staging', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: true,
        stored: null,
        currentApiOrigin: staging,
        currentBuildEnv: 'staging',
      ),
      SessionEnvironmentAction.bindLegacy,
    );
  });

  test('legacy internal-test session is cleared on pre-prod', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: true,
        stored: null,
        currentApiOrigin: preprod,
        currentBuildEnv: 'pre-prod',
      ),
      SessionEnvironmentAction.clearForSwitch,
    );
    expect(
      SessionEnvironmentPolicy.oldApiOrigin(
        stored: null,
        currentBuildEnv: 'pre-prod',
      ),
      staging,
    );
  });

  test('a changed API origin cannot reuse an old session', () {
    expect(
      SessionEnvironmentPolicy.decide(
        hasSession: true,
        stored: const StoredSessionEnvironment(
          apiOrigin: staging,
          buildEnv: 'staging',
        ),
        currentApiOrigin: 'https://unexpected.kmstry.net',
        currentBuildEnv: 'staging',
      ),
      SessionEnvironmentAction.clearForSwitch,
    );
  });
}
