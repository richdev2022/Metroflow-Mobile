import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// E2E payload encryption for the app's HTTP API (mobile client side).
///
/// Mirrors the backend contract in `metroflow-backend/server/lib/payload-crypto.ts`
/// EXACTLY:
///
///   AES-256-GCM, key = 32 bytes (base64, or 64 hex chars) taken from the
///   bundled dotenv asset `EXPO_PUBLIC_PAYLOAD_ENCRYPTION_KEY`.
///
/// Wire format (JSON object — survives every JSON body parser):
/// ```
/// { "v": 1, "iv": <b64 12B>, "tag": <b64 16B>, "ct": <b64 ciphertext> }
/// ```
///
/// Protocol:
///   - When the key is configured, JSON request BODIES are sent as an
///     envelope with the `x-mfv-enc: 1` header (see ApiService's request
///     interceptor). The server decrypts and wraps every JSON response in an
///     envelope + the same header — the response interceptor decrypts it
///     BEFORE the app parses the body.
///   - Empty/absent key => `isEnabled == false` => the app stays in plaintext
///     mode (no header, no envelope) — old backends and curl keep working.
///   - Multipart uploads (FormData) are never encrypted (backend bypasses
///     multipart; files are already protected by TLS).
class PayloadCrypto {
  PayloadCrypto._();

  static const int envelopeVersion = 1;
  static const String envKeyName = 'EXPO_PUBLIC_PAYLOAD_ENCRYPTION_KEY';
  static const String encHeaderName = 'x-mfv-enc';
  static const String encHeaderValue = '1';

  /// Pure-Dart AES-GCM (no platform channels). 256-bit key, 12-byte nonce —
  /// matching the backend's `crypto.createCipheriv('aes-256-gcm', key, iv)`.
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Random _random = Random.secure();

  static SecretKey? _cachedKey;
  static bool? _enabledCache;

  /// Test/dev hook: when set, this base64 key REPLACES the dotenv value
  /// (smoke tests cannot load the Flutter dotenv asset). Null restores the
  /// normal dotenv lookup.
  static String? _keyOverride;

  static void setKeyOverride(String? base64Key) {
    _keyOverride = base64Key;
    resetCache();
  }

  /// Raw key material: the override first (tests), else dotenv. Null when
  /// unset/blank (=> plaintext mode). Guarded with try/catch because
  /// `dotenv.env` throws when `loadEnv` was never called (widget tests).
  static String? get _rawKey {
    if (_keyOverride != null && _keyOverride!.trim().isNotEmpty) {
      return _keyOverride!.trim();
    }
    String? raw;
    try {
      raw = dotenv.env[envKeyName];
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// True when a usable key is configured — the interceptors only switch to
  /// envelope mode when this holds.
  static bool get isEnabled {
    if (_enabledCache != null) return _enabledCache!;
    _enabledCache = _loadKey() != null;
    return _enabledCache!;
  }

  /// Test/dev hook: forget the cached key so a changed .env is re-read.
  static void resetCache() {
    _cachedKey = null;
    _enabledCache = null;
  }

  /// 32-byte key from the dotenv value. Accepts base64 (32 bytes) or 64 hex
  /// chars — the backend's loadKey() accepts both shapes, so both env
  /// conventions interoperate. Null => encryption disabled.
  static SecretKey? _loadKey() {
    if (_cachedKey != null) return _cachedKey;
    final raw = _rawKey;
    if (raw == null) return null;
    final isHex = raw.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(raw);
    List<int>? bytes;
    try {
      if (isHex) {
        bytes = _fromHex(raw);
      } else {
        final decoded = base64Decode(raw);
        if (decoded.length == 32) bytes = decoded;
      }
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.length != 32) {
      // A malformed key must never half-enable encryption: fall back to
      // plaintext mode (same policy as the backend ignoring a bad key).
      return null;
    }
    _cachedKey = SecretKeyData(bytes);
    return _cachedKey;
  }

  static List<int> _fromHex(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// Encrypts a JSON-serialisable request body into the wire envelope.
  /// Returns null when encryption is disabled (caller sends plaintext).
  static Future<Map<String, dynamic>?> encryptJson(Map<String, dynamic> body) async {
    final key = _loadKey();
    if (key == null) return null;
    final iv = _randomBytes(12);
    final plaintext = utf8.encode(jsonEncode(body));
    final box = await _cipher.encrypt(plaintext, secretKey: key, nonce: iv);
    return <String, dynamic>{
      'v': envelopeVersion,
      'iv': base64Encode(iv),
      'tag': base64Encode(box.mac.bytes),
      'ct': base64Encode(box.cipherText),
    };
  }

  /// Decrypts a response envelope into the original JSON value (Map/List/
  /// scalar — whatever the server `JSON.stringify`-ed before encrypting).
  /// Throws on any tamper/format failure; callers convert that into a
  /// readable request error instead of trying to parse garbage.
  static Future<dynamic> decryptEnvelope(Map<String, dynamic> envelope) async {
    final key = _loadKey();
    if (key == null) {
      throw StateError('Payload encryption key is not configured');
    }
    if (!looksLikeEnvelope(envelope)) {
      throw const FormatException('Malformed encrypted payload envelope');
    }
    final iv = base64Decode(envelope['iv'].toString());
    final tag = base64Decode(envelope['tag'].toString());
    final ct = base64Decode(envelope['ct'].toString());
    if (iv.length != 12 || tag.length != 16) {
      throw const FormatException('Malformed encrypted payload envelope');
    }
    final box = SecretBox(ct, nonce: iv, mac: Mac(tag));
    final plaintext = await _cipher.decrypt(box, secretKey: key);
    return jsonDecode(utf8.decode(plaintext));
  }

  /// Cheap structural check — same shape the backend uses to recognise its
  /// own envelopes. Combined with the `x-mfv-enc: 1` response header this is
  /// unambiguous (regular API payloads never carry v/iv/tag/ct).
  static bool looksLikeEnvelope(dynamic data) {
    if (data is! Map) return false;
    final v = data['v'];
    return v == envelopeVersion &&
        data['iv'] is String &&
        data['tag'] is String &&
        data['ct'] is String;
  }

  static List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}
