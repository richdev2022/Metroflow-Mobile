/// Parsed result of the backend's update check
/// (GET /api/public/app-updates/check).
///
/// Simplified flow (2026-11): the prompt is driven by the release row's
/// `update_available` TOGGLE — the admin flips it, users get the modal
/// instantly. No version numbers are involved:
///   - `update_available`: the admin toggle is ON (or, for legacy backends,
///     a newer active release exists)
///   - `update_required` : force_update is set on the release — the modal
///                         cannot be skipped
///   - `release.url`     : the download URL (store listing or custom link)
///
/// All parsing is defensive: any malformed field degrades to "no update"
/// rather than throwing, so a bad backend payload can never crash the app.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.appType,
    required this.promptSource,
    required this.releaseId,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.updateAvailable,
    required this.updateRequired,
    this.currentVersionCode,
    this.currentVersionName,
    this.releaseNotes,
    this.downloadUrl,
    this.urlType,
    this.minSupportedVersionCode,
  });

  final String platform; // 'ios' | 'android'
  final String appType; // 'personal' | 'business'
  final String promptSource; // 'toggle' | 'version' | '' (legacy)
  final String releaseId; // '' when unknown (legacy backend)
  final int? currentVersionCode;
  final String? currentVersionName;
  final int latestVersionCode;
  final String latestVersionName;
  final bool updateAvailable;
  final bool updateRequired;
  final String? releaseNotes;

  /// The URL the admin passed — a store listing OR a custom download link.
  final String? downloadUrl;

  /// 'store' | 'custom' — custom links are mobile-only (never on the site).
  final String? urlType;

  final int? minSupportedVersionCode;

  /// Stable id used for skip/handled bookkeeping. Falls back to the version
  /// code for legacy backends that do not send the release id.
  String get trackingKey => releaseId.isNotEmpty
      ? releaseId
      : 'code-$latestVersionCode';

  /// "1.4.0 (build 14)" — used by the Settings row and toasts.
  String get currentLabel {
    final name = (currentVersionName == null || currentVersionName!.isEmpty)
        ? null
        : currentVersionName;
    if (name != null && currentVersionCode != null) {
      return '$name (build $currentVersionCode)';
    }
    return name ?? 'build ${currentVersionCode ?? '?'}';
  }

  String get latestLabel => 'v$latestVersionName';

  static String? _cleanString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _cleanInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  factory AppUpdateInfo.fromApi(
    Map<dynamic, dynamic> data, {
    required String platform,
    required String appType,
    int? currentVersionCode,
    String? currentVersionName,
  }) {
    final latest = data['latest'] is Map<dynamic, dynamic>
        ? data['latest'] as Map<dynamic, dynamic>
        : const <dynamic, dynamic>{};
    final release = data['release'] is Map<dynamic, dynamic>
        ? data['release'] as Map<dynamic, dynamic>
        : const <dynamic, dynamic>{};

    final latestVersionName =
        _cleanString(latest['version_name']) ?? '';
    final latestVersionCode = _cleanInt(latest['version_code']) ?? 0;

    final promptSource = _cleanString(data['prompt_source']) ?? '';
    final releaseId = _cleanString(release['id'] ?? latest['id']) ?? '';

    // Trust the server decision, EXCEPT for the legacy version-comparison
    // signal where a local re-verify protects against stale/incorrect
    // server-side caching ever forcing users backwards. The toggle signal
    // ('toggle') is the admin's explicit intent and is always trusted.
    bool updateAvailable = data['update_available'] == true;
    if (updateAvailable &&
        promptSource != 'toggle' &&
        currentVersionCode != null &&
        latestVersionCode > 0) {
      updateAvailable = latestVersionCode > currentVersionCode;
    }

    final releaseForce = release['force_update'] == true;
    final updateRequired =
        (data['update_required'] == true ||
            data['force_update'] == true ||
            releaseForce) &&
            updateAvailable;

    // The download URL: the simplified release block first, then the legacy
    // latest.store_url (which carries whatever URL the admin passed).
    final downloadUrl =
        _cleanString(release['url']) ?? _cleanString(latest['store_url']);
    final urlType = _cleanString(release['url_type'] ?? latest['url_type']);

    final minSupported = _cleanInt(data['min_supported_version_code']) ??
        _cleanInt(latest['min_supported_version_code']);

    return AppUpdateInfo(
      platform: platform,
      appType: _cleanString(release['app_type'] ?? latest['app_type']) ?? appType,
      promptSource: promptSource,
      releaseId: releaseId,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      latestVersionCode: latestVersionCode,
      latestVersionName:
          latestVersionName.isEmpty ? 'latest' : latestVersionName,
      updateAvailable: updateAvailable,
      updateRequired: updateRequired,
      releaseNotes:
          _cleanString(release['release_notes'] ?? latest['release_notes']),
      downloadUrl: downloadUrl,
      urlType: urlType,
      minSupportedVersionCode: minSupported,
    );
  }
}
