class CloudDefaults {
  CloudDefaults._();

  static String localBaseUrl = String.fromEnvironment(
    'POS_LOCAL_API_URL',
    defaultValue: 'http://192.168.1.102:8000',
  );

  static String cloudFallbackBaseUrl = String.fromEnvironment(
    'POS_CLOUD_FALLBACK_API_URL',
    defaultValue: '',
  );

  static String productionBaseUrl = localBaseUrl;

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
    return _isUsableBaseUrl(trimmed) ||
        _isUsableBaseUrl(cloudFallbackBaseUrl.trim());
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

  static Uri? fallbackBaseUriFor(Uri currentBase) {
    final fallback = Uri.tryParse(cloudFallbackBaseUrl.trim());
    if (fallback == null || !_isUsableUri(fallback)) return null;
    if (_sameBase(currentBase, fallback)) return null;
    return fallback;
  }

  static bool _isUsableBaseUrl(String value) {
    if (value.isEmpty || value == placeholderBaseUrl) return false;
    final uri = Uri.tryParse(value);
    return uri != null && _isUsableUri(uri);
  }

  static bool _isUsableUri(Uri uri) {
    return uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static bool _sameBase(Uri a, Uri b) {
    return a.scheme == b.scheme &&
        a.host == b.host &&
        a.port == b.port &&
        _trimSlash(a.path) == _trimSlash(b.path);
  }

  static String _trimSlash(String value) {
    if (value.endsWith('/')) return value.substring(0, value.length - 1);
    return value;
  }
}
