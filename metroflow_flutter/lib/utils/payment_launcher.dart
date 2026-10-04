import 'payment_launcher_stub.dart'
    if (dart.library.html) 'payment_launcher_web.dart';

Future<bool> openExternalPaymentUrl(String url) => openExternalUrl(url);
