Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/utils/app_toast.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/providers/auth_provider.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/theme/app_theme.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/services/api.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/models/employee.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/models/epic.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/models/bank.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/models/wallet.dart'.
Error: Couldn't resolve the package 'metricorex_flutter' in 'package:metricorex_flutter/models/transfer.dart'.
lib/main.dart:45:8: Error: Error when reading 'lib/screens/board_screen.dart': No such file or directory
import 'screens/board_screen.dart';
       ^
lib/services/api.dart:4:8: Error: Not found: 'package:metricorex_flutter/utils/app_toast.dart'
import 'package:metricorex_flutter/utils/app_toast.dart';
       ^
lib/services/api.dart:6:8: Error: Not found: 'package:metricorex_flutter/providers/auth_provider.dart'
import 'package:metricorex_flutter/providers/auth_provider.dart';
       ^
lib/screens/bulk_transfer_screen.dart:5:8: Error: Not found: 'package:metricorex_flutter/theme/app_theme.dart'
import 'package:metricorex_flutter/theme/app_theme.dart';
       ^
lib/screens/bulk_transfer_screen.dart:6:8: Error: Not found: 'package:metricorex_flutter/services/api.dart'
import 'package:metricorex_flutter/services/api.dart';
       ^
lib/screens/bulk_transfer_screen.dart:7:8: Error: Not found: 'package:metricorex_flutter/models/employee.dart'
import 'package:metricorex_flutter/models/employee.dart';
       ^
lib/screens/bulk_transfer_screen.dart:8:8: Error: Not found: 'package:metricorex_flutter/models/epic.dart'
import 'package:metricorex_flutter/models/epic.dart';
       ^
lib/screens/bulk_transfer_screen.dart:9:8: Error: Not found: 'package:metricorex_flutter/models/bank.dart'
import 'package:metricorex_flutter/models/bank.dart';
       ^
lib/screens/bulk_transfer_screen.dart:10:8: Error: Not found: 'package:metricorex_flutter/models/wallet.dart'
import 'package:metricorex_flutter/models/wallet.dart';
       ^
lib/screens/bulk_transfer_screen.dart:11:8: Error: Not found: 'package:metricorex_flutter/models/transfer.dart'
import 'package:metricorex_flutter/models/transfer.dart';
       ^
lib/screens/bulk_transfer_screen.dart:21:8: Error: Type 'Employee' not found.
  List<Employee> _employees = [];
       ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:22:8: Error: Type 'Epic' not found.
  List<Epic> _epics = [];
       ^^^^
lib/screens/bulk_transfer_screen.dart:27:3: Error: Type 'Epic' not found.
  Epic? _selectedEpic;
  ^^^^
lib/screens/bulk_transfer_screen.dart:30:8: Error: Type 'Bank' not found.
  List<Bank> _banks = [];
       ^^^^
lib/screens/bulk_transfer_screen.dart:492:3: Error: Type 'Wallet' not found.
  Wallet? get _selectedWalletData {
  ^^^^^^
lib/screens/bulk_transfer_screen.dart:797:34: Error: Type 'Employee' not found.
  Widget _employeeTile({required Employee employee}) {
                                 ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1076:27: Error: Type 'ThemeColors' not found.
  Widget _buildEpicPicker(ThemeColors colors) {
                          ^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1174:27: Error: Type 'ThemeColors' not found.
  Widget _buildBankPicker(ThemeColors colors) {
                          ^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1292:25: Error: Type 'ThemeColors' not found.
  Widget _buildOtpModal(ThemeColors colors) {
                        ^^^^^^^^^^^
lib/main.dart:315:50: Error: Not a constant expression.
              builder: (context, state) => const BoardScreen(),
                                                 ^^^^^^^^^^^
lib/services/api.dart:76:9: Error: The getter 'authNotifierInstance' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'authNotifierInstance'.
    if (authNotifierInstance != null) {
        ^^^^^^^^^^^^^^^^^^^^
lib/services/api.dart:77:13: Error: The getter 'authNotifierInstance' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'authNotifierInstance'.
      await authNotifierInstance!.logout(disableBiometrics: true);
            ^^^^^^^^^^^^^^^^^^^^
lib/services/api.dart:135:13: Error: The getter 'AppToast' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToast'.
            AppToast.show(successMessage, type: AppToastType.success);
            ^^^^^^^^
lib/services/api.dart:135:49: Error: The getter 'AppToastType' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToastType'.
            AppToast.show(successMessage, type: AppToastType.success);
                                                ^^^^^^^^^^^^
lib/services/api.dart:142:11: Error: The getter 'AppToast' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToast'.
          AppToast.show(errorMessage, type: AppToastType.error);
          ^^^^^^^^
lib/services/api.dart:142:45: Error: The getter 'AppToastType' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToastType'.
          AppToast.show(errorMessage, type: AppToastType.error);
                                            ^^^^^^^^^^^^
lib/services/api.dart:173:11: Error: The getter 'AppToast' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToast'.
          AppToast.show(message, type: AppToastType.error);
          ^^^^^^^^
lib/services/api.dart:173:40: Error: The getter 'AppToastType' isn't defined for the type 'ApiService'.
 - 'ApiService' is from 'package:metroflow_flutter/services/api.dart' ('lib/services/api.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppToastType'.
          AppToast.show(message, type: AppToastType.error);
                                       ^^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:21:8: Error: 'Employee' isn't a type.
  List<Employee> _employees = [];
       ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:22:8: Error: 'Epic' isn't a type.
  List<Epic> _epics = [];
       ^^^^
lib/screens/bulk_transfer_screen.dart:27:3: Error: 'Epic' isn't a type.
  Epic? _selectedEpic;
  ^^^^
lib/screens/bulk_transfer_screen.dart:30:8: Error: 'Bank' isn't a type.
  List<Bank> _banks = [];
       ^^^^
lib/screens/bulk_transfer_screen.dart:79:19: Error: The method 'ApiService' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'ApiService'.
      final api = ApiService();
                  ^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:80:41: Error: The argument type 'List<dynamic>' can't be assigned to the parameter type 'Iterable<Future<dynamic>>'.
 - 'List' is from 'dart:core'.
 - 'Iterable' is from 'dart:core'.
 - 'Future' is from 'dart:async'.
      final results = await Future.wait([
                                        ^
lib/screens/bulk_transfer_screen.dart:96:27: Error: The getter 'Employee' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'Employee'.
              .map((e) => Employee.fromJson(e as Map<String, dynamic>))
                          ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:112:27: Error: The getter 'Epic' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'Epic'.
              .map((e) => Epic.fromJson(e as Map<String, dynamic>))
                          ^^^^
lib/screens/bulk_transfer_screen.dart:121:27: Error: The getter 'Bank' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'Bank'.
              .map((e) => Bank.fromJson(e as Map<String, dynamic>))
                          ^^^^
lib/screens/bulk_transfer_screen.dart:241:19: Error: The method 'ApiService' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'ApiService'.
      final api = ApiService();
                  ^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:312:19: Error: The method 'ApiService' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'ApiService'.
      final api = ApiService();
                  ^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:386:61: Error: The getter 'netSalary' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'netSalary'.
      final hasInvalidAmount = _employees.any((emp) => (emp.netSalary as num) < 100);
                                                            ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:399:19: Error: The method 'ApiService' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'ApiService'.
      final api = ApiService();
                  ^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:415:32: Error: The getter 'SingleTransferResponse' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'SingleTransferResponse'.
        final singleResponse = SingleTransferResponse.fromJson(response.data);
                               ^^^^^^^^^^^^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:433:29: Error: The getter 'netSalary' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'netSalary'.
              'amount': emp.netSalary,
                            ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:434:31: Error: The getter 'bankCode' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'bankCode'.
              'bankCode': emp.bankCode ?? '',
                              ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:435:36: Error: The getter 'bankAccountNumber' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'bankAccountNumber'.
              'accountNumber': emp.bankAccountNumber ?? '',
                                   ^^^^^^^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:436:34: Error: The getter 'name' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'name'.
              'accountName': emp.name,
                                 ^^^^
lib/screens/bulk_transfer_screen.dart:439:14: Error: A value of type 'List<dynamic>' can't be assigned to a variable of type 'List<Map<String, dynamic>>'.
 - 'List' is from 'dart:core'.
 - 'Map' is from 'dart:core'.
          }).toList();
             ^
lib/screens/bulk_transfer_screen.dart:462:30: Error: The getter 'BulkTransferResponse' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'BulkTransferResponse'.
        final bulkResponse = BulkTransferResponse.fromJson(response.data);
                             ^^^^^^^^^^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:486:57: Error: The getter 'netSalary' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'netSalary'.
      return _employees.fold(0, (sum, emp) => sum + emp.netSalary);
                                                        ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:494:29: Error: The getter 'Wallet' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'Wallet'.
    return wallet != null ? Wallet.fromJson(wallet as Map<String, dynamic>) : null;
                            ^^^^^^
lib/screens/bulk_transfer_screen.dart:505:53: Error: Not a constant expression.
            child: CircularProgressIndicator(color: AppColors.primary),
                                                    ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:499:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:737:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:753:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:797:34: Error: 'Employee' isn't a type.
  Widget _employeeTile({required Employee employee}) {
                                 ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:798:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:871:66: Error: Not a constant expression.
                  icon: const Icon(Icons.delete_outlined, color: AppColors.error, size: 20),
                                                                 ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:921:67: Error: Not a constant expression.
                  const Icon(Icons.check_circle, size: 20, color: AppColors.success),
                                                                  ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:926:30: Error: Not a constant expression.
                      color: AppColors.success,
                             ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:846:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:897:50: Error: The getter 'code' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'code'.
                      _banks.firstWhere((b) => b.code == recipient.recipientBank, orElse: () => Bank(code: '', name: 'Select a bank')).name,
                                                 ^^^^
lib/screens/bulk_transfer_screen.dart:897:97: Error: The method 'Bank' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing method, or defining a method named 'Bank'.
                      _banks.firstWhere((b) => b.code == recipient.recipientBank, orElse: () => Bank(code: '', name: 'Select a bank')).name,
                                                                                          ^^^^
lib/screens/bulk_transfer_screen.dart:916:24: Error: The getter 'AppColors' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppColors'.
                color: AppColors.success.withValues(alpha: 0.1),
                       ^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:954:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1010:20: Error: The getter 'AppTheme' isn't defined for the type '_BulkTransferScreenState'.
 - '_BulkTransferScreenState' is from 'package:metroflow_flutter/screens/bulk_transfer_screen.dart' ('lib/screens/bulk_transfer_screen.dart').
Try correcting the name to the name of an existing getter, or defining a getter or field named 'AppTheme'.
    final colors = AppTheme.colors;
                   ^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1076:27: Error: 'ThemeColors' isn't a type.
  Widget _buildEpicPicker(ThemeColors colors) {
                          ^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1174:27: Error: 'ThemeColors' isn't a type.
  Widget _buildBankPicker(ThemeColors colors) {
                          ^^^^^^^^^^^
lib/screens/bulk_transfer_screen.dart:1176:31: Error: The getter 'name' isn't defined for the type 'Object?'.
 - 'Object' is from 'dart:core'.
Try correcting the name to the name of an existing getter, or defining a getter or field named 'name'.
        .where((bank) => bank.name.toLowerCase().contains(_bankSearchQuery.toLowerCase()))
                              ^^^^
lib/screens/bulk_transfer_screen.dart:1292:25: Error: 'ThemeColors' isn't a type.
  Widget _buildOtpModal(ThemeColors colors) {
                        ^^^^^^^^^^^
Unhandled exception:
FileSystemException(uri=org-dartlang-untranslatable-uri:package%3Ametricorex_flutter%2Futils%2Fapp_toast.da
rt; message=StandardFileSystem only supports file:* and data:* URIs)
#0      StandardFileSystem.entityForUri (package:front_end/src/api_prototype/standard_file_system.dart:45)
#1      asFileUri (package:vm/kernel_front_end.dart:1038)
#2      writeDepfile (package:vm/kernel_front_end.dart:1199)
<asynchronous suspension>
#3      FrontendCompiler.compile (package:frontend_server/frontend_server.dart:751)
<asynchronous suspension>
#4      starter (package:frontend_server/starter.dart:102)
<asynchronous suspension>
#5      main (file:///b/s/w/ir/x/w/sdk/pkg/frontend_server/bin/frontend_server_starter.dart:13)
<asynchronous suspension>

Target kernel_snapshot_program failed: Exception


FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':app:compileFlutterBuildRelease'.
> Process 'command '/opt/hostedtoolcache/flutter/stable-3.44.1-x64/flutter/bin/flutter'' finished with non-zero exit value 1

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to generate a Build Scan (Powered by Develocity).
> Get more help at https://help.gradle.org.

BUILD FAILED in 4m 21s
Running Gradle task 'assembleRelease'...                          263.0s
Gradle task assembleRelease failed with exit code 1
Error: Process completed with exit code 1.