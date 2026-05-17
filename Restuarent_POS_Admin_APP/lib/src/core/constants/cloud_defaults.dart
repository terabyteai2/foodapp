class CloudDefaults {
  CloudDefaults._();

  static String productionBaseUrl = 'http://192.168.1.102:8000';

  static String placeholderBaseUrl = 'https://your-domain.ngrok-free.app';

  static String baseUrl = String.fromEnvironment(
    'POS_CLOUD_API_URL',
    defaultValue: productionBaseUrl,
  );

  static bool forceCloudSyncEnabled = bool.fromEnvironment(
    'POS_CLOUD_SYNC_ENABLED',
  );

  static bool get hasConfiguredBaseUrl {
    final trimmed = baseUrl.trim();
    return trimmed.isNotEmpty && trimmed != placeholderBaseUrl;
  }

  static bool get shouldEnableSyncByDefault {
    return forceCloudSyncEnabled || hasConfiguredBaseUrl;
  }

  static String resolveBaseUrl(String? override) {
    final trimmed = override?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == placeholderBaseUrl) {
      return baseUrl;
    }
    return trimmed;
  }
}
