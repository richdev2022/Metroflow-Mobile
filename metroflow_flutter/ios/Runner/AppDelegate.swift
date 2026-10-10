import AVFoundation
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

    // ---------------------------------------------------------------------
    // metricorex/audio — call output routing (speaker / earpiece / bluetooth).
    // iOS cannot pick a SPECIFIC bluetooth device from app code, but the
    // speaker override and the "remove override" (→ earpiece / attached BT)
    // routes are fully controllable through AVAudioSession, and the current
    // route can be enumerated for the in-call device sheet.
    // ---------------------------------------------------------------------
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "metricorex/audio", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "listOutputs":
          let session = AVAudioSession.sharedInstance()
          let outputs = session.currentRoute.outputs.map { port -> [String: Any] in
            let t = port.portType
            let isBT = t == .bluetoothHFP || t == .bluetoothA2DP || t == .bluetoothLE
            return [
              "id": port.uid,
              "productName": port.portName,
              "type": isBT ? "bluetooth" : (t == .builtInSpeaker ? "speaker" : (t == .builtInReceiver ? "earpiece" : "other")),
              "isBluetooth": isBT,
            ]
          }
          result(outputs)
        case "setRoute":
          let route = (call.arguments as? [String: Any])?["route"] as? String ?? "speaker"
          do {
            let session = AVAudioSession.sharedInstance()
            switch route {
            case "speaker":
              try session.overrideOutputAudioPort(.speaker)
            case "earpiece", "bluetooth":
              // Removing the override lets the OS pick the default
              // communication output: earpiece, or the attached BT headset.
              try session.overrideOutputAudioPort(.none)
            default:
              try session.overrideOutputAudioPort(.none)
            }
            result(true)
          } catch {
            result(FlutterError(code: "audio_route_failed",
                                message: "Failed to set audio route: \(error.localizedDescription)",
                                details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
