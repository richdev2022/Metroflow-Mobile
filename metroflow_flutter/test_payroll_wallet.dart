import 'dart:convert';
import 'package:dio/dio.dart';

const String apiBaseUrl = 'https://Metricorex-backend.netlify.app/api';
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
      return handler.next(options);
    },
    onResponse: (response, handler) {
      print('✅ ${response.requestOptions.uri.path}');
      print('📡 ${jsonEncode(response.data)}');
      return handler.next(response);
    },
    onError: (error, handler) {
      print('❌ ${error.requestOptions.uri.path}');
      if (error.response != null) {
        print('❌ ${jsonEncode(error.response?.data)}');
      }
      return handler.next(error);
    },
  ));

  print('--- WALLET ---');
  await dio.get('/wallet');
  print('\n--- PAYROLL SUMMARY ---');
  await dio.get('/payroll/summary');
  print('\n--- PAYROLL CONFIG ---');
  await dio.get('/payroll/config');
}
// ignore_for_file: avoid_print
