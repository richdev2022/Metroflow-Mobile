import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // MARK: - CallKit / PushKit state

  /// Reports incoming calls to the system CallKit UI (full-screen native ring
  /// with Answer/Decline — the iOS equivalent of the Android full-screen call
  /// notification). Without this, an incoming call can only appear as a
  /// banner in the notification panel.
  private var callProvider: CXProvider?
  private var callController: CXCallController?

  /// CXProvider stores its delegate weakly — retain the bridge here or the
  /// Answer/Decline buttons in the native call UI would stop working as soon
  /// as setupCallKit() returns (the temporary would be deallocated).
  private var callKitBridge: CallKitDelegateBridge?
  /// PKPushRegistry stops delivering VoIP pushes once deallocated, and its
  /// `delegate` property is weak too — both MUST be retained for the whole
  /// app lifetime or PushKit never hands us the VoIP token / incoming pushes.
  private var pushRegistry: PKPushRegistry?
  private var pushKitBridge: PushKitDelegateBridge?

  /// callId (backend) -> CallKit call UUID. Lets Dart end the CallKit call
  /// when the in-app UI accepted/ended the same call (and vice versa).
  private var callUuidByCallId: [String: UUID] = [:]

  private var callkitChannel: FlutterMethodChannel?

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

    if let controller = window?.rootViewController as? FlutterViewController {
      // -------------------------------------------------------------------
      // metricorex/audio — call output routing (speaker / earpiece / bluetooth).
      // iOS cannot pick a SPECIFIC bluetooth device from app code, but the
      // speaker override and the "remove override" (→ earpiece / attached BT)
      // routes are fully controllable through AVAudioSession, and the current
      // route can be enumerated for the in-call device sheet.
      // -------------------------------------------------------------------
      let audioChannel = FlutterMethodChannel(
        name: "metricorex/audio", binaryMessenger: controller.binaryMessenger)
      audioChannel.setMethodCallHandler { (call, result) in
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
            // WebRTC (flutter_webrtc) configures .playAndRecord itself once
            // the audio track starts — but the route override below only
            // behaves predictably when the session is already in the
            // voice-chat mode. Re-asserting it here is idempotent.
            try session.setCategory(
              .playAndRecord, mode: .voiceChat,
              options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
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
        case "clearRoute":
          // Call ended — release the session so system audio (music, TTS)
          // works again and the route resets to platform defaults.
          let session = AVAudioSession.sharedInstance()
          try? session.overrideOutputAudioPort(.none)
          try? session.setActive(false, options: [.notifyOthersOnDeactivation])
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // -------------------------------------------------------------------
      // metricorex/callkit — PushKit VoIP token + CallKit answer/decline
      // events. Dart registers the token with the backend; the backend sends
      // the VoIP push; PushKit wakes the app and CallKit shows the native
      // ring UI even when the app is backgrounded or terminated.
      // -------------------------------------------------------------------
      let channel = FlutterMethodChannel(
        name: "metricorex/callkit", binaryMessenger: controller.binaryMessenger)
      self.callkitChannel = channel
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "endCall":
          // Dart accepted/ended this call in-app — the CallKit ring UI must
          // not linger. args: { callId, succeeded(true=answered,false=declined) }
          let args = call.arguments as? [String: Any]
          let callId = args?["callId"] as? String ?? ""
          let answered = (args?["answered"] as? Bool) ?? true
          self.endCallkitCall(callId: callId, answered: answered)
          result(true)
        case "reportConnected":
          let args = call.arguments as? [String: Any]
          let callId = args?["callId"] as? String ?? ""
          self.reportConnected(callId: callId)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      self.setupCallKit()
      self.setupPushKit()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - CallKit

  private func setupCallKit() {
    let config = CXProviderConfiguration(localizedName: "Metricorex")
    config.supportsVideo = true
    config.maximumCallGroups = 2
    config.maximumCallsPerCallGroup = 4
    // Ringtone shown before/while CallKit rings (bundled). CallKit also
    // vibrates by default.
    config.ringtoneSound = "call_ringtone.caf"
    config.includesCallsInRecents = true
    config.supportedHandleTypes = [.generic]
    let provider = CXProvider(configuration: config)
    let controller = CXCallController()
    let bridge = CallKitDelegateBridge(appDelegate: self)
    provider.setDelegate(bridge, queue: nil)
    self.callProvider = provider
    self.callController = controller
    self.callKitBridge = bridge
  }

  private func endCallkitCall(callId: String, answered: Bool) {
    guard let uuid = callUuidByCallId.removeValue(forKey: callId) else { return }
    guard let controller = callController else { return }
    // CXCallObserver exposes no per-UUID lookup — only the `calls` array.
    let call = controller.callObserver.calls.first { $0.uuid == uuid }
    let action: CXEndCallAction
    if answered {
      action = CXEndCallAction(call: uuid)
    } else {
      action = CXEndCallAction(call: uuid)
    }
    _ = call // observer lookup retained for future state-specific handling
    let transaction = CXTransaction(action: action)
    controller.request(transaction) { _ in }
  }

  private func reportConnected(callId: String) {
    // No-op placeholder: CallKit reflects the connected state from the
    // delegate's didBecomeActive — Dart calls endCall when the room closes.
  }

  private func reportIncomingCall(payload: [String: Any]) -> UUID {
    let callId = (payload["callId"] as? String) ?? (payload["call_id"] as? String) ?? ""
    let callerName = (payload["callerName"] as? String) ?? (payload["caller_name"] as? String) ?? "Unknown Caller"
    let callType = (payload["callType"] as? String) ?? (payload["call_type"] as? String) ?? "video"
    let handle = callerName
    let uuid = UUID()

    if !callId.isEmpty {
      callUuidByCallId[callId] = uuid
    }

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.hasVideo = callType.lowercased() != "audio"
    update.localizedCallerName = callerName

    callProvider?.reportNewIncomingCall(
      with: uuid,
      update: update,
      completion: { error in
        if let error = error {
          NSLog("[CallKit] reportNewIncomingCall failed: \(error.localizedDescription)")
        }
      }
    )
    return uuid
  }

  /// Bridges CXProviderDelegate events back to Dart.
  private final class CallKitDelegateBridge: NSObject, CXProviderDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
      self.appDelegate = appDelegate
    }

    func providerDidReset(_ provider: CXProvider) {
      appDelegate?.callUuidByCallId.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
      appDelegate?.forwardToDart("onAnswered", nil)
      action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
      appDelegate?.forwardToDart("onDeclined", nil)
      action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
      // WebRTC owns the session from Dart; activating here keeps the mic
      // alive for the native ring → answer handoff before Flutter attaches.
      try? audioSession.setCategory(
        .playAndRecord, mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
      try? audioSession.setActive(true)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
      try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  private func forwardToDart(_ method: String, _ arguments: Any?) {
    DispatchQueue.main.async {
      self.callkitChannel?.invokeMethod(method, arguments: arguments)
    }
  }

  // MARK: - PushKit (VoIP pushes)

  private func setupPushKit() {
    let registry = PKPushRegistry(queue: .main)
    let bridge = PushKitDelegateBridge(appDelegate: self)
    registry.delegate = bridge
    registry.desiredPushTypes = [.voIP]
    self.pushRegistry = registry
    self.pushKitBridge = bridge
  }

  private final class PushKitDelegateBridge: NSObject, PKPushRegistryDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
      self.appDelegate = appDelegate
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
      guard type == .voIP else { return }
      let tokenData = credentials.token
      let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
      NSLog("[PushKit] voip token received (\(tokenString.prefix(12))…)")
      appDelegate?.forwardToDart("onVoipToken", ["token": tokenString])
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
      appDelegate?.forwardToDart("onVoipTokenInvalidated", nil)
    }

    /// MANDATORY: a VoIP push MUST be reported to CallKit immediately —
    /// Apple kills the PushKit entitlement for apps that don't.
    func pushRegistry(_ registry: PKPushRegistry, didReceive incomingPush: PKPushPayload, for type: PKPushType) {
      guard type == .voIP, let payload = incomingPush.dictionaryPayload as? [String: Any] else { return }
      NSLog("[PushKit] voip push received: \(payload.keys.joined(separator: ","))")
      appDelegate?.reportIncomingCall(payload: payload)
      appDelegate?.forwardToDart("onIncomingCall", payload)
    }
  }
}
