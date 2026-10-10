import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'payload_crypto.dart';
import '../utils/app_toast.dart';
import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import '../widgets/upgrade_dialog.dart';
import '../widgets/maintenance_gate.dart' show MaintenanceGate;
import '../models/chat_media.dart';
import '../models/gif.dart';
import '../models/task_attachment.dart';

final String _apiBaseUrl = dotenv.env['EXPO_PUBLIC_API_BASE_URL'] ?? 'https://api.metricorex.com/api';

/// Absolute origin of the API (scheme + host, without the /api suffix) — used
/// to resolve RELATIVE media URLs (`/uploads/xyz.m4a`) returned by the local
/// upload fallback in POST /chat/media.
final String _apiOrigin = _apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');

/// Origin of the WEB app, derived from the API origin by stripping the
/// `api.` host prefix (api.metricorex.com -> metricorex.com). Local/dev
/// origins without the prefix pass through unchanged. Used as the default
/// `redirect_url` for wallet funding so provider callbacks land on the
/// web app's /payment/callback route (mobile verifies via the reference API).
String get webAppOrigin {
  final uri = Uri.tryParse(_apiOrigin);
  if (uri == null || !uri.hasScheme) return 'https://metricorex.com';
  final host = uri.host;
  final webHost = host.startsWith('api.') ? host.substring(4) : host;
  return '${uri.scheme}://$webHost${uri.hasPort ? ':${uri.port}' : ''}';
}

/// Base URL of the API (…/api). Exported for the app-update checker
/// (AppUpdateService), which calls the unauthenticated
/// /public/app-updates/check endpoint through its own short-timeout Dio
/// instance instead of ApiService's auth/plan-gate interceptors.
String get apiBaseUrl => _apiBaseUrl;

// Global key to access navigator context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void Function()? logoutHandler;

void setLogoutHandler(void Function() handler) {
  logoutHandler = handler;
}

void showSessionExpiredModal() {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Session Expired'),
      content: const Text('Your session has expired. Please log in again to continue.'),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (logoutHandler != null) {
              logoutHandler!();
            }
          },
          child: const Text('Log In'),
        ),
      ],
    ),
  );
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _initializeDio();
  }

  /// Matches the backend plan gate (server/middleware/auth.ts):
  /// 403 { success:false, code:"PLAN_UPGRADE_REQUIRED", error:"Kindly upgrade your plan..." }
  static bool _isPlanUpgradeFailure(dynamic data) {
    if (data is! Map) return false;
    if (data['code'] == 'PLAN_UPGRADE_REQUIRED') return true;
    final error = data['error'];
    return error is String && error.toLowerCase().contains('upgrade your plan');
  }

  late final Dio _dio;
  final StorageService _storage = StorageService();

  /// Read-only access to the session storage (source of truth for the auth
  /// token) — used by SocketService to re-handshake with a fresh token after
  /// the server rejects an expired one.
  StorageService get storage => _storage;

  static String? extractResponseMessage(dynamic data) {
    if (data is Map) {
      final message = data['message'] ?? data['error'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message != null) return message.toString();
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return null;
  }

  static String extractErrorMessage(dynamic error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      // Proxy body-size limit (nginx client_max_body_size): the request never
      // reached the API, so there is no JSON error message to extract.
      if (status == 413) {
        return 'File too large for the server (upload limit). Try a smaller file.';
      }
      final responseData = error.response?.data;
      final msg = extractResponseMessage(responseData);
      if (msg != null) return msg;
    }
    final msg = extractResponseMessage(error);
    if (msg != null) return msg;
    return 'Something went wrong';
  }

  /// Re-entrancy guard: a session-expired 403 can arrive DURING the logout
  /// flow itself (logout best-effort unregisters the FCM token; that DELETE
  /// also 403s with "Invalid or expired token" and would call this handler
  /// again -> logout() again -> infinite recursion). One flag breaks it.
  static bool _handlingSessionExpiry = false;

  Future<void> _handleSessionExpired() async {
    if (_handlingSessionExpiry) return;
    _handlingSessionExpiry = true;
    try {
      // Session expiry logs the user out but must NEVER touch the biometric
      // enrollment: the `biometricsEnabled` flag and the per-device token stay
      // on the device so the next password/Google sign-in silently re-enrolls.
      // Enrollment is revoked ONLY by an explicit user action
      // (Settings → disable biometrics → logout(disableBiometrics: true)).
      if (authNotifierInstance != null) {
        try {
          await authNotifierInstance!.logout();
        } catch (_) {
          // logout() must never throw inside an interceptor — the storage
          // cleanup below is the safety net and runs regardless.
        }
      }
      // ALWAYS clear the session material ourselves, not just in the fallback
      // branch. HISTORY: when the notifier wasn't ready (early-boot 403s from
      // the notifications provider) only SharedPreferences were cleaned while
      // the SECURE-STORAGE token survived — the interceptor kept sending the
      // dead token, every request kept 403ing, and the user was stuck in a
      // "logged-in zombie" state (notifications error, no calls, no chat)
      // until they manually logged out. Clearing both stores guarantees the
      // next boot lands on the login screen.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        await prefs.remove('userId');
        await prefs.remove('businessId');
        await prefs.remove('userName');
      } catch (_) {}
      try {
        await _storage.clearSession();
      } catch (_) {}
    } finally {
      _handlingSessionExpiry = false;
    }
    // Don't show dialog - auth state listener will navigate to login
  }

  void _initializeDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Prefer the secure-storage copy (source of truth), fall back to
        // SharedPreferences for tokens written by older app versions.
        String? token = await _storage.getToken();
        token ??= (await SharedPreferences.getInstance()).getString('token');
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        // E2E PAYLOAD ENCRYPTION (request direction): when the key is
        // configured, JSON map bodies travel as { v, iv, tag, ct } envelopes
        // with the `x-mfv-enc: 1` header so the network tab never shows raw
        // payloads. FormData (multipart uploads) passes through UNTOUCHED —
        // the backend bypasses encryption for multipart. Any encryption
        // hiccup degrades to plaintext WITHOUT the header (the server
        // accepts both), so a crypto failure can never block a request.
        if (PayloadCrypto.isEnabled &&
            options.data is Map &&
            options.data is! FormData) {
          // Keep the plaintext body around: if the server turns out to be
          // deployed WITHOUT PAYLOAD_ENCRYPTION_KEY it answers 400
          // DECRYPT_FAILED and the onError handler below retries once in
          // plaintext instead of failing the call.
          options.extra['mfvPlaintext'] = options.data;
          if (options.extra['mfvRetryPlaintext'] == true) {
            // Already a plaintext retry — send as-is, no enc header.
            options.headers.remove(PayloadCrypto.encHeaderName);
            return handler.next(options);
          }
          try {
            final body = Map<String, dynamic>.from(options.data as Map);
            final envelope = await PayloadCrypto.encryptJson(body);
            if (envelope != null) {
              options.data = envelope;
              options.headers[PayloadCrypto.encHeaderName] =
                  PayloadCrypto.encHeaderValue;
            }
          } catch (_) {
            // Plaintext fallback (no header => server treats it as such).
          }
        }

        // Opt in to response encryption on EVERY request — including
        // bodyless GET/DELETE — so balances, chats and profiles are
        // ciphertext on the wire too. The server never decrypts GET bodies;
        // the header is purely the "this client supports encryption" signal.
        if (PayloadCrypto.isEnabled &&
            options.extra['mfvRetryPlaintext'] != true) {
          options.headers[PayloadCrypto.encHeaderName] =
              PayloadCrypto.encHeaderValue;
        }

        options.headers['Content-Type'] = options.data is FormData
            ? Headers.multipartFormDataContentType
            : Headers.jsonContentType;
        return handler.next(options);
      },
      onResponse: (response, handler) async {
        // E2E PAYLOAD ENCRYPTION (response direction): the server wraps EVERY
        // JSON response in an envelope when we opted in. Decrypt it BEFORE
        // any success/failure parsing so the rest of the pipeline (and every
        // caller) keeps seeing plain JSON. Detection is ENVELOPE-SHAPE first
        // (proxies can strip headers) with the header as a tie-breaker — a
        // decrypt failure on a header-confirmed envelope is converted into a
        // normal-shaped business error; a shape-only miss passes through so
        // a coincidental lookalike body is never destroyed.
        if (PayloadCrypto.isEnabled &&
            PayloadCrypto.looksLikeEnvelope(response.data)) {
          final headerConfirmed = response.headers.value(
                PayloadCrypto.encHeaderName,
              ) ==
              PayloadCrypto.encHeaderValue;
          try {
            response.data = await PayloadCrypto.decryptEnvelope(
              Map<String, dynamic>.from(response.data as Map),
            );
          } catch (e) {
            if (!headerConfirmed) {
              // Shape said "maybe", header wasn't there to confirm — leave
              // the body untouched and let normal parsing proceed.
              return handler.next(response);
            }
            return handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: Response<dynamic>(
                requestOptions: response.requestOptions,
                statusCode: response.statusCode,
                // Normal-shaped error body: the error interceptor + callers
                // extract a readable message from it (no auth side effects).
                data: <String, dynamic>{
                  'success': false,
                  'error':
                      'Could not decrypt the server response. Please check your connection and try again.',
                  'code': 'MFV_DECRYPT_FAILED',
                },
              ),
              type: DioExceptionType.badResponse,
              error: e,
            ));
          }
        }

        final data = response.data;
        final isSuccess = data is Map && data['success'] == true;
        final isFailure = data is Map && data['success'] == false;

        // REGRESSION FIX (users logged out "unauthorized" too easily): an
        // HTTP-200 {success:false} envelope is a BUSINESS failure ("Invalid
        // transaction PIN", "OTP expired", "Invalid account number", …) — it
        // must NEVER terminate the session. Real session failures arrive as
        // HTTP 401/403 and are handled in onError below.
        if (isFailure) {
          return handler.next(response);
        }
        
        // Show success toast for non-GET requests if success and message exists
        if (isSuccess && response.requestOptions.method != 'GET' &&
            response.requestOptions.extra['suppressToast'] != true) {
          final successMessage = extractResponseMessage(data);
          if (successMessage != null) {
            AppToast.show(successMessage, type: AppToastType.success);
          }
        }
        
        // Show error toast if success is false (and not token error)
        if (isFailure && response.requestOptions.extra['suppressToast'] != true) {
          // Plan gate: show the upgrade dialog instead of a plain error toast
          if (_isPlanUpgradeFailure(data)) {
            showUpgradeDialog();
            return handler.next(response);
          }
          final errorMessage = extractResponseMessage(data) ?? 'Something went wrong';
          AppToast.show(errorMessage, type: AppToastType.error);
        }
        
        return handler.next(response);
      },
      onError: (error, handler) async {
        // ENCRYPTION MISMATCH FALLBACK: the app encrypted the body but the
        // server was deployed WITHOUT PAYLOAD_ENCRYPTION_KEY — it answers
        // 400 DECRYPT_FAILED. Retry the exact request once in plaintext so
        // a half-configured deployment degrades instead of breaking every
        // JSON POST from a build that ships with the key.
        final mismatchResponse = error.response;
        if (mismatchResponse != null &&
            mismatchResponse.statusCode == 400 &&
            error.requestOptions.headers[PayloadCrypto.encHeaderName] ==
                PayloadCrypto.encHeaderValue &&
            error.requestOptions.extra['mfvRetryPlaintext'] != true &&
            error.requestOptions.extra['mfvPlaintext'] != null &&
            mismatchResponse.data is Map &&
            (mismatchResponse.data as Map)['code'] == 'DECRYPT_FAILED') {
          try {
            final ro = error.requestOptions;
            final retry = RequestOptions(
              path: ro.path,
              baseUrl: ro.baseUrl,
              method: ro.method,
              data: ro.extra['mfvPlaintext'],
              queryParameters: ro.queryParameters,
              headers: Map<String, dynamic>.from(ro.headers)
                ..remove(PayloadCrypto.encHeaderName),
              extra: Map<String, dynamic>.from(ro.extra)
                ..['mfvRetryPlaintext'] = true,
              contentType: Headers.jsonContentType,
              responseType: ro.responseType,
            );
            final res = await _dio.fetch(retry);
            return handler.resolve(res);
          } catch (e) {
            // Retry failed — fall through with the original error.
          }
        }

        // E2E PAYLOAD ENCRYPTION (error direction): error responses (4xx/5xx)
        // are wrapped in the same envelope. Decrypt error.response.data
        // FIRST so the maintenance gate, the session-expiry logic and the
        // toasts below all see the REAL error message instead of ciphertext.
        // A failed decrypt keeps the original error — the existing handling
        // then just shows a generic message; the session is never touched by
        // the decrypt failure itself.
        final errResponse = error.response;
        if (errResponse != null &&
            PayloadCrypto.isEnabled &&
            PayloadCrypto.looksLikeEnvelope(errResponse.data)) {
          try {
            errResponse.data = await PayloadCrypto.decryptEnvelope(
              Map<String, dynamic>.from(errResponse.data as Map),
            );
          } catch (_) {
            // Leave the undecryptable envelope in place; the generic error
            // path below handles it without auth side effects.
          }
        }

        // MAINTENANCE GATE (web parity): the backend answers 503 with
        // code "MAINTENANCE_MODE" when an admin has maintenance mode ON —
        // most importantly on POST /auth/login. Flip the global gate so the
        // full-screen maintenance screen covers the app immediately.
        if (error.response?.statusCode == 503) {
          final errData = error.response?.data;
          final code = (errData is Map
                  ? (errData['code'] ?? errData['data']?['code'])
                  : null)
              ?.toString()
              .toUpperCase();
          final errText = extractResponseMessage(errData)?.toLowerCase() ?? '';
          if (code == 'MAINTENANCE_MODE' ||
              errText.contains('maintenance')) {
            MaintenanceGate.setOn();
            return handler.next(error);
          }
        }

        final message = extractResponseMessage(error.response?.data) ?? 'Something went wrong';
        final errorData = error.response?.data;
        final isPlanUpgradeError = _isPlanUpgradeFailure(errorData);

        // Plan gate: always present the upgrade modal (with CTA to the
        // subscription screen) instead of a generic error toast.
        if (isPlanUpgradeError) {
          showUpgradeDialog();
          return handler.next(error);
        }

        // Only logout for ACTUAL session failures. The backend's real
        // session errors are exactly: 401 "Access token required" and 403
        // "Invalid or expired token". Matching bare 'invalid'/'expired'
        // here also matched business errors ("Invalid OTP", "OTP expired",
        // "Invalid account number") and logged users out mid-flow — the
        // "user gets unauthorized easily" regression. Match on the token
        // keyword (plus a plain 401) instead.
        if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
          // PER-REQUEST OPT-OUT: endpoints that legitimately answer 401 as a
          // BUSINESS signal (GET /roles/me for personal accounts with no
          // business workspace) set
          // Options(extra: {'suppressSessionLogout': true}) — they must
          // never terminate the session.
          final suppressSessionLogout =
              error.requestOptions.extra['suppressSessionLogout'] == true;
          if (!isPlanUpgradeError && !suppressSessionLogout) {
            final errorMsg = (errorData is Map ? errorData['error'] : null)?.toString().toLowerCase() ?? '';
            final isSessionError = error.response?.statusCode == 401 ||
                errorMsg.contains('token') ||
                errorMsg.contains('unauthorized');
            if (isSessionError) {
              await _handleSessionExpired();
              return handler.next(error);
            }
          }
        }

        // Show error toast, except for plan upgrade errors which are handled specially
        if (!isPlanUpgradeError && (error.requestOptions.method != 'GET' ||
            (error.response?.statusCode != 401 && error.response?.statusCode != 403))) {
          if (error.requestOptions.extra['suppressToast'] == true) {
            return handler.next(error);
          }
          AppToast.show(message, type: AppToastType.error);
        }

        return handler.next(error);
      },
    ));
  }

  // Auth API
  Future<Response> register(Map<String, dynamic> data) async {
    return await _dio.post('/auth/register', data: data);
  }

  Future<Response> login(String email, String password) async {
    try {
      return await _dio.post('/auth/login', data: {'email': email, 'password': password});
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['code'] == 'GOOGLE_ACCOUNT_NO_PASSWORD') {
        // SSO-only account tried password login — point them at the Google
        // button instead of showing the raw backend error.
        throw Exception('This account uses Google Sign-In. Please continue with Google.');
      }
      rethrow;
    }
  }

  /// Google Sign-In: exchanges a Google ID token for an app session.
  /// Response shape mirrors /auth/login: token, userId, businessId,
  /// isNewUser, requiresPasswordSetup and user { id, name, email, avatarUrl,
  /// authProvider, hasPassword }.
  Future<Response> googleAuth(String credential) async {
    return await _dio.post('/auth/google', data: {'credential': credential});
  }

  /// Sets an initial password for SSO (Google) accounts that don't have one.
  /// Backend error code PASSWORD_ALREADY_SET when a password already exists.
  Future<Response> setPassword(String password) async {
    return await _dio.post(
      '/auth/set-password',
      data: {'password': password},
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// Changes the password for accounts that already have one.
  /// Backend error code NO_PASSWORD_SET when no password exists yet.
  Future<Response> changePassword(String currentPassword, String newPassword) async {
    return await _dio.post(
      '/auth/change-password',
      data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// Current authenticated user profile. Returns
  /// { success, data: { id, businessId, email, name, role, avatarUrl,
  /// authProvider, hasPassword, emailVerified, kycStatus, phoneNumber } }.
  Future<Response> getMe() async {
    return await _dio.get('/auth/me', options: Options(extra: {'suppressToast': true}));
  }

  /// Multi-workspace switching — every VERIFIED, ACTIVE membership that
  /// shares the caller's email. Returns
  /// { success, data: { workspaces: [ { userId, businessId, businessName,
  /// businessLogo, workspaceCode, role, isCurrent } ], canSwitch } }.
  Future<Response> listWorkspaces() async {
    return await _dio.get('/auth/workspaces');
  }

  /// Switch into another workspace this email belongs to. Returns the same
  /// payload shape as [login] (token/userId/businessId/name/...) so the
  /// caller can swap the whole session atomically.
  Future<Response> switchWorkspace(String businessId) async {
    return await _dio.post('/auth/switch-workspace', data: {'businessId': businessId});
  }

  // ===================== Chat status (24h stories) =====================

  /// Active statuses for the caller's workspace (+ viewer context).
  /// Returns the raw `data.statuses` list of maps.
  Future<List<Map<String, dynamic>>> listStatuses() async {
    final response = await _dio.get('/statuses');
    final data = response.data is Map ? response.data['data'] : null;
    final statuses = data is Map && data['statuses'] is List ? data['statuses'] as List : const [];
    return statuses.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Post a status (text card and/or image). [backgroundColor] must be one
  /// of the palette colours the backend accepts (unknown colours fall back
  /// server-side). Returns the created row (id/createdAt/expiresAt).
  Future<Map<String, dynamic>?> createStatus({
    String? content,
    String? mediaUrl,
    String? mediaType,
    required String backgroundColor,
  }) async {
    final response = await _dio.post('/statuses', data: {
      if (content != null && content.trim().isNotEmpty) 'content': content.trim(),
      if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
      if (mediaType != null && mediaType.isNotEmpty) 'mediaType': mediaType,
      'backgroundColor': backgroundColor,
    });
    final data = response.data is Map ? response.data['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// Record a view (idempotent server-side). Returns the response whose
  /// `data.data.viewsCount` is the fresh view total.
  Future<Response> viewStatus(String statusId) async {
    return await _dio.post('/statuses/$statusId/view');
  }

  /// Toggle a like. Returns { liked, likesCount }.
  Future<Map<String, dynamic>?> likeStatus(String statusId) async {
    final response = await _dio.post('/statuses/$statusId/like');
    final data = response.data is Map ? response.data['data'] : null;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// Repost a status to your own rail (attributed).
  Future<void> repostStatus(String statusId) async {
    await _dio.post('/statuses/$statusId/repost');
  }

  /// Delete your own status.
  Future<void> deleteStatus(String statusId) async {
    await _dio.delete('/statuses/$statusId');
  }

  /// Result codes for a server-side session validation (GET /auth/me):
  /// [sessionValid] alive, [sessionExpired] server rejected the token
  /// (caller clears the session and lands on login), [sessionUnknown]
  /// network/5xx hiccup — callers must fail open.
  static const int sessionValid = 0;
  static const int sessionExpired = 1;
  static const int sessionUnknown = 2;

  /// Validates the stored session against the server WITHOUT side effects.
  /// Used by AuthNotifier.checkAuth so a dead session (server cleaned up the
  /// user_sessions row after idle expiry) is detected at boot instead of
  /// leaving the app in an authenticated-looking state where every request
  /// 403s, sockets run as guest (no calls/chat) and push never registers.
  /// Returns [sessionValid] / [sessionExpired] / [sessionUnknown].
  Future<int> validateSession() async {
    try {
      final response = await _dio.get('/auth/me', options: Options(extra: {'suppressToast': true}));
      final data = response.data;
      if (data is Map && data['success'] == true) return sessionValid;
      // 200 but unexpected body — treat as unknown (fail open).
      return sessionUnknown;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) return sessionExpired;
      // Network/timeout/5xx — cannot judge, fail open.
      return sessionUnknown;
    } catch (_) {
      return sessionUnknown;
    }
  }

  Future<Response> verifyOtp(String email, String otpCode) async {
    return await _dio.post('/auth/verify-otp', data: {'email': email, 'otpCode': otpCode});
  }

  Future<Response> resendOtp(String email) async {
    return await _dio.post('/auth/resend-otp', data: {'email': email});
  }

  Future<Response> forgotPassword(String email) async {
    return await _dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<Response> verifyResetOtp(String email, String otpCode) async {
    return await _dio.post('/auth/verify-reset-otp', data: {'email': email, 'otpCode': otpCode});
  }

  Future<Response> resetPassword(String email, String otpCode, String newPassword) async {
    return await _dio.post('/auth/reset-password', data: {
      'email': email,
      'otpCode': otpCode,
      'newPassword': newPassword,
    });
  }

  // Tasks API
  Future<Response> getTasks({Map<String, dynamic>? params}) async {
    return await _dio.get('/tasks', queryParameters: params);
  }

  Future<Response> createTask(Map<String, dynamic> data) async {
    return await _dio.post('/tasks', data: data);
  }

  Future<Response> createBulkTasks(List<dynamic> tasks) async {
    return await _dio.post('/tasks/bulk', data: {'tasks': tasks});
  }

  Future<Response> bulkUpdateTasks(Map<String, dynamic> data) async {
    return await _dio.patch('/tasks/bulk', data: data);
  }

  Future<Response> deleteTask(String id) async {
    return await _dio.delete('/tasks/$id');
  }

  Future<Response> updateTask(String id, Map<String, dynamic> data) async {
    return await _dio.put('/tasks/$id', data: data);
  }

  Future<Response> bulkDeleteTasks(List<String> taskIds) async {
    return await _dio.delete('/tasks', data: {'taskIds': taskIds});
  }

  // Task attachments API (server: requires the 'manage_tasks' feature
  // permission for uploads/deletes; up to 10 files, 50MB each per request).

  /// GET /tasks/:id/attachments ->
  /// `{ success, data: { attachments: [TaskAttachment] } }`.
  Future<Response> getTaskAttachments(String taskId) async {
    return await _dio.get('/tasks/$taskId/attachments',
        options: Options(extra: {'suppressToast': true}));
  }

  /// POST /tasks/:id/attachments — multipart with an array field named
  /// `files`. Returns the created TaskAttachment objects. Toasts are
  /// suppressed so callers can drive their own progress feedback and handle
  /// 403 (missing 'manage_tasks') with a friendly message.
  Future<List<TaskAttachment>> uploadTaskAttachments(
    String taskId,
    List<File> files, {
    void Function(int completed, int total)? onFileProgress,
  }) async {
    final List<TaskAttachment> uploaded = [];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap(<String, dynamic>{
        'files': [await MultipartFile.fromFile(file.path, filename: fileName)],
      });
      final response = await _dio.post('/tasks/$taskId/attachments',
          data: formData,
          options: Options(extra: {'suppressToast': true}));
      final data = response.data is Map ? response.data['data'] : null;
      final list = data is Map ? data['attachments'] : null;
      if (list is List) {
        uploaded.addAll(list
            .whereType<Map>()
            .map((a) =>
                TaskAttachment.fromJson(Map<String, dynamic>.from(a)))
            .toList());
      }
      onFileProgress?.call(i + 1, files.length);
    }
    return uploaded;
  }

  /// DELETE /tasks/attachments/:attachmentId -> `{ success }`.
  Future<Response> deleteTaskAttachment(String attachmentId) async {
    return await _dio.delete('/tasks/attachments/$attachmentId',
        options: Options(extra: {'suppressToast': true}));
  }

  /// POST /tasks/:id/attachments with a caller-prepared FormData (the
  /// multipart array field must be named `files`). Throws on failure so
  /// callers can distinguish 403 (missing 'manage_tasks') from network
  /// errors. Toasts suppressed — callers own the progress feedback.
  Future<Response> uploadTaskAttachmentPart(String taskId, FormData formData) async {
    return await _dio.post('/tasks/$taskId/attachments',
        data: formData, options: Options(extra: {'suppressToast': true}));
  }

  Future<Response> getDashboardMetrics({Map<String, dynamic>? params}) async {
    return await _dio.get('/dashboard/metrics', queryParameters: params);
  }

  // Comments API
  Future<Response> getComments(String taskId) async {
    return await _dio.get('/comments/$taskId');
  }

  Future<Response> addComment(Map<String, dynamic> data) async {
    return await _dio.post('/comments', data: data);
  }

  Future<Response> deleteComment(String id) async {
    return await _dio.delete('/comments/$id');
  }

  Future<Response> toggleReaction(String id, String type) async {
    return await _dio.post('/comments/$id/reaction', data: {'type': type}, options: Options(extra: {'suppressToast': true}));
  }

  // Assignments API
  Future<Response> assignTasks(Map<String, dynamic> data) async {
    return await _dio.post('/assignments', data: data);
  }

  Future<Response> getAssignments(String taskId) async {
    return await _dio.get('/assignments/$taskId');
  }

  Future<Response> removeAssignment(String assignmentId) async {
    return await _dio.delete('/assignments/$assignmentId');
  }

  // Epics API
  Future<Response> getEpics() async {
    return await _dio.get('/epics');
  }

  Future<Response> createEpic(Map<String, dynamic> data) async {
    return await _dio.post('/epics', data: data);
  }

  Future<Response> linkTasksToEpic(String epicId, List<String> taskIds) async {
    return await _dio.post('/epics/$epicId/link-tasks', data: {'taskIds': taskIds});
  }

  Future<Response> backfillEpics() async {
    return await _dio.post('/epics/backfill');
  }

  // Team API
  Future<Response> getTeam() async {
    return await _dio.get('/team');
  }

  Future<Response> inviteMember(Map<String, dynamic> data) async {
    return await _dio.post('/team/invite', data: data);
  }

  Future<Response> updateMemberStatus(String id, String status) async {
    return await _dio.patch('/team/$id/status', data: {'status': status});
  }

  Future<Response> updateMemberRole(String id, String role) async {
    return await _dio.patch('/team/$id/role', data: {'role': role});
  }

  /// Assign a custom workspace role (Role Management) to a member.
  Future<Response> updateMemberRoleById(String id, String roleId) async {
    return await _dio.patch('/team/$id/role', data: {'roleId': roleId});
  }

  // Team Roles & Permissions API (mirror of the web app Role Management).
  // suppressSessionLogout: GET /roles/me answers 401 "Unauthorized" for
  // PERSONAL accounts (no business workspace) — that is a business signal,
  // not a dead session, so the error interceptor must not log the user out
  // (and team_roles_screen treats the call as independently optional).
  Future<Response> getRoles() async {
    return await _dio.get(
      '/roles',
      options: Options(extra: {'suppressSessionLogout': true}),
    );
  }

  Future<Response> getRolePermissions() async {
    return await _dio.get(
      '/roles/permissions',
      options: Options(extra: {'suppressSessionLogout': true}),
    );
  }

  Future<Response> getMyTeamRole() async {
    return await _dio.get(
      '/roles/me',
      options: Options(extra: {'suppressSessionLogout': true}),
    );
  }

  Future<Response> createRole(Map<String, dynamic> data) async {
    return await _dio.post('/roles', data: data);
  }

  Future<Response> updateRole(String id, Map<String, dynamic> data) async {
    return await _dio.put('/roles/$id', data: data);
  }

  Future<Response> deleteRole(String id) async {
    return await _dio.delete('/roles/$id');
  }

  Future<Response> deleteMember(String id) async {
    return await _dio.delete('/team/$id');
  }

  Future<Response> getTeamRanking({Map<String, dynamic>? params}) async {
    return await _dio.get('/team/ranking', queryParameters: params);
  }

  Future<Response> getTopTeamMembers() async {
    return await _dio.get('/team/ranking/top');
  }

  Future<Response> verifyTeamInvite(String token) async {
    return await _dio.get('/team/verify-invite/$token');
  }

  Future<Response> acceptTeamInvite(String token, Map<String, dynamic> data) async {
    return await _dio.post('/team/accept-invite/$token', data: data);
  }

  // KYC API
  Future<Response> initiateKyc(String type, String number, {String? otpMethod}) async {
    final Map<String, dynamic> payload = {'type': type, 'number': number};
    if (otpMethod != null) payload['otp_method'] = otpMethod;
    return await _dio.post('/kyc/initiate', data: payload);
  }

  Future<Response> verifyKycOtp(String otp) async {
    return await _dio.post('/kyc/verify-otp', data: {'otp': otp});
  }

  Future<Response> getKycStatus({Options? options}) async {
    return await _dio.get('/kyc/status', options: options);
  }

  Future<Response> submitBusinessKyc(Map<String, dynamic> data, {XFile? proofFile}) async {
    if (proofFile == null) {
      return await _dio.post('/kyc/business', data: data);
    }

    FormData formData = FormData.fromMap(data);
    formData.files.add(MapEntry(
      'proof_of_address',
      await MultipartFile.fromFile(
        proofFile.path,
        filename: proofFile.name,
      ),
    ));

    return await _dio.post('/kyc/business', data: formData);
  }

  // ---- Business KYC upgrade (registration category + transaction limits) ----
  // Server: POST /auth/register accepts an optional businessType
  // ('registered' | 'non_registered'); GET /business-kyc/status reports the
  // current category, pending submission and per-category transaction limits;
  // POST /business-kyc/submit upgrades non-registered businesses to
  // registered via a multipart document submission. All shapes are parsed
  // defensively by callers — the server may null out nested fields.

  /// GET /business-kyc/status (auth) → the unwrapped `data` map:
  /// `{ business, latestSubmission, submissionHistory, limits, canUpgrade }`.
  /// Returns {} on unexpected shapes — callers parse defensively (nulls are
  /// possible). Toasts suppressed — the dashboard polls this best-effort and
  /// must stay silent on failures.
  Future<Map<String, dynamic>> getBusinessKycStatus() async {
    final response = await _dio.get('/business-kyc/status',
        options: Options(extra: {'suppressToast': true}));
    final data = response.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return <String, dynamic>{};
  }

  /// GET /business-kyc/config (no auth) → the unwrapped `data` map:
  /// `{ registrationTypes: [{ id, label, authority, docPack, description,
  /// documents: [{ id, label, description, required }] }], limits: {...} }`.
  Future<Map<String, dynamic>> getBusinessKycConfig() async {
    final response = await _dio.get('/business-kyc/config',
        options: Options(extra: {'suppressToast': true}));
    final data = response.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return <String, dynamic>{};
  }

  /// POST /business-kyc/submit (auth, multipart/form-data) → the unwrapped
  /// response body `{ success, message, data: { submissionId, status } }`.
  ///
  /// NOTE: named …Upgrade because the legacy address-proof
  /// [submitBusinessKyc] (POST /kyc/business) already occupies the name —
  /// Dart has no overloading.
  ///
  /// [documents] items are `{path, kind}` maps; `docKinds` is sent as a
  /// JSON-encoded array aligned BY INDEX with the files posted under the
  /// `documents` field. FormData passes through the crypto interceptor
  /// untouched. Toasts suppressed so the caller owns error codes
  /// (SUBMISSION_PENDING 409, DOCUMENTS_MISSING 400 + data.missing,
  /// FILE_TOO_LARGE, DESCRIPTION_TOO_SHORT, INVALID_REGISTRATION_TYPE).
  Future<Map<String, dynamic>> submitBusinessKycUpgrade({
    required String registrationType,
    required String businessDescription,
    required List<Map<String, String>> documents,
  }) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'registrationType': registrationType,
      'businessDescription': businessDescription,
      'docKinds': jsonEncode(documents.map((d) => d['kind'] ?? '').toList()),
    });
    for (final doc in documents) {
      final path = doc['path'] ?? '';
      if (path.isEmpty) continue;
      final fileName = path.split(Platform.pathSeparator).last;
      formData.files.add(MapEntry(
        'documents',
        await MultipartFile.fromFile(path, filename: fileName),
      ));
    }
    final response = await _dio.post('/business-kyc/submit', data: formData,
        options: Options(extra: {'suppressToast': true}));
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  /// GET /wallet/limits (auth) → the unwrapped `data` map:
  /// `{ category, isRegistered, currency,
  /// limits: {singleTransactionLimit, dailyLimit, monthlyLimit},
  /// usage: {...}, inflow: {usedToday, usedThisMonth, remainingToday,
  /// remainingThisMonth}, registeredLimits: {...}, inflowLimits: {...},
  /// outflowLimits: {...} }` — the funding screen shows these before the
  /// user commits an amount. Returns {} on unexpected shapes — callers
  /// parse defensively (nulls are possible). Toasts suppressed — loaded
  /// best-effort and must stay silent on failures.
  Future<Map<String, dynamic>> getWalletLimits() async {
    final response = await _dio.get('/wallet/limits',
        options: Options(extra: {'suppressToast': true}));
    final data = response.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return <String, dynamic>{};
  }

  // Wallet API
  Future<Response> getWallet() async {
    return await _dio.get('/wallet');
  }

  // ---- Payment Links ("Get Paid" revenue feature) ---------------------------
  Future<Response> getPaymentLinks() async {
    return await _dio.get('/payment-links');
  }

  Future<Response> createPaymentLink(Map<String, dynamic> payload) async {
    return await _dio.post('/payment-links', data: payload);
  }

  Future<Response> updatePaymentLink(String id, Map<String, dynamic> payload) async {
    return await _dio.put('/payment-links/$id', data: payload);
  }

  Future<Response> deletePaymentLink(String id) async {
    return await _dio.delete('/payment-links/$id');
  }

  // ---- MetricAi Credit Packs (revenue feature) ------------------------------
  Future<Response> getAiCreditPacks() async {
    return await _dio.get('/ai-credits/packs');
  }

  Future<Response> purchaseAiCreditPack(String packId, {String? walletId}) async {
    return await _dio.post('/ai-credits/purchase', data: {
      'pack_id': packId,
      if (walletId != null) 'wallet_id': walletId,
    });
  }

  Future<Response> getAiCreditPurchases() async {
    return await _dio.get('/ai-credits/purchases');
  }

  // ---- Smart Invoices ("Get Paid" revenue feature) --------------------------
  Future<Response> getInvoices() async {
    return await _dio.get('/invoices');
  }

  Future<Response> createInvoice(Map<String, dynamic> payload) async {
    return await _dio.post('/invoices', data: payload);
  }

  Future<Response> updateInvoice(String id, Map<String, dynamic> payload) async {
    return await _dio.put('/invoices/$id', data: payload);
  }

  Future<Response> cancelInvoice(String id) async {
    return await _dio.post('/invoices/$id/cancel');
  }

  Future<Response> deleteInvoice(String id) async {
    return await _dio.delete('/invoices/$id');
  }

  // ---- Storefront (Metroflow Store — business revenue feature) --------------
  Future<Response> getStoreProducts() async {
    return await _dio.get('/store/products');
  }

  Future<Response> createStoreProduct(Map<String, dynamic> payload) async {
    return await _dio.post('/store/products', data: payload);
  }

  Future<Response> updateStoreProduct(String id, Map<String, dynamic> payload) async {
    return await _dio.put('/store/products/$id', data: payload);
  }

  Future<Response> deleteStoreProduct(String id) async {
    return await _dio.delete('/store/products/$id');
  }

  Future<Response> getStoreOrders() async {
    return await _dio.get('/store/orders');
  }

  Future<Response> fulfilStoreOrder(String id) async {
    return await _dio.post('/store/orders/$id/fulfil');
  }

  Future<Response> cancelStoreOrder(String id) async {
    return await _dio.post('/store/orders/$id/cancel');
  }

  // ---- Recurring Billing (customer subscriptions — business revenue feature)
  // NOTE: named getRecurring* — getSubscriptionPlans() already exists below
  // for the PLATFORM plan purchase flow (/subscription/plans). Two methods
  // with the same name in one class is a Dart compile error.
  Future<Response> getRecurringPlans() async {
    return await _dio.get('/recurring/plans');
  }

  Future<Response> createSubscriptionPlan(Map<String, dynamic> payload) async {
    return await _dio.post('/recurring/plans', data: payload);
  }

  Future<Response> updateSubscriptionPlan(String id, Map<String, dynamic> payload) async {
    return await _dio.put('/recurring/plans/$id', data: payload);
  }

  Future<Response> deleteSubscriptionPlan(String id) async {
    return await _dio.delete('/recurring/plans/$id');
  }

  Future<Response> getSubscribers() async {
    return await _dio.get('/recurring/subscribers');
  }

  Future<Response> addSubscriber(Map<String, dynamic> payload) async {
    return await _dio.post('/recurring/subscribers', data: payload);
  }

  Future<Response> cancelSubscriber(String id) async {
    return await _dio.delete('/recurring/subscribers/$id');
  }

  Future<Response> reactivateSubscriber(String id) async {
    return await _dio.post('/recurring/subscribers/$id/reactivate');
  }

  Future<Response> getRecurringCharges() async {
    return await _dio.get('/recurring/charges');
  }


  /// POST /wallet/fund/card. The backend resolves the active payment provider
  /// itself — the client MUST NOT send a `provider` field (it 400s for
  /// unsupported names and fights the admin-configured active provider).
  ///
  /// [suppressToast] lets the caller own the error UI — the funding screen
  /// passes true so a 403 *LIMIT_EXCEEDED rejection renders as a dedicated
  /// "Transaction limit reached" sheet instead of the interceptor's generic
  /// toast (all error cases must then be handled in the caller's catch).
  Future<Response> fundWallet(double amount, String walletId,
      {String? redirectUrl, bool suppressToast = false}) async {
    final data = <String, dynamic>{
      'amount': amount,
      'wallet_id': walletId,
    };
    if (redirectUrl != null) {
      data['redirect_url'] = redirectUrl;
    }
    return await _dio.post('/wallet/fund/card', data: data,
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// Fetch available payment providers and the globally active one.
  /// Response: { success, data: { providers: [...], activeProvider, defaultProvider, configStatus } }
  Future<Response> getPaymentProviders() async {
    return await _dio.get('/providers/list', options: Options(extra: {'suppressToast': true}));
  }

  Future<Response> verifyWalletFunding(String reference) async {
    return await verifyWalletPayment(reference);
  }

  Future<Response> createVirtualAccount(String accountType) async {
    return await _dio.post('/wallet/create-virtual-account', data: {
      'accountType': accountType,
    });
  }

  Future<Response> verifyWalletPayment(String reference, {bool suppressToast = false}) async {
    // POST /subscription/verify-payment handles wallet-funding references too:
    // it verifies with the provider, atomically credits the wallet and returns
    // JSON. (GET /wallet/verify returns HTML meant for browser redirects.)
    return await _dio.post(
      '/subscription/verify-payment',
      data: {'reference': reference},
      options: Options(extra: {'suppressToast': suppressToast}),
    );
  }

  // Transfers API
  Future<Response> getBanks() async {
    return await _dio.get('/transfers/banks');
  }

  /// International address autocomplete — rides the backend
  /// /geo/address-suggest proxy (OpenStreetMap Nominatim). Going through the
  /// backend keeps web and mobile on ONE provider/UA identity: Nominatim's
  /// edge 503s generic browser UAs, and mobile app stores also discourage
  /// third-party direct calls. Beneficiaries screen falls back to a direct
  /// Nominatim query if this endpoint is unreachable.
  Future<Response> getAddressSuggestions(String query, String countryCode,
      {bool suppressToast = true}) async {
    return await _dio.get('/geo/address-suggest', queryParameters: {
      'q': query,
      if (countryCode.trim().isNotEmpty) 'cc': countryCode.trim().toLowerCase(),
    }, options: Options(extra: {'suppressToast': suppressToast}));
  }


  Future<Response> resolveAccount(String bankCode, String accountNumber, {bool suppressToast = false}) async {
    return await _dio.post('/transfers/account-lookup', data: {
      'bank_code': bankCode,
      'account_number': accountNumber,
    }, options: Options(extra: {'suppressToast': suppressToast}));
  }

  Future<Response> lookupTransferAccount(String bankCode, String accountNumber, {bool suppressToast = false}) async {
    return await _dio.post('/transfers/lookup', data: {
      'bank_code': bankCode,
      'account_number': accountNumber,
    }, options: Options(extra: {'suppressToast': suppressToast}));
  }

  Future<Response> requestTransferOtp({String? walletId, String? otpMethod}) async {
    final Map<String, dynamic> payload = {};
    if (walletId != null) payload['wallet_id'] = walletId;
    if (otpMethod != null) payload['otp_method'] = otpMethod;
    return await _dio.post('/transfers/otp/request', data: payload);
  }

  Future<Response> singleTransfer(Map<String, dynamic> data, {bool suppressToast = true}) async {
    return await _dio.post('/transfers/single', data: _normalizeTransferPayload(data), options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// Ensures the /transfers/single payload uses the camelCase keys the
  /// backend Zod schema expects, while keeping snake_case keys working.
  Map<String, dynamic> _normalizeTransferPayload(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    const keyMap = {
      'bank_code': 'bankCode',
      'account_number': 'accountNumber',
      'account_name': 'accountName',
      'wallet_id': 'walletId',
    };
    keyMap.forEach((snake, camel) {
      if (normalized.containsKey(snake)) {
        normalized[camel] ??= normalized[snake];
      }
    });
    return normalized;
  }

  Future<Response> bulkTransfer(Map<String, dynamic> data, {bool suppressToast = true}) async {
    return await _dio.post('/transfers/bulk', data: data, options: Options(extra: {'suppressToast': suppressToast}));
  }

  Future<Response> bulkTransferV2(Map<String, dynamic> data, {bool suppressToast = true}) async {
    return await _dio.post('/transfers/bulk', data: data, options: Options(extra: {'suppressToast': suppressToast}));
  }

  Future<Response> getTransfers({Map<String, dynamic>? params}) async {
    return await _dio.get('/transfers', queryParameters: params);
  }

  Future<Response> getTransferQueue({Map<String, dynamic>? params}) async {
    return await _dio.get('/transfers', queryParameters: params);
  }

  Future<Response> exportSubscriptionTransactions({Map<String, dynamic>? params}) async {
    return await _dio.get('/subscription/transactions/export', queryParameters: params);
  }

  Future<Response> retryTransfer(String id) async {
    return await _dio.post('/transfers/$id/retry');
  }

  /// Re-query the provider for the CURRENT status of a transfer (used by the
  /// receipt/success screen so users see the real outcome instantly instead
  /// of a stuck "Processing").
  Future<Response> verifyTransfer(String id) async {
    return await _dio.post('/transfers/$id/verify');
  }

  /// GET /transfers/beneficiaries — recent transfer recipients (chips row).
  /// `currency` filters to one corridor (NGN/USD/GBP/EUR).
  Future<Response> getBeneficiaries({String? currency, int limit = 100}) async {
    return await _dio.get('/transfers/beneficiaries', queryParameters: {
      if (currency != null) 'currency': currency,
      'limit': limit,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// POST /transfers/beneficiaries — save a beneficiary with verification
  /// (NGN resolves the account name; intl corridors are format-validated).
  Future<Response> createBeneficiary(Map<String, dynamic> data) async {
    return await _dio.post('/transfers/beneficiaries', data: data,
        options: Options(extra: {'suppressToast': true}));
  }

  /// PUT /transfers/beneficiaries/:id — edit a saved beneficiary. Changing an
  /// NGN account's bank/number re-resolves it server-side; intl corridors are
  /// re-validated. Returns the updated record with verificationStatus.
  Future<Response> updateBeneficiary(String id, Map<String, dynamic> data) async {
    return await _dio.put('/transfers/beneficiaries/$id', data: data,
        options: Options(extra: {'suppressToast': true}));
  }

  /// POST /transfers/beneficiaries/:id/verify — re-run verification for a
  /// saved beneficiary (NGN provider resolve / intl corridor validation).
  Future<Response> verifyBeneficiary(String id) async {
    return await _dio.post('/transfers/beneficiaries/$id/verify',
        options: Options(extra: {'suppressToast': true}));
  }

  /// GET /transfers/payout-limits — admin-configured min/max per currency.
  Future<Response> getPayoutLimits() async {
    return await _dio.get('/transfers/payout-limits',
        options: Options(extra: {'suppressToast': true}));
  }

  /// POST /calls/push-ack — delivery receipt for an incoming-call push.
  /// Fire-and-forget; cancels the server's visible-tray fallback.
  Future<void> acknowledgeCallPush(String callId) async {
    try {
      await _dio.post('/calls/push-ack', data: {'callId': callId},
          options: Options(extra: {'suppressToast': true}));
    } catch (_) {
      // never fail an ack
    }
  }

  /// DELETE /transfers/beneficiaries/:id — remove a saved recipient.
  Future<Response> deleteBeneficiary(String id) async {
    return await _dio.delete('/transfers/beneficiaries/$id');
  }

  /// POST /transfers/:id/force-reversal — customer-triggered self-heal for a
  /// failed transfer whose money has not come back yet (idempotent).
  Future<Response> forceTransferReversal(String idOrReference) async {
    return await _dio.post('/transfers/$idOrReference/force-reversal');
  }

  /// POST /meetings/:meetingIdOrCode/participants — invite people to a live
  /// meeting (call-room "Add people"). Accepts the meeting UUID OR its code;
  /// the backend emails every newly-added participant/guest.
  Future<Response> addMeetingParticipants(
    String meetingIdOrCode, {
    List<String> participantIds = const [],
    List<String> emails = const [],
  }) async {
    return await _dio.post(
      '/meetings/$meetingIdOrCode/participants',
      data: {'participantIds': participantIds, 'emails': emails},
    );
  }

  /// POST /calls/:callId/participants — invite people to a live call.
  Future<Response> addCallParticipants(
    String callIdOrCode, {
    List<String> participantIds = const [],
    List<String> emails = const [],
  }) async {
    return await _dio.post(
      '/calls/$callIdOrCode/participants',
      data: {'participantIds': participantIds, 'emails': emails},
    );
  }

  /// GET /meetings/:id (accepts UUID or code) — used by the call-room invite
  /// sheet to resolve the shareable meeting code.
  Future<Response> getMeetingDetail(String idOrCode) async {
    return await _dio.get(
      '/meetings/$idOrCode',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// GET /calls/:id (accepts UUID or code) — same as above for calls.
  Future<Response> getCallDetail(String idOrCode) async {
    return await _dio.get(
      '/calls/$idOrCode',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  // ---------------------------------------------------------------------------
  // Transaction disputes
  // ---------------------------------------------------------------------------

  /// POST /disputes — file a dispute against a debit transaction, with an
  /// optional image/PDF attachment sent as multipart/form-data.
  Future<Response> createDispute({
    required String reference,
    required String category,
    required String message,
    String? attachmentPath,
    String? attachmentName,
  }) async {
    if (attachmentPath != null && attachmentPath.isNotEmpty) {
      final fileName =
          (attachmentName != null && attachmentName.isNotEmpty)
              ? attachmentName
              : attachmentPath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap(<String, dynamic>{
        'reference': reference,
        'category': category,
        'message': message,
        'attachment': await MultipartFile.fromFile(attachmentPath,
            filename: fileName),
      });
      return await _dio.post('/disputes', data: formData);
    }
    return await _dio.post('/disputes', data: {
      'reference': reference,
      'category': category,
      'message': message,
    });
  }

  /// GET /disputes/mine — disputes filed by my business.
  Future<Response> getMyDisputes() async {
    return await _dio.get('/disputes/mine');
  }

  // ---------------------------------------------------------------------------
  // SSO profile completion (business name / industry / phone / logo)
  // ---------------------------------------------------------------------------

  /// POST /settings/business/complete — one-call SSO onboarding completion.
  /// [logoPath] is a local image file picked by the user (multipart 'logo').
  Future<Response> completeBusinessProfile({
    required String name,
    required String industry,
    required String phoneNumber,
    String? logoPath,
  }) async {
    if (logoPath != null && logoPath.isNotEmpty) {
      final fileName = logoPath.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap(<String, dynamic>{
        'name': name,
        'industry': industry,
        'phone_number': phoneNumber,
        'logo': await MultipartFile.fromFile(logoPath, filename: fileName),
      });
      return await _dio.post('/settings/business/complete', data: formData);
    }
    return await _dio.post('/settings/business/complete', data: {
      'name': name,
      'industry': industry,
      'phone_number': phoneNumber,
    });
  }

  /// International payout quote (USD payouts funded from an NGN wallet).
  /// GET /transfers/quote?amount=&source_currency=&destination_currency=
  /// Response: { success, data: { live_rate, markup_percent, marked_up_rate,
  /// fee, total_debit (source currency), receiving_amount, ... } }
  Future<Response> getTransferQuote({
    required num amount,
    String sourceCurrency = 'NGN',
    String destinationCurrency = 'USD',
  }) async {
    return await _dio.get('/transfers/quote', queryParameters: {
      'amount': amount,
      'source_currency': sourceCurrency,
      'destination_currency': destinationCurrency,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Payroll employee directory with verification details.
  /// GET /payroll/employees?verification_status=&currency=&search=&page=&limit=
  /// Response: { success, data: [employees], pagination }
  Future<Response> getPayrollEmployees({Map<String, dynamic>? params}) async {
    return await _dio.get('/payroll/employees',
        queryParameters: params, options: Options(extra: {'suppressToast': true}));
  }

  /// Verify a single payroll employee via backend account lookup.
  /// POST /payroll/employees/:id/verify → { success, data: { verification_status, account_name } }
  Future<Response> verifyPayrollEmployee(String id, {bool suppressToast = true}) async {
    return await _dio.post('/payroll/employees/$id/verify',
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// Bulk-verify payroll employees. Empty [employeeIds] (or null) = ALL
  /// pending employees. Response:
  /// { success, data: { total, verified, failed, results: [...] } }
  Future<Response> verifyPayrollEmployeesBulk({List<String>? employeeIds, bool suppressToast = true}) async {
    return await _dio.post('/payroll/employees/verify-bulk', data: {
      if (employeeIds != null && employeeIds.isNotEmpty) 'employee_ids': employeeIds,
    }, options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// Add one or more employees to the payroll directory.
  /// POST /payroll/employees/import { employees: [row] }
  Future<Response> importPayrollEmployees(List<Map<String, dynamic>> employees) async {
    return await _dio.post('/payroll/employees/import', data: {'employees': employees});
  }

  // -------------------------------------------------------------------------
  // Push notifications (FCM device registration)
  // -------------------------------------------------------------------------

  /// Registers this device's FCM token so the backend can deliver pushes.
  /// POST /notifications/register-device (path relative to the /api base —
  /// NOTE the base URL already contains /api, so NO extra /api here).
  Future<Response> registerDevice({
    required String fcmToken,
    required String platform,
    String? deviceName,
    String? appVersion,
  }) async {
    return await _dio.post('/notifications/register-device', data: {
      'fcm_token': fcmToken,
      'platform': platform,
      if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
      if (appVersion != null && appVersion.isNotEmpty) 'app_version': appVersion,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Removes this device's FCM token (logout). DELETE /notifications/register-device
  Future<Response> unregisterDevice({required String fcmToken}) async {
    return await _dio.delete('/notifications/register-device',
        data: {'fcm_token': fcmToken}, options: Options(extra: {'suppressToast': true}));
  }

  // -------------------------------------------------------------------------
  // Biometric unlock (server-backed)
  //
  // POST /auth/biometric/enroll   (auth) { device_id, device_name?, platform? }
  //   -> { success, message, data: { biometric_token, device_id } }
  //   The plaintext biometric_token is ONE-TIME: store it in secure storage.
  // POST /auth/biometric/login    { biometric_token, device_id, device_name? }
  //   -> same envelope as /auth/login: { success, token, userId, businessId }
  // DELETE /auth/biometric/enroll (auth) { device_id? }  -> revokes locally.
  // -------------------------------------------------------------------------

  /// Enables biometric unlock for this device. Requires an authenticated
  /// session (the Authorization header is attached by the interceptor).
  Future<Response> biometricEnroll({
    required String deviceId,
    String? deviceName,
    String? platform,
  }) async {
    return await _dio.post('/auth/biometric/enroll', data: {
      'device_id': deviceId,
      if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Exchanges the stored biometric token for a full session. Public route
  /// (no auth header needed). 401 => the credential was revoked server-side.
  Future<Response> biometricLogin({
    required String biometricToken,
    required String deviceId,
    String? deviceName,
  }) async {
    return await _dio.post('/auth/biometric/login', data: {
      'biometric_token': biometricToken,
      'device_id': deviceId,
      if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Revokes this device's (or all of the user's) biometric credentials.
  Future<Response> biometricRevoke({String? deviceId}) async {
    return await _dio.delete('/auth/biometric/enroll', data: {
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Reports whether THIS device still has a live server-side biometric
  /// enrollment. POST /auth/biometric/status { device_id } →
  /// { success, enrolled }. Used by the login screen to detect a stale
  /// per-device token BEFORE prompting (the endpoint is additive: old
  /// backends 404 — callers must treat errors as soft-success).
  Future<Response> biometricStatus(String deviceId) async {
    return await _dio.post('/auth/biometric/status', data: {
      'device_id': deviceId,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Deep-defensive account-name extraction for bank account lookups.
  ///
  /// The backend wraps provider responses in multiple layers:
  ///   { success, data: { status: 'success', data: { account_name, account_number } } }
  /// but older providers return flattened or camelCase shapes:
  ///   { success, data: { account_name } }
  ///   { success, data: { responseBody: { accountName } } }
  /// This helper walks every known shape and returns null when nothing fits.
  static String? extractAccountName(dynamic payload) {
    dynamic probe(dynamic node) {
      if (node is! Map) return null;
      // Prefer the snake_case key, then the camelCase twin.
      final direct = node['account_name'] ?? node['accountName'];
      if (direct is String && direct.trim().isNotEmpty) return direct.trim();
      return null;
    }

    // payload === the axios response body: { success, data: {...} }
    dynamic data = payload is Map ? payload['data'] : null;
    // 1. data.data.account_name (current backend contract)
    final name = probe(data is Map ? data['data'] : null);
    if (name != null) return name;
    // 2. data.account_name (flattened)
    final flat = probe(data);
    if (flat != null) return flat;
    // 3. data.responseBody.accountName (legacy provider passthrough)
    final legacy = probe(data is Map ? data['responseBody'] : null);
    if (legacy != null) return legacy;
    // 4. top-level account_name (already-unwrapped callers)
    return probe(payload);
  }

  // Payroll API
  Future<Response> getPayrollSummary({Map<String, dynamic>? params}) async {
    return await _dio.get('/payroll/summary', queryParameters: params);
  }

  Future<Response> getPayrollConfig() async {
    return await _dio.get('/payroll/config');
  }

  Future<Response> updatePayrollConfig(Map<String, dynamic> data) async {
    return await _dio.put('/payroll/config', data: data);
  }

  Future<Response> updatePayrollUser(String id, Map<String, dynamic> data) async {
    return await _dio.put('/payroll/user/$id', data: data);
  }

  Future<Response> addPayrollAdjustment(Map<String, dynamic> data) async {
    return await _dio.post('/payroll/adjustments', data: data);
  }

  Future<Response> getPayrollAdjustments({String? userId}) async {
    return await _dio.get(
      '/payroll/adjustments',
      queryParameters: userId != null ? {'userId': userId} : null,
    );
  }

  Future<Response> deletePayrollAdjustment(String id) async {
    return await _dio.delete('/payroll/adjustments/$id');
  }

  // Subscription API
  Future<Response> getCurrentSubscription() async {
    return await _dio.get('/subscription/current');
  }

  Future<Response> getSubscriptionPlans() async {
    return await _dio.get('/subscription/plans');
  }

  Future<Response> getSubscriptionCards() async {
    return await _dio.get('/subscription/cards');
  }

  Future<Response> initiateSubscriptionPayment(String planId, String currency) async {
    return await _dio.post('/subscription/initiate-payment', data: {
      'planId': planId,
      'currency': currency,
    });
  }

  Future<Response> verifySubscriptionPayment(String reference) async {
    return await _dio.post('/subscription/verify-payment', data: {'reference': reference});
  }

  Future<Response> cancelSubscription() async {
    return await _dio.post('/subscription/cancel');
  }

  Future<Response> downgradeSubscription() async {
    return await _dio.post('/subscription/downgrade');
  }

  Future<Response> addSubscriptionCard() async {
    return await _dio.post('/subscription/cards/initiate');
  }

  Future<Response> removeSubscriptionCard(String id) async {
    return await _dio.delete('/subscription/cards/$id');
  }

  Future<Response> setActiveSubscriptionCard(String id) async {
    return await _dio.put('/subscription/cards/$id/active');
  }

  Future<Response> getSubscriptionTransactions({Map<String, dynamic>? params}) async {
    return await _dio.get('/subscription/transactions', queryParameters: params);
  }

  // Settings API
  Future<Response> getSettings() async {
    return await _dio.get('/settings');
  }

  Future<Response> updateSettings(Map<String, dynamic> data) async {
    return await _dio.put('/settings', data: data);
  }

  Future<Response> requestContactUpdateOtp(String type, String value) async {
    return await _dio.post('/settings/update-contact/request-otp', data: {
      'type': type,
      'value': value,
    });
  }

  Future<Response> verifyContactUpdateOtp(String otp) async {
    return await _dio.post('/settings/update-contact/verify-otp', data: {'otp': otp});
  }

  Future<Response> getOtpPreference() async {
    return await _dio.get('/settings/otp-preference');
  }

  Future<Response> updateOtpPreference(String preference) async {
    return await _dio.put('/settings/otp-preference', data: {'preference': preference});
  }

  Future<Response> getOtpEnabled() async {
    return await _dio.get('/settings/otp-enabled');
  }

  /// Request the OTP that authorizes flipping the OTP-for-transactions
  /// setting (the PUT below is rejected without it).
  Future<Response> sendOtpToggleOtp() async {
    return await _dio.post('/settings/otp-enabled/send-otp');
  }

  Future<Response> updateOtpEnabled(bool enabled, {String? otp}) async {
    return await _dio.put('/settings/otp-enabled', data: {
      'enabled': enabled,
      if (otp != null) 'otp': otp,
    });
  }

  Future<Response> createPin(String pin) async {
    return await _dio.post('/settings/pin', data: {'pin': pin});
  }

  Future<Response> sendPinUpdateOtp() async {
    return await _dio.post('/settings/pin/send-otp');
  }

  Future<Response> updatePin(String newPin, String otp) async {
    return await _dio.put('/settings/pin', data: {'newPin': newPin, 'otp': otp});
  }

  Future<Response> getFees() async {
    return await _dio.get('/fees');
  }

  // Activity Logs API
  Future<Response> getActivityLogs({int page = 1, int limit = 10}) async {
    return await _dio.get('/activity-logs', queryParameters: {
      'page': page,
      'limit': limit,
    });
  }

  // Ideas API
  Future<Response> getIdeas() async {
    return await _dio.get('/ideas');
  }

  Future<Response> createIdea(Map<String, dynamic> data) async {
    return await _dio.post('/ideas', data: data);
  }

  Future<Response> updateIdea(String id, Map<String, dynamic> data) async {
    return await _dio.put('/ideas/$id', data: data);
  }

  Future<Response> updateIdeaStatus(String id, String status) async {
    return await _dio.put('/ideas/$id/status', data: {'status': status});
  }

  Future<Response> deleteIdea(String id) async {
    return await _dio.delete('/ideas/$id');
  }

  Future<Response> generateDocumentation(String ideaId) async {
    return await _dio.post('/ideas/$ideaId/documentation');
  }

  Future<Response> getDocumentation(String ideaId) async {
    return await _dio.get('/ideas/$ideaId/documentation');
  }

  Future<Response> updateDocumentation(String id, Map<String, dynamic> data) async {
    return await _dio.put('/product-documentation/$id', data: data);
  }

  Future<Response> deleteDocumentation(String id) async {
    return await _dio.delete('/product-documentation/$id');
  }

  Future<Response> regenerateDocumentation(String id, String areasOfConcern) async {
    return await _dio.post('/product-documentation/$id/regenerate', data: {
      'areasOfConcern': areasOfConcern,
    });
  }

  Future<Response> getDocumentationPdf(String id) async {
    return await _dio.get(
      '/product-documentation/$id/pdf',
      options: Options(responseType: ResponseType.bytes, extra: {'suppressToast': true}),
    );
  }

  // Task Statuses API
  Future<Response> getTaskStatuses() async {
    return await _dio.get('/task-statuses');
  }

  // Board API
  Future<Response> getBoard() async {
    return await _dio.get('/board');
  }

  Future<Response> createTaskStatus(Map<String, dynamic> data) async {
    return await _dio.post('/task-statuses', data: data);
  }

  Future<Response> updateTaskStatus(String id, Map<String, dynamic> data) async {
    return await _dio.put('/task-statuses/$id', data: data);
  }

  Future<Response> deleteTaskStatus(String id) async {
    return await _dio.delete('/task-statuses/$id');
  }

  // Meetings API
  Future<Response> getMeetings({int page = 1, int limit = 10, String? from, String? to}) async {
    return await _dio.get('/meetings', queryParameters: {
      'page': page,
      'limit': limit,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
    });
  }

  Future<Response> getMeetingByCode(String code) async {
    return await _dio.get('/meetings/code/$code');
  }

  Future<Response> createMeeting(Map<String, dynamic> data) async {
    return await _dio.post('/meetings', data: data);
  }

  Future<Response> updateMeeting(String id, Map<String, dynamic> data) async {
    return await _dio.put('/meetings/$id', data: data);
  }

  Future<Response> deleteMeeting(String id) async {
    return await _dio.delete('/meetings/$id');
  }

  // Chat API
  Future<Response> getConversations() async {
    return await _dio.get('/chat/conversations');
  }

  Future<Response> createConversation(Map<String, dynamic> data) async {
    return await _dio.post('/chat/conversations', data: data);
  }

  /// GET /chat/conversations/:id/participants — participant roster with roles,
  /// presence and last-seen. Used by the group profile sheet (member rows,
  /// add-members picker source) and the @mention member list.
  Future<Response> getConversationParticipants(String conversationId) async {
    return await _dio.get(
      '/chat/conversations/$conversationId/participants',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// POST /chat/conversations/:id/participants { userIds } — add members to a
  /// GROUP conversation. Backend answers { added: [userId...], conversation }.
  Future<Response> addChatParticipants(
    String conversationId,
    List<String> userIds,
  ) async {
    return await _dio.post(
      '/chat/conversations/$conversationId/participants',
      data: {'userIds': userIds},
    );
  }

  /// GET /chat/conversations/:id/invite — { inviteCode, inviteUrl } for the
  /// group's join link (code is created lazily on first request).
  Future<Response> getChatInvite(String conversationId) async {
    return await _dio.get(
      '/chat/conversations/$conversationId/invite',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// POST /chat/conversations/:id/invite/rotate — regenerate the join code;
  /// old links stop working. Same response shape as [getChatInvite].
  Future<Response> rotateChatInvite(String conversationId) async {
    return await _dio.post(
      '/chat/conversations/$conversationId/invite/rotate',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// POST /chat/join/:code — self-join a group via its invite link. Returns
  /// the fully-hydrated conversation for the joiner (existing members get it
  /// too — the endpoint is idempotent).
  Future<Response> joinChatByInvite(String code) async {
    return await _dio.post(
      '/chat/join/$code',
      data: <String, dynamic>{},
      options: Options(extra: {'suppressToast': true}),
    );
  }

  // ---- Chat guest contacts ("add anyone by email") ------------------------
  // Registered workspace members resolve to a normal DM; unknown emails get
  // an invite email + an Invited badge row in the chat list.

  /// GET /chat/contacts/lookup?email=
  Future<Response> lookupChatContact(String email, {bool suppressToast = true}) async {
    return await _dio.get('/chat/contacts/lookup',
        queryParameters: {'email': email},
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// POST /chat/contacts/invite { email }
  Future<Response> inviteChatContact(String email, {bool suppressToast = false}) async {
    return await _dio.post('/chat/contacts/invite', data: {'email': email},
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// GET /chat/contacts — the caller's invited (guest) contacts.
  Future<Response> getChatGuestContacts({bool suppressToast = true}) async {
    return await _dio.get('/chat/contacts',
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  /// DELETE /chat/contacts/:id
  Future<Response> deleteChatGuestContact(String contactId, {bool suppressToast = true}) async {
    return await _dio.delete('/chat/contacts/$contactId',
        options: Options(extra: {'suppressToast': suppressToast}));
  }

  Future<Response> getConversationMessages(String conversationId, {int page = 1, int limit = 50}) async {
    return await _dio.get('/chat/conversations/$conversationId/messages', queryParameters: {
      'page': page,
      'limit': limit,
    });
  }

  /// [forwarded] marks the message as forwarded-to-this-chat (chat.ts stores
  /// it and the UI renders a "Forwarded" caption). Backward compatible —
  /// omitted means a normal message.
  Future<Response> sendMessage(
    String conversationId,
    Map<String, dynamic> data, {
    bool forwarded = false,
  }) async {
    return await _dio.post(
      '/chat/conversations/$conversationId/messages',
      data: <String, dynamic>{
        ...data,
        if (forwarded) 'forwarded': true,
      },
    );
  }

  /// Upload chat media (voice notes) via POST /chat/media as multipart
  /// form-data (field name `file`). Returns the hosted URL from
  /// `{ success, data: { url, mimeType, size, attachmentType } }` — pass it as
  /// `attachmentUrl` to [sendMessage]. Throws on network/server errors so the
  /// caller can surface them.
  Future<String?> uploadChatMedia(File file) async {
    final result = await uploadChatMediaDetailed(file);
    return result?.url;
  }

  /// Upload chat media (images / videos / audio / documents / GIFs, 100MB
  /// limit) via POST /chat/media as multipart form-data (field name `file`).
  /// Returns the full upload payload — url, filename, mimeType, byte size and
  /// the backend-detached attachmentType (`image|video|audio|document|gif`) —
  /// so the follow-up [sendMessage] can include attachmentName/attachmentSize.
  /// Throws on network/server errors so the caller can surface them.
  Future<ChatMediaUpload?> uploadChatMediaDetailed(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    final response = await _dio.post('/chat/media', data: formData);
    final data = response.data is Map ? response.data['data'] : null;
    if (data is Map && data['url'] != null) {
      return ChatMediaUpload.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  /// Download a (chat attachment) URL to [savePath] with progress callback.
  /// Absolute URLs bypass the Dio baseUrl automatically; the auth header is
  /// attached by the interceptor. Used for the chat document/image download
  /// buttons (the media URLs are public but the header is harmless).
  Future<void> downloadFile(
    String url,
    String savePath, {
    void Function(int received, int total)? onProgress,
    bool suppressToast = true,
  }) async {
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
      options: Options(extra: {'suppressToast': suppressToast}),
    );
  }

  /// GIF picker proxy: GET /chat/gifs?search=&limit=.
  /// Returns `{ configured, gifs: [{ id, description, url, previewUrl }] }`.
  /// When `configured` is false (no TENOR_API_KEY server-side) the client
  /// hides the GIF tab entirely.
  Future<ChatGifsResult> getChatGifs({String? search, int limit = 16}) async {
    final response = await _dio.get('/chat/gifs', queryParameters: {
      'search': (search == null || search.trim().isEmpty) ? 'trending' : search.trim(),
      'limit': limit,
    }, options: Options(extra: {'suppressToast': true}));
    final data = response.data is Map ? response.data['data'] : null;
    if (data is Map) {
      final gifs = (data['gifs'] as List? ?? const [])
          .whereType<Map>()
          .map((g) => GifObject.fromJson(Map<String, dynamic>.from(g)))
          .toList();
      return ChatGifsResult(configured: data['configured'] == true, gifs: gifs);
    }
    return const ChatGifsResult(configured: false, gifs: []);
  }

  // -------------------------------------------------------------------------
  // MetricAi (plan-gated GLM assistant) — GET /ai/status, POST /ai/chat,
  // GET /ai/history, DELETE /ai/history.
  // -------------------------------------------------------------------------

  /// MetricAi availability for the current business/plan.
  Future<Response> getAiStatus() async {
    return await _dio.get('/ai/status', options: Options(extra: {'suppressToast': true}));
  }

  /// Chat with MetricAi. [imageUrl] is an attached/validated image URL (the
  /// backend runs OCR/vision on it and stores it with the message).
  /// [attachmentUrl] + [attachmentType] carry generic attachments
  /// (currently video clips — attachmentType 'video') which the backend
  /// stores and, for videos, samples frames from for vision.
  Future<Response> sendAiChat(String message, {String? imageUrl, String? attachmentUrl, String? attachmentType}) async {
    return await _dio.post('/ai/chat', data: {
      'message': message,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) 'attachmentUrl': attachmentUrl,
      if (attachmentType != null && attachmentType.isNotEmpty) 'attachmentType': attachmentType,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// MetricAi usage vs the caller's plan limits — GET /ai/usage.
  /// `{ usage: { chat|image|video: { daily: {used, limit, resetsAt},
  /// monthly: {...} } } }` (limit null = unlimited).
  Future<Response> getAiUsage() async {
    return await _dio.get('/ai/usage', options: Options(extra: {'suppressToast': true}));
  }

  // -------------------------------------------------------------------------
  // MetricAi chat intelligence (web Chat.tsx parity) — smart replies,
  // per-message translation and conversation summary. All three are
  // plan-gated server-side and answer 503 `ai_not_configured` when GLM is
  // off; the UI probes /ai/status and hides the entry points instead.
  // -------------------------------------------------------------------------

  /// Smart replies for a conversation — POST /chat/ai/smart-replies
  /// `{ conversationId }` -> `{ suggestions: string[] }` (up to 3, may be
  /// empty when there is nothing to reply to).
  Future<Response> getChatSmartReplies(String conversationId) async {
    return await _dio.post('/chat/ai/smart-replies', data: {
      'conversationId': conversationId,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Translate a message body — POST /chat/ai/translate
  /// `{ text, targetLanguage }` -> `{ translation, language }`.
  Future<Response> aiTranslateText(String text, {String targetLanguage = 'en'}) async {
    return await _dio.post('/chat/ai/translate', data: {
      'text': text,
      'targetLanguage': targetLanguage,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Summarize a whole conversation —
  /// POST /chat/conversations/:id/ai/summarize -> `{ summary }`.
  /// 409 `Nothing to summarize yet` when the chat has no messages.
  Future<Response> summarizeConversation(String conversationId) async {
    return await _dio.post('/chat/conversations/$conversationId/ai/summarize',
        options: Options(extra: {'suppressToast': true}));
  }

  /// Upload a MetricAi attachment (image/video/pdf/text, 100MB) via
  /// POST /ai/attachments as multipart form-data (field `file`). Returns
  /// `{ url, filename, mimeType, attachmentType }` — pass url back as
  /// imageUrl (images) or attachmentUrl+attachmentType (video) on /ai/chat.
  /// Throws on network/server errors so the caller can surface them.
  Future<Map<String, dynamic>?> uploadAiAttachment(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    final response = await _dio.post('/ai/attachments', data: formData,
        options: Options(extra: {'suppressToast': true}));
    final data = response.data is Map ? response.data['data'] : null;
    if (data is Map && data['url'] != null) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  /// MetricAi conversation history (oldest first).
  Future<Response> getAiHistory({int page = 1, int limit = 50}) async {
    return await _dio.get('/ai/history', queryParameters: {
      'page': page,
      'limit': limit,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Clears the caller's MetricAi history.
  Future<Response> deleteAiHistory() async {
    return await _dio.delete('/ai/history', options: Options(extra: {'suppressToast': true}));
  }

  /// Poll an async MetricAi video job (GET /ai/video/:jobId). Status is
  /// processing|success|failed; videoUrl (our own storage, never expires) is
  /// present on success.
  Future<Response> getAiVideoJob(String jobId) async {
    return await _dio.get('/ai/video/$jobId', options: Options(extra: {'suppressToast': true}));
  }

  /// PUBLIC app config — GET /public/app-config. No auth required. Returns
  /// { maintenance_mode: bool, announcement: {...} } and drives the global
  /// MaintenanceGateOverlay + announcement banner (web MaintenanceGate
  /// parity). Suppressed toasts: failures fail-open inside the gate.
  Future<Response> getPublicAppConfig() async {
    return await _dio.get('/public/app-config',
        options: Options(extra: {'suppressToast': true}));
  }

  /// Free public "Ask MetricAi" — POST /public/metric-ai/ask.
  /// No plan required: Metricorex-scoped help with human handoff
  /// (suggestHumanSupport in the response). [sessionId] keeps the 30-minute
  /// server-side conversation thread; pass the id returned by the previous
  /// call to continue the same thread.
  Future<Response> askPublicMetricAi(String message, {String? sessionId}) async {
    return await _dio.post('/public/metric-ai/ask', data: {
      'message': message,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    }, options: Options(extra: {'suppressToast': true}));
  }

  // -------------------------------------------------------------------------
  // MetricAi human handoff — support desk (customer side, JWT auth).
  // POST /support/escalate, GET /support/my/:id/messages?after=ISO,
  // POST /support/my/:id/messages, POST /support/my/:id/close.
  // -------------------------------------------------------------------------

  /// Escalate a MetricAi conversation to a human support agent. [transcript]
  /// is the current AI screen's messages (`{role: 'user'|'assistant',
  /// content}`) so the agent sees the full context. Returns
  /// `{ success, data: { conversationId, status } }`.
  Future<Response> escalateToSupport({
    required String name,
    required String email,
    String? subject,
    String? message,
    String channel = 'mobile',
    List<Map<String, dynamic>> transcript = const [],
  }) async {
    return await _dio.post('/support/escalate', data: {
      'name': name,
      'email': email,
      if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      'channel': channel,
      'transcript': transcript,
    }, options: Options(extra: {'suppressToast': true}));
  }

  /// Messages of the caller's own support conversation. `after` (ISO date)
  /// returns only newer messages (incremental polling). Response:
  /// `{ success, data: { messages: [...], status } }`.
  Future<Response> getMySupportMessages(String conversationId, {String? after}) async {
    return await _dio.get('/support/my/$conversationId/messages',
        queryParameters: {
          if (after != null && after.isNotEmpty) 'after': after,
        },
        options: Options(extra: {'suppressToast': true}));
  }

  /// Send a customer reply in the caller's support conversation.
  Future<Response> sendMySupportMessage(String conversationId, String body) async {
    return await _dio.post('/support/my/$conversationId/messages',
        data: {'body': body}, options: Options(extra: {'suppressToast': true}));
  }

  /// Conclude (close) the caller's own support conversation. Afterwards the
  /// server rejects new messages (400) and the status becomes
  /// 'resolved'|'closed'.
  Future<Response> closeMySupportConversation(String conversationId) async {
    return await _dio.post('/support/my/$conversationId/close',
        options: Options(extra: {'suppressToast': true}));
  }

  /// Upload the user's profile picture via POST /settings/profile/avatar as
  /// multipart form-data (field name `file`). Returns the absolute avatar URL
  /// from `{ success, data: { avatarUrl } }`. Throws on network/server errors
  /// so the caller can surface them.
  Future<String?> uploadProfileAvatar(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    final response = await _dio.post('/settings/profile/avatar', data: formData);
    final data = response.data is Map ? response.data['data'] : null;
    if (data is Map) {
      final url = (data['avatarUrl'] ?? data['avatar_url'] ?? data['url'])?.toString() ?? '';
      return url.isNotEmpty ? resolveMediaUrl(url) : null;
    }
    return null;
  }

  /// Save the personal profile (first-login completion or Settings).
  /// Email is deliberately NOT sent — the backend treats it as read-only.
  /// Any save marks the profile complete and dismisses the first-login prompt.
  Future<Response> saveMyProfile({String? name, String? phoneNumber}) async {
    return await _dio.put('/settings/profile', data: {
      if (name != null) 'name': name,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    });
  }

  /// Send the phone-number verification OTP (SMS) for profile completion.
  Future<Response> sendProfilePhoneOtp(String phone) async {
    return await _dio.post('/settings/profile/phone/send-otp',
        data: {'phone': phone});
  }

  /// Verify the phone OTP; on success the backend commits the number and
  /// flips phone_verified + profile_completed.
  Future<Response> verifyProfilePhoneOtp(String phone, String otp) async {
    return await _dio.post('/settings/profile/phone/verify-otp',
        data: {'phone': phone, 'otp': otp});
  }

  /// Skip CTA for the first-login profile completion prompt (server-persisted
  /// so the prompt does not reappear on other devices).
  Future<Response> dismissProfilePrompt() async {
    return await _dio.post('/settings/profile/dismiss',
        options: Options(extra: {'suppressToast': true}));
  }

  /// Make a media URL absolute. The backend returns absolute URLs for
  /// R2-hosted files but RELATIVE paths (`/uploads/...`) for the local upload
  /// fallback — players (audioplayers / network images) need absolute URLs.
  ///
  /// Bare object keys ("recordings/<biz>/<id>.mp4" from the LiveKit egress
  /// webhook, or chat/metricai keys uploaded to R2 without a public URL) are
  /// NOT URLs — they are routed through the API's public /files/<key>
  /// streaming endpoint, mirroring the web/media-upload normalization.
  static String? resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('file://') ||
        url.startsWith('data:')) {
      return url;
    }
    if (url.startsWith('/')) return '$_apiOrigin$url';
    final bare = url.replaceFirst(RegExp(r'^\.?/'), '');
    if (bare.toLowerCase().startsWith('uploads/')) return '$_apiOrigin/$bare';
    return '$_apiOrigin/files/$bare';
  }

  /// Mark a conversation as read (clears unread badge for the current user).
  /// Backend: PUT /chat/conversations/:conversationId/read
  Future<Response> markConversationAsRead(String conversationId) async {
    return await _dio.put('/chat/conversations/$conversationId/read');
  }

  /// WhatsApp-style "delete chat": removes a DIRECT conversation from MY
  /// chat list only (the other participant keeps it; a new message un-hides).
  /// Groups are rejected by the backend — leave them instead.
  Future<Response> deleteConversation(String conversationId) async {
    return await _dio.delete('/chat/conversations/$conversationId');
  }

  // -------------------------------------------------------------------------
  // Message actions (parity with the web batch-4 contract)
  // -------------------------------------------------------------------------

  /// Edit the text of one of YOUR messages (backend enforces the ≤24h window
  /// on text messages). PATCH /chat/conversations/:cid/messages/:mid
  Future<Response> editChatMessage(
    String conversationId,
    String messageId, {
    required String content,
  }) async {
    return await _dio.patch(
      '/chat/conversations/$conversationId/messages/$messageId',
      data: {'content': content},
    );
  }

  /// Delete a message. [scope] `me` hides it for this user only; `everyone`
  /// tombstones it for the whole conversation (own messages only).
  /// DELETE /chat/conversations/:cid/messages/:mid?scope=me|everyone
  Future<Response> deleteChatMessage(
    String conversationId,
    String messageId, {
    String scope = 'me',
  }) async {
    return await _dio.delete(
      '/chat/conversations/$conversationId/messages/$messageId',
      queryParameters: {'scope': scope},
    );
  }

  // Calls API
  Future<Response> getCalls({int page = 1, int limit = 10}) async {
    return await _dio.get('/calls', queryParameters: {
      'page': page,
      'limit': limit,
    });
  }

  Future<Response> getCallByCode(String code) async {
    return await _dio.get('/calls/code/$code');
  }

  /// Full call record incl. participants (`{ userId, status, joinedAt,
  /// leftAt }`) — used by the chat call-log tap-through summary sheet.
  Future<Response> getCallById(String id) async {
    return await _dio.get('/calls/$id', options: Options(extra: {'suppressToast': true}));
  }

  /// Stored live-caption transcript for a call (absent on backends without
  /// the endpoint — callers must treat failures as "no transcript").
  Future<Response> getCallTranscript(String id) async {
    return await _dio.get('/calls/$id/transcript', options: Options(extra: {'suppressToast': true}));
  }

  Future<Response> createCall(Map<String, dynamic> data) async {
    return await _dio.post('/calls', data: data);
  }

  Future<Response> updateCall(String id, Map<String, dynamic> data) async {
    return await _dio.put('/calls/$id', data: data);
  }

  /// Always send a JSON body: the backend runs Express 5, where a bodyless
  /// POST leaves `req.body` undefined and routes that destructure it crash
  /// with a 500 (this silently killed every passwordless call join).
  Future<Response> joinCall(String id, {String? password}) async {
    return await _dio.post('/calls/$id/join', data: <String, dynamic>{
      if (password != null) 'password': password,
    });
  }


  Future<Response> leaveCall(String id) async {
    return await _dio.post('/calls/$id/leave');
  }

  /// POST /calls/:id/reject — REST decline for an incoming call. Used from
  /// the notification action button (background isolate) where the app-side
  /// socket may be dead, so the socket-only `call:reject` emit cannot be
  /// relied on. Backend marks the callee rejected, notifies the caller and
  /// emits `call:rejected`.
  Future<Response> rejectCall(String callId) async {
    return await _dio.post(
      '/calls/$callId/reject',
      data: <String, dynamic>{},
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// Mint/refresh short-lived media credentials for a room
  /// (`POST /rtc/token`). Used by the call screen to retry the media
  /// connection ONCE with fresh credentials when the first connect fails —
  /// the backend health-checks its media servers and returns credentials for
  /// whichever provider is actually healthy (or the default one when the
  /// secondary provider is down).
  Future<Response> refreshRtcToken({required String roomType, required String roomId}) async {
    return await _dio.post(
      '/rtc/token',
      data: {'roomType': roomType, 'roomId': roomId},
      options: Options(extra: {'suppressToast': true}),
    );
  }

  Future<Response> deleteCall(String id) async {
    return await _dio.delete('/calls/$id');
  }

  Future<Response> joinMeeting(String id, {String? password}) async {
    return await _dio.post('/meetings/$id/join', data: password != null ? {'password': password} : null);
  }

  Future<Response> leaveMeeting(String id) async {
    return await _dio.post('/meetings/$id/leave');
  }

  /// AI meeting notes (summary / key points / decisions / action items).
  /// Returns `{ success, data: { meetingId, notes: <map|null> } }` — notes is
  /// null when they have not been generated yet.
  Future<Response> getMeetingNotes(String id) async {
    return await _dio.get(
      '/meetings/$id/notes',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// (Re)generate AI meeting notes from the stored live-caption transcript.
  /// Responds 409 with `errorCode: 'no_transcript'` when not enough transcript
  /// content exists yet.
  Future<Response> generateMeetingNotes(String id) async {
    return await _dio.post(
      '/meetings/$id/notes/generate',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  /// Stored live-caption transcript segments for a meeting
  /// (`{ success, data: { meetingId, segments: [...] } }`).
  Future<Response> getMeetingTranscript(String id) async {
    return await _dio.get(
      '/meetings/$id/transcript',
      options: Options(extra: {'suppressToast': true}),
    );
  }

  // Recordings API
  Future<Response> getRecordings({int page = 1, int limit = 10}) async {
    return await _dio.get('/recordings', queryParameters: {
      'page': page,
      'limit': limit,
    });
  }

  Future<Response> startRecording(Map<String, dynamic> data) async {
    return await _dio.post('/recordings', data: data);
  }

  Future<Response> updateRecording(String id, Map<String, dynamic> data) async {
    return await _dio.put('/recordings/$id', data: data);
  }

  Future<Response> deleteRecording(String id) async {
    return await _dio.delete('/recordings/$id');
  }

  Future<Response> uploadRecording(String id, String filePath, {int? duration}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (duration != null) 'duration': duration,
    });
    return await _dio.post('/recordings/$id/upload', data: formData);
  }

  /// Start SERVER-SIDE recording for a call/meeting room (host only).
  /// Backend: POST /rtc/rooms/:roomType/:roomId/recording/start
  ///
  /// Returns the response `data` map:
  ///  - { mode: 'server', recordingId, egressId, ... } → LiveKit egress started;
  ///    pass `recordingId` to [stopRoomRecording]. A DB row was created and the
  ///    finalized MP4 lands in R2 (webhook sets storage_url).
  ///  - { mode: 'client', reason? } → the room's provider (MediaSoup) has no
  ///    server recorder; composite recording is only available on web.
  ///
  /// Throws DioException on errors (403 non-host, 409 already recording, 410
  /// room ended) — callers surface `error.response.data['error']`.
  Future<Map<String, dynamic>?> startRoomRecording({
    required bool isMeeting,
    required String roomId,
    bool audioOnly = false,
  }) async {
    final roomType = isMeeting ? 'meeting' : 'call';
    final response = await _dio.post(
      '/rtc/rooms/$roomType/$roomId/recording/start',
      data: {'audioOnly': audioOnly},
    );
    return response.data is Map<String, dynamic>
        ? (response.data['data'] as Map<String, dynamic>?)
        : null;
  }

  /// Stop the active server-side recording (host only).
  /// Backend: POST /rtc/rooms/:roomType/:roomId/recording/stop
  /// Returns { recordingId, mediaStopped } from the response `data`.
  Future<Map<String, dynamic>?> stopRoomRecording({
    required bool isMeeting,
    required String roomId,
    String? recordingId,
  }) async {
    final roomType = isMeeting ? 'meeting' : 'call';
    final response = await _dio.post(
      '/rtc/rooms/$roomType/$roomId/recording/stop',
      data: {if (recordingId != null && recordingId.isNotEmpty) 'recordingId': recordingId},
    );
    return response.data is Map<String, dynamic>
        ? (response.data['data'] as Map<String, dynamic>?)
        : null;
  }

  // Notifications API
  Future<Response> getNotifications({int page = 1, int limit = 20, bool unreadOnly = false}) async {
    return await _dio.get('/notifications', queryParameters: {
      'page': page,
      'limit': limit,
      'unreadOnly': unreadOnly,
    });
  }

  Future<Response> markNotificationAsRead(String id) async {
    return await _dio.patch('/notifications/$id/read');
  }

  Future<Response> markAllNotificationsAsRead() async {
    return await _dio.patch('/notifications/read-all');
  }

  Future<Response> takeNotificationAction(String id, String action) async {
    return await _dio.post('/notifications/$id/action', data: {'action': action});
  }
}

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // Secure storage is the PRIMARY home for the session token. Every access
  // is guarded — if the platform doesn't support it (or the keychain is
  // unavailable), we transparently fall back to SharedPreferences.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static bool _secureStorageAvailable = true;

  Future<void> _writeTokenSecurely(String token) async {
    if (!_secureStorageAvailable) return;
    try {
      await _secureStorage.write(key: 'token', value: token);
    } catch (e) {
      // Unsupported platform / plugin failure → keep using SharedPreferences.
      _secureStorageAvailable = false;
      debugPrint('Secure token storage unavailable, falling back to SharedPreferences: $e');
    }
  }

  Future<String?> _readTokenSecurely() async {
    if (!_secureStorageAvailable) return null;
    try {
      return await _secureStorage.read(key: 'token');
    } catch (e) {
      _secureStorageAvailable = false;
      debugPrint('Secure token storage unavailable, falling back to SharedPreferences: $e');
      return null;
    }
  }

  Future<void> _deleteTokenSecurely() async {
    if (!_secureStorageAvailable) return;
    try {
      await _secureStorage.delete(key: 'token');
    } catch (e) {
      _secureStorageAvailable = false;
      debugPrint('Secure token storage delete failed: $e');
    }
  }

  Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    // Primary: secure storage. The SharedPreferences copy is kept for
    // backward compatibility (dio interceptor and existing code paths read
    // prefs directly).
    await _writeTokenSecurely(token);
  }

  Future<String?> getToken() async {
    final secureToken = await _readTokenSecurely();
    if (secureToken != null && secureToken.isNotEmpty) return secureToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await _deleteTokenSecurely();
  }

  /// Clears ALL session material (token, ids, profile name) from BOTH stores
  /// — secure storage AND SharedPreferences. Used by the session-expired
  /// handler: the interceptor previously only wiped the SharedPreferences
  /// copies, so a dead secure-storage token kept being attached to requests
  /// and the app stayed trapped in an authenticated-looking 403 loop.
  /// Biometric enrollment keys are deliberately untouched.
  Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('userId');
      await prefs.remove('businessId');
      await prefs.remove('userName');
    } catch (_) {}
    await _deleteTokenSecurely();
  }

  Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId');
  }

  Future<void> setBusinessId(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('businessId', businessId);
  }

  Future<String?> getBusinessId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('businessId');
  }

  Future<void> setUserName(String userName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', userName);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userName');
  }

  // Google SSO / sign-in security extras
  Future<void> setAvatarUrl(String? avatarUrl) async {
    final prefs = await SharedPreferences.getInstance();
    if (avatarUrl == null || avatarUrl.isEmpty) {
      await prefs.remove('avatarUrl');
    } else {
      await prefs.setString('avatarUrl', avatarUrl);
    }
  }

  Future<String?> getAvatarUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('avatarUrl');
  }

  Future<void> setRequiresPasswordSetup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('requiresPasswordSetup', value);
  }

  Future<bool> getRequiresPasswordSetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('requiresPasswordSetup') ?? false;
  }

  Future<void> setAuthProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('authProvider', provider);
  }

  Future<String?> getAuthProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('authProvider');
  }

  Future<void> setHasPassword(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasPassword', value);
  }

  Future<bool?> getHasPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasPassword');
  }

  // Biometrics credential storage
  Future<void> setBiometricsCredentials({
    required String token,
    required String userId,
    required String businessId,
    required String userName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('biometrics_token', token);
    await prefs.setString('biometrics_userId', userId);
    await prefs.setString('biometrics_businessId', businessId);
    await prefs.setString('biometrics_userName', userName);
  }

  Future<Map<String, String>?> getBiometricsCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('biometrics_token');
    final userId = prefs.getString('biometrics_userId');
    final businessId = prefs.getString('biometrics_businessId');
    final userName = prefs.getString('biometrics_userName');
    if (token != null && userId != null && businessId != null && userName != null) {
      return {
        'token': token,
        'userId': userId,
        'businessId': businessId,
        'userName': userName,
      };
    }
    return null;
  }

  Future<void> clearBiometricsCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('biometrics_token');
    await prefs.remove('biometrics_userId');
    await prefs.remove('biometrics_businessId');
    await prefs.remove('biometrics_userName');
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricsEnabled', enabled);
  }

  Future<bool> getBiometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometricsEnabled') ?? false;
  }

  Future<void> removeBiometricsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('biometricsEnabled');
  }

  // ------------------------------------------------------------------
  // PER-ACCOUNT biometric switch + prompt tracking.
  //
  // The legacy global flags above are DEVICE-wide: once account A enabled
  // biometrics (or dismissed the setup prompt) account B was never asked and
  // silently inherited A's switch. Biometrics is now keyed by ACCOUNT:
  //   biometricsEnabled_<userId>       — per-account opt-in
  //   biometricsPromptShown_<userId>   — per-account setup-prompt memory
  // POISONING FIX: the per-account getters NO LONGER fall back to the legacy
  // device-wide keys and the per-account setters NO LONGER mirror into them —
  // the fallback/mirror made a brand-new account inherit a previous account's
  // values (promptShown=true meant the activation offer never appeared).
  // A fresh account now genuinely starts from false/false. The legacy keys
  // remain only for the (rare) code paths that have no userId available.
  // ------------------------------------------------------------------

  Future<void> setBiometricsEnabledForAccount(String userId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricsEnabled_$userId', enabled);
    await prefs.setBool('biometricsEnabled', enabled); // legacy mirror
  }

  Future<bool> getBiometricsEnabledForAccount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    // PER-ACCOUNT ONLY — no legacy fallback. Falling back to the device-wide
    // flag poisoned new accounts with a PREVIOUS account's opt-in.
    return prefs.getBool('biometricsEnabled_$userId') ?? false;
  }

  Future<void> setBiometricsPromptShownForAccount(String userId, bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    // PER-ACCOUNT ONLY — no mirroring into the legacy device-wide key:
    // mirroring made one account's dismissal silence the activation offer
    // for every account signed in afterwards on this device.
    await prefs.setBool('biometricsPromptShown_$userId', shown);
  }

  Future<bool> getBiometricsPromptShownForAccount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    // PER-ACCOUNT ONLY — no legacy fallback: a brand-new account must reach
    // the biometric activation offer even when an older account on this
    // device already dismissed it.
    return prefs.getBool('biometricsPromptShown_$userId') ?? false;
  }

  // SSO onboarding gate — persisted copy of the server's profileCompleted
  // flag so the completion screen can be shown right after a cold restart
  // too (until GET /auth/me refreshes the authoritative value).
  Future<void> setProfileCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('profileCompleted', completed);
  }

  Future<bool?> getProfileCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('profileCompleted');
  }

  Future<void> removeProfileCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profileCompleted');
  }

  Future<void> setBiometricsPromptShown(bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometricsPromptShown', shown);
  }

  Future<bool> getBiometricsPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometricsPromptShown') ?? false;
  }

  Future<void> removeBiometricsPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('biometricsPromptShown');
  }

  // -------------------------------------------------------------------------
  // Backend biometric enrollment storage.
  //
  // The biometric_token is a bearer secret -> it lives in
  // flutter_secure_storage, KEYED PER DEVICE (`biometric_token_<device_id>`).
  // The stable device_id is a random UUID generated once and persisted
  // alongside it (secure storage first, SharedPreferences fallback).
  // -------------------------------------------------------------------------

  static const String _biometricDeviceIdKey = 'biometric_device_id';

  Future<String?> getBiometricDeviceId() async {
    if (_secureStorageAvailable) {
      try {
        final v = await _secureStorage.read(key: _biometricDeviceIdKey);
        if (v != null && v.isNotEmpty) return v;
      } catch (e) {
        _secureStorageAvailable = false;
        debugPrint('Secure device-id read failed, using SharedPreferences: $e');
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_biometricDeviceIdKey);
    } catch (_) {
      return null;
    }
  }

  /// Returns the stable per-install device id, creating (and persisting) a
  /// random UUID on first use. Never throws.
  Future<String> getOrCreateBiometricDeviceId() async {
    final existing = await getBiometricDeviceId();
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _generateDeviceId();
    bool stored = false;
    if (_secureStorageAvailable) {
      try {
        await _secureStorage.write(key: _biometricDeviceIdKey, value: id);
        stored = true;
      } catch (e) {
        _secureStorageAvailable = false;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_biometricDeviceIdKey, id);
      stored = true;
    } catch (_) {}
    if (!stored) debugPrint('Warning: biometric device_id could not be persisted');
    return id;
  }

  /// Random UUIDv4-shaped id (no extra package needed).
  static String _generateDeviceId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> setBiometricToken(String deviceId, String token) async {
    final key = 'biometric_token_$deviceId';
    if (_secureStorageAvailable) {
      try {
        await _secureStorage.write(key: key, value: token);
      } catch (e) {
        _secureStorageAvailable = false;
        debugPrint('Secure biometric token write failed: $e');
      }
    }
    // Best-effort fallback copy so revoke/login still works on platforms
    // without secure storage.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, token);
    } catch (_) {}
  }

  Future<String?> getBiometricToken(String deviceId) async {
    final key = 'biometric_token_$deviceId';
    if (_secureStorageAvailable) {
      try {
        final v = await _secureStorage.read(key: key);
        if (v != null && v.isNotEmpty) return v;
      } catch (e) {
        _secureStorageAvailable = false;
        debugPrint('Secure biometric token read failed: $e');
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearBiometricToken(String deviceId) async {
    final key = 'biometric_token_$deviceId';
    if (_secureStorageAvailable) {
      try {
        await _secureStorage.delete(key: key);
      } catch (e) {
        _secureStorageAvailable = false;
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Bump when the onboarding flow changes (new slides/design). Existing
  /// installs will see onboarding once more after an app update ships a
  /// higher version here. The legacy bool-only flag predates versioning.
  static const int kOnboardingVersion = 2;

  Future<void> setHasSeenOnboarding(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', seen);
    if (seen) {
      await prefs.setInt('onboarding_seen_version', kOnboardingVersion);
    }
  }

  /// Whether the guided app tour (lib/widgets/app_tour.dart) has already been
  /// completed or skipped on this device.
  Future<void> setHasSeenAppTour(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenAppTour', seen);
  }

  Future<bool> getHasSeenAppTour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenAppTour') ?? false;
  }

  Future<bool> getHasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // Version-keyed: legacy installs (bool flag only, no version key) have
    // NOT seen the CURRENT onboarding -> they get it once after the update
    // (fixes "onboarding not showing after app update").
    final seenVersion = prefs.getInt('onboarding_seen_version') ?? 0;
    return seenVersion >= kOnboardingVersion;
  }

  Future<void> setLastRoute(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoute', route);
  }

  Future<String?> getLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastRoute');
  }

  Future<void> removeLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastRoute');
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('businessId');
    await prefs.remove('userName');
    await prefs.remove('avatarUrl');
    await prefs.remove('requiresPasswordSetup');
    await prefs.remove('authProvider');
    await prefs.remove('hasPassword');
    await _deleteTokenSecurely();
    // Keep biometricsEnabled, biometricsPromptShown, hasSeenOnboarding, lastRoute, and biometrics credentials
  }
}
