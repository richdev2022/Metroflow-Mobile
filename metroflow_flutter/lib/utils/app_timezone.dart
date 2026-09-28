import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart';
import 'package:timezone/timezone.dart' as tz;

/// App-wide business timezone + timezone-aware date formatting.
///
/// Mirrors the webapp's `client/lib/datetime.ts`: the timezone is set on the
/// Settings page (persisted on the business record via `PUT /settings` and
/// locally via SharedPreferences) and every user-facing date/time should be
/// rendered through these helpers so the chosen timezone is honoured
/// consistently.
///
/// If no stored setting exists yet, a best-effort initial guess is derived
/// from the device UTC offset (`DateTime.now().timeZoneOffset`) — the stored
/// setting always remains authoritative once present.
class AppTimezone {
  AppTimezone._internal();

  static final AppTimezone instance = AppTimezone._internal();

  factory AppTimezone() => instance;

  /// SharedPreferences key for the locally cached business timezone.
  static const String storageKey = 'business_timezone';

  String? _tz;
  bool _tzDbReady = false;

  /// Current display timezone (IANA name). Falls back to 'UTC'.
  String get current => _tz ?? 'UTC';

  /// Whether a timezone has been explicitly set/stored.
  ///
  /// Note: [load] seeds an offset-based device guess when nothing is stored,
  /// so this only reports true before the first [load]/[set] call.
  bool get hasExplicitTimezone => _tz != null;

  /// Ensure the timezone database is loaded exactly once.
  void _ensureTzDatabase() {
    if (_tzDbReady) return;
    try {
      initializeTimeZones();
      _tzDbReady = true;
    } catch (e) {
      debugPrint('AppTimezone: failed to initialize timezone database: $e');
    }
  }

  /// Resolve the configured IANA name to a tz database location, or null when
  /// the database isn't ready / the name is unknown (graceful fallback to
  /// device-local rendering).
  tz.Location? _location() {
    _ensureTzDatabase();
    if (_tz == null || _tz!.isEmpty) return null;
    try {
      return tz.getLocation(_tz!);
    } catch (e) {
      return null;
    }
  }

  /// Load the stored timezone from SharedPreferences (call once at boot).
  /// When nothing has been stored yet, fall back to the offset-based device
  /// guess — the stored setting always remains authoritative once present.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(storageKey);
      _tz = (stored == null || stored.isEmpty) ? null : stored;
    } catch (e) {
      debugPrint('AppTimezone: failed to load stored timezone: $e');
    }
    _tz ??= guessFromDeviceOffset();
  }

  /// Update the app-wide display timezone and persist it locally.
  ///
  /// Server persistence is handled by the caller (Settings →
  /// `PUT /settings { timezone }`) so a network failure never blocks the
  /// local switch.
  void set(String name) {
    final next = name.trim();
    _tz = next.isEmpty ? 'UTC' : next;
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, current);
    } catch (e) {
      debugPrint('AppTimezone: failed to persist timezone: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Conversion helpers
  // ---------------------------------------------------------------------------

  /// Convert [dt] (any DateTime — UTC, local or TZDateTime) into the
  /// configured timezone. Falls back to the original DateTime (device-local
  /// rendering) when the configured zone cannot be resolved.
  ///
  /// Note: [tz.TZDateTime.from] copies wall-clock fields when given a non-UTC
  /// DateTime, so we normalize through `toUtc()` first to guarantee a true
  /// instant conversion regardless of the input kind.
  DateTime inAppTimezone(DateTime dt) {
    final loc = _location();
    if (loc == null) return dt;
    try {
      return tz.TZDateTime.from(dt.toUtc(), loc);
    } catch (e) {
      return dt;
    }
  }

  /// Best-effort initial guess derived from the device UTC offset. The stored
  /// setting (server or local) is always authoritative over this guess.
  static String guessFromDeviceOffset() {
    final now = DateTime.now();
    final offsetMinutes = now.timeZoneOffset.inMinutes;
    // Representative zone per common offset. Deliberately conservative —
    // an offset alone cannot disambiguate DST, so this is only a default
    // until the user picks a timezone in Settings.
    const table = <int, String>{
      0: 'UTC',
      60: 'Africa/Lagos',
      120: 'Africa/Cairo',
      180: 'Asia/Riyadh',
      210: 'Asia/Tehran',
      240: 'Asia/Dubai',
      300: 'Asia/Karachi',
      330: 'Asia/Kolkata',
      345: 'Asia/Kathmandu',
      360: 'Asia/Dhaka',
      420: 'Asia/Bangkok',
      480: 'Asia/Singapore',
      540: 'Asia/Tokyo',
      600: 'Australia/Sydney',
      720: 'Pacific/Auckland',
      -180: 'America/Sao_Paulo',
      -240: 'America/New_York',
      -300: 'America/Chicago',
      -360: 'America/Chicago',
      -420: 'America/Denver',
      -480: 'America/Los_Angeles',
    };
    return table[offsetMinutes] ?? 'UTC';
  }

  /// Normalize an instant to a bare (year, month, day) key in the configured
  /// timezone — used for day-bucketing (weekly activity charts etc.).
  DateTime dateKeyIn(DateTime dt) {
    final z = inAppTimezone(dt);
    return DateTime(z.year, z.month, z.day);
  }

  /// Today's date key (midnight, device clock arithmetic) in the configured
  /// timezone.
  DateTime todayKey() => dateKeyIn(DateTime.now());

  // ---------------------------------------------------------------------------
  // Formatting helpers (mirror client/lib/datetime.ts)
  // ---------------------------------------------------------------------------

  String _fmt(DateTime? dt, String pattern) {
    if (dt == null) return '—';
    try {
      return DateFormat(pattern).format(inAppTimezone(dt));
    } catch (e) {
      return '—';
    }
  }

  /// e.g. "Sep 28, 2026"
  String formatDate(DateTime? dt) => _fmt(dt, 'MMM d, yyyy');

  /// e.g. "3:45 PM"
  String formatTime(DateTime? dt) => _fmt(dt, 'h:mm a');

  /// e.g. "Sep 28, 2026, 3:45 PM"
  String formatDateTime(DateTime? dt) => _fmt(dt, 'MMM d, yyyy, h:mm a');

  /// e.g. "Mon, Sep 28, 2026"
  String formatDateLong(DateTime? dt) => _fmt(dt, 'EEE, MMM d, yyyy');

  /// Compact date, e.g. "Sep 28" (labels inside cards/chips).
  String formatDateShort(DateTime? dt) => _fmt(dt, 'MMM d');

  /// Full weekday date, e.g. "Monday, September 28, 2026" (greeting headers).
  String formatDateFull(DateTime? dt) => _fmt(dt, 'EEEE, MMMM d, yyyy');

  /// Tolerant parse of a backend date string/DateTime into a DateTime, or
  /// null when it cannot be parsed.
  static DateTime? tryParse(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Format a raw backend date string in the configured timezone; returns the
  /// original string when unparsable.
  String formatDateValue(Object? value) {
    final dt = tryParse(value);
    if (dt == null) return value == null ? '—' : value.toString();
    return formatDate(dt);
  }

  /// Format a raw backend datetime string (date + time) in the configured
  /// timezone; returns the original string when unparsable.
  String formatDateTimeValue(Object? value) {
    final dt = tryParse(value);
    if (dt == null) return value == null ? '—' : value.toString();
    return formatDateTime(dt);
  }
}
