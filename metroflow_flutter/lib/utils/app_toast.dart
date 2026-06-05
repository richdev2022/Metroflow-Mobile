import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../theme/app_theme.dart';

enum AppToastType { info, success, error, warning }

class AppToast {
  const AppToast._();

  static void show(
    String message, {
    AppToastType type = AppToastType.info,
    bool isLong = false,
  }) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: isLong ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIosWeb: isLong ? 3 : 2,
      backgroundColor: AppColors.primary,
      textColor: Colors.white,
      fontSize: 15,
    );
  }

}
