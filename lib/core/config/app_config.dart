class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    //defaultValue: 'http://192.168.70.243:3000',
    defaultValue: 'http://192.168.1.190:3000',
  );

  /// Public marketing/legal site (privacy, terms, support, invite landing).
  /// Distinct from [baseUrl] which is the API host.
  static const String siteBaseUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://staging.kmstry.net',
  );
}
