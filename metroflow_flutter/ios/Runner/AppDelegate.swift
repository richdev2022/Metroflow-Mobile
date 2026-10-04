import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // REGISTER FOR REMOTE NOTIFICATIONS (APNs). HISTORY: this call was
    // missing, so iOS never obtained an APNs device token — the app did not
    // even appear under Settings → Notifications and FCM could not deliver
    // anything (push notifications, incoming-call rings, chat alerts).
    // With Firebase's default swizzling (FirebaseAppDelegateProxyEnabled),
    // the token is forwarded to Firebase Messaging automatically once the
    // GoogleService-Info.plist config is present in ios/Runner/.
    // Registering is idempotent and safe to call on every launch; when the
    // user has not granted the notification permission yet it is a no-op
    // until the permission prompt (fired from the Dart side on first launch)
    // is answered.
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
