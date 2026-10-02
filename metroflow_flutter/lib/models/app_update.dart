/// Parsed result of the backend's update check
/// (GET /api/public/app-updates/check).
///
/// The server compares the caller's `version_code` (the monotonic build
/// number injected by `flutter build --build-number=N`) against the newest
/// ACTIVE row in its `app_versions` table:
///   - `update_available`: a newer active release exists
///   - `update_required` : force_update flag set on the latest release OR the
///                         caller is below the max(min_supported_version_code)
///                         floor across active releases
///
/// All parsing is defensive: any malformed field degrades to "no update"
/// rather than throwing, so a bad backend payload can never crash the app.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.platform,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.updateAvailable,
    required this.updateRequired,
    this.currentVersionCode,
    this.currentVersionName,
    this.releaseNotes,
    this.storeUrl,
    this.minSupportedVersionCode,
  });

  final String platform; // 'ios' | 'android'
  final int? currentVersionCode;
  final String? currentVersionName;
  final int latestVersionCode;
  final String latestVersionName;
  final bool updateAvailable;
  final bool updateRequired;
  final String? releaseNotes;
  final String? storeUrl;
  final int? minSupportedVersionCode;

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
    int? currentVersionCode,
    String? currentVersionName,
  }) {
    final latest = data['latest'] is Map<dynamic, dynamic>
        ? data['latest'] as Map<dynamic, dynamic>
        : const <dynamic, dynamic>{};

    final latestVersionName =
        _cleanString(latest['version_name']) ?? '';
    final latestVersionCode = _cleanInt(latest['version_code']) ?? 0;

    // Trust the server decision, but re-verify the comparison locally when
    // both build numbers are known — protects against stale/incorrect
    // server-side caching ever forcing users backwards.
    bool updateAvailable = data['update_available'] == true;
    if (updateAvailable &&
        currentVersionCode != null &&
        latestVersionCode > 0) {
      updateAvailable = latestVersionCode > currentVersionCode;
    }

    final updateRequired =
        (data['update_required'] == true || data['force_update'] == true) &&
            updateAvailable;

    final minSupported = _cleanInt(data['min_supported_version_code']) ??
        _cleanInt(latest['min_supported_version_code']);

    return AppUpdateInfo(
      platform: platform,
      currentVersionCode: currentVersionCode,
      currentVersionName: currentVersionName,
      latestVersionCode: latestVersionCode,
      latestVersionName:
          latestVersionName.isEmpty ? 'latest' : latestVersionName,
      updateAvailable: updateAvailable,
      updateRequired: updateRequired,
      releaseNotes: _cleanString(latest['release_notes']),
      storeUrl: _cleanString(latest['store_url']),
      minSupportedVersionCode: minSupported,
    );
  }
}
