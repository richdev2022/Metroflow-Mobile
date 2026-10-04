import 'package:flutter/foundation.dart';

class Logger {
  static void log(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    assert(() {
      debugPrint('[LOG] $message');
      if (error != null) debugPrint(error.toString());
      if (stackTrace != null) debugPrint(stackTrace.toString());
      return true;
    }());
  }

  static void warn(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    assert(() {
      debugPrint('[WARN] $message');
      if (error != null) debugPrint(error.toString());
      if (stackTrace != null) debugPrint(stackTrace.toString());
      return true;
    }());
  }

  static void error(String message, [dynamic error, bool showAlert = false]) {
    debugPrint('[ERROR] $message');
    if (error != null) debugPrint(error.toString());
  }

  static void critical(String message, [dynamic error]) {
    error(message, error, true);
  }
}
