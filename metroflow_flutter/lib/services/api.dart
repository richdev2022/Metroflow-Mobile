import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metroflow_flutter/utils/app_toast.dart';
import 'package:flutter/material.dart';

const String _apiBaseUrl = 'https://metroflow-backend.netlify.app/api';

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

  late final Dio _dio;

  String? _extractResponseMessage(dynamic data) {
    if (data is Map) {
      final message = data['message'] ?? data['error'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message != null) return message.toString();
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return null;
  }

  Future<void> _handleSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('userId');
    await prefs.remove('businessId');
    await prefs.remove('userName');
    showSessionExpiredModal();
  }

  void _initializeDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _apiBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['Content-Type'] = options.data is FormData
            ? Headers.multipartFormDataContentType
            : Headers.jsonContentType;
        return handler.next(options);
      },
      onResponse: (response, handler) async {
        final data = response.data;
        final isSuccess = data is Map && data['success'] == true;
        final isFailure = data is Map && data['success'] == false;

        // Check for token error even in 200 OK responses
        if (isFailure) {
          final errorMsg = (data['error'] as String?)?.toLowerCase() ?? '';
          if (errorMsg.contains('invalid') || errorMsg.contains('expired')) {
            await _handleSessionExpired();
            // Don't show toast for token errors
            return handler.next(response);
          }
        }
        
        // Show success toast for non-GET requests if success and message exists
        if (isSuccess && response.requestOptions.method != 'GET' &&
            response.requestOptions.extra['suppressToast'] != true) {
          final successMessage = _extractResponseMessage(data);
          if (successMessage != null) {
            AppToast.show(successMessage, type: AppToastType.success);
          }
        }
        
        // Show error toast if success is false (and not token error)
        if (isFailure && response.requestOptions.extra['suppressToast'] != true) {
          final errorMessage = _extractResponseMessage(data) ?? 'Something went wrong';
          AppToast.show(errorMessage, type: AppToastType.error);
        }
        
        return handler.next(response);
      },
      onError: (error, handler) async {
        final message = _extractResponseMessage(error.response?.data) ?? 'Something went wrong';
        final errorData = error.response?.data;
        final isPlanUpgradeError = errorData is Map && 
            errorData['error'] != null && 
            errorData['error'].toString().toLowerCase().contains('upgrade');

        // Only logout for actual auth failures
        if (error.response?.statusCode == 401 || error.response?.statusCode == 403) {
          // Check if this is a plan upgrade error or other non-auth 401
          if (!isPlanUpgradeError) {
            // Check if the error message is something that means token is invalid
            final errorMsg = (errorData is Map ? errorData['error'] : null)?.toString().toLowerCase() ?? '';
            if (errorMsg.contains('invalid') || errorMsg.contains('expired') || errorMsg.contains('unauthorized')) {
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
    return await _dio.post('/auth/login', data: {'email': email, 'password': password});
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
  Future<Response> initiateKyc(String type, String number) async {
    return await _dio.post('/kyc/initiate', data: {'type': type, 'number': number});
  }

  Future<Response> verifyKycOtp(String otp) async {
    return await _dio.post('/kyc/verify-otp', data: {'otp': otp});
  }

  Future<Response> getKycStatus() async {
    return await _dio.get('/kyc/status');
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

  // Wallet API
  Future<Response> getWallet() async {
    return await _dio.get('/wallet');
  }

  Future<Response> fundWallet(double amount, String walletType) async {
    return await _dio.post('/wallet/fund/card', data: {'amount': amount, 'wallet_type': walletType});
  }

  Future<Response> createBusinessWallet(String gtbAccountNumber, String businessName, {String? kycReferenceId}) async {
    return await _dio.post('/wallet/business/create', data: {
      'gtb_account_number': gtbAccountNumber,
      'business_name': businessName,
      'kycReferenceId': kycReferenceId,
    });
  }

  Future<Response> verifyWalletFunding(String reference) async {
    return await verifyWalletPayment(reference);
  }

  Future<Response> createVirtualAccount() async {
    return await _dio.post('/wallet/create-virtual-account');
  }

  Future<Response> verifyWalletPayment(String reference, {bool suppressToast = false}) async {
    return await _dio.get(
      '/wallet/verify',
      queryParameters: {'reference': reference},
      options: Options(extra: {'suppressToast': suppressToast}),
    );
  }

  // Transfers API
  Future<Response> getBanks() async {
    return await _dio.get('/transfers/banks');
  }

  Future<Response> resolveAccount(String bankCode, String accountNumber) async {
    return await _dio.post('/transfers/account-lookup', data: {
      'bank_code': bankCode,
      'account_number': accountNumber,
    });
  }

  Future<Response> lookupTransferAccount(String bankCode, String accountNumber) async {
    return await _dio.post('/transfers/lookup', data: {
      'bank_code': bankCode,
      'account_number': accountNumber,
    });
  }

  Future<Response> requestTransferOtp({String? walletId}) async {
    return await _dio.post('/transfers/otp/request', data: {'wallet_id': walletId});
  }

  Future<Response> singleTransfer(Map<String, dynamic> data) async {
    return await _dio.post('/transfers/single', data: data);
  }

  Future<Response> bulkTransfer(Map<String, dynamic> data) async {
    return await _dio.post('/transfers/bulk', data: data);
  }

  Future<Response> bulkTransferV2(Map<String, dynamic> data) async {
    return await _dio.post('/transfers/bulk', data: data);
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
}

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
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

  Future<void> setHasSeenOnboarding(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', seen);
  }

  Future<bool> getHasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenOnboarding') ?? false;
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
    // Keep biometricsEnabled, biometricsPromptShown, hasSeenOnboarding, lastRoute, and biometrics credentials
  }
}
