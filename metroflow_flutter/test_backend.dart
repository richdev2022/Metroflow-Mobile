import 'dart:convert';
import 'package:dio/dio.dart';

const String apiBaseUrl = 'https://metroflow-backend.netlify.app/api';
const String testToken = 'eyJ1c2VySWQiOiI3NTZmMTJiMi01OTY5LTRlYWUtOGFhOC1lNGNjNzczY2Y4MjQiLCJidXNpbmVzc0lkIjoiVkJSSEEzOSIsImlhdCI6MTc4MDU2ODQ2MiwiZXhwIjoxNzgwNjU0ODYyfQ==';

void main() async {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      options.headers['Authorization'] = 'Bearer $testToken';
      options.headers['Content-Type'] = 'application/json';
      print('🔍 Request: ${options.method} ${options.uri}');
      print('🔍 Request Body: ${options.data != null ? jsonEncode(options.data) : 'None'}');
      return handler.next(options);
    },
    onResponse: (response, handler) {
      print('📡 Response Status: ${response.statusCode}');
      print('📡 Response Body: ${response.data}');
      return handler.next(response);
    },
    onError: (error, handler) {
      print('❌ Error: ${error.message}');
      if (error.response != null) {
        print('❌ Error Status: ${error.response?.statusCode}');
        print('❌ Error Data: ${error.response?.data}');
      }
      return handler.next(error);
    },
  ));

  print('=== TESTING BACKEND ===');
  print('\n--- 1. Test Get Wallet ---');
  try {
    final walletRes = await dio.get('/wallet');
    print('✅ Wallet OK: ${walletRes.statusCode}');
    print('📊 Wallet Data: ${walletRes.data}');
  } catch (e) {
    print('❌ Wallet error: $e');
  }

  print('\n--- 2. Test Get Payroll Summary ---');
  try {
    final payrollRes = await dio.get('/payroll/summary', queryParameters: {'limit': '10000'});
    print('✅ Payroll summary OK: ${payrollRes.statusCode}');
    print('📊 Payroll Data: ${payrollRes.data}');
  } catch (e) {
    print('❌ Payroll error: $e');
  }

  print('\n--- 3. Test Get Payroll Config ---');
  try {
    final configRes = await dio.get('/payroll/config');
    print('✅ Payroll config OK: ${configRes.statusCode}');
    print('📊 Config Data: ${configRes.data}');
  } catch (e) {
    print('❌ Payroll config error: $e');
  }

  print('\n--- 4. Test Get Banks ---');
  try {
    final banksRes = await dio.get('/transfers/banks');
    print('✅ Banks OK: ${banksRes.statusCode}');
    print('📊 Banks Data: ${banksRes.data}');
  } catch (e) {
    print('❌ Banks error: $e');
  }

  print('\n--- 5. Test Get Transfers ---');
  try {
    final transfersRes = await dio.get('/transfers', queryParameters: {'limit': '100'});
    print('✅ Transfers OK: ${transfersRes.statusCode}');
    print('📊 Transfers Data: ${transfersRes.data}');
  } catch (e) {
    print('❌ Transfers error: $e');
  }

  print('\n--- 6. Test Get Epics ---');
  try {
    final epicsRes = await dio.get('/epics');
    print('✅ Epics OK: ${epicsRes.statusCode}');
    print('📊 Epics Data: ${epicsRes.data}');
  } catch (e) {
    print('❌ Epics error: $e');
  }

  print('\n=== DONE ===');
}
// ignore_for_file: avoid_print
