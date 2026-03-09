import AVFAudio
import CallKit
import FirebaseMessaging
import Flutter
import PushKit
import UIKit

private enum IOSCallStoreKey {
  static let voipToken = "teacherhub.ios.voipToken"
  static let pendingIncoming = "teacherhub.ios.pendingIncomingCall"
  static let pendingAnswer = "teacherhub.ios.pendingCallAnswer"
  static let pendingDecline = "teacherhub.ios.pendingCallDecline"
  static let launchPayload = "teacherhub.ios.launchPayload"
  static let activeCall = "teacherhub.ios.activeCall"
  static let activeCallUuid = "teacherhub.ios.activeCallUuid"
}

private final class IOSCallStateStore {
  static let shared = IOSCallStateStore()

  private let defaults = UserDefaults.standard

  var voipToken: String? {
    get { defaults.string(forKey: IOSCallStoreKey.voipToken) }
    set {
      if let token = newValue, !token.isEmpty {
        defaults.set(token, forKey: IOSCallStoreKey.voipToken)
      } else {
        defaults.removeObject(forKey: IOSCallStoreKey.voipToken)
      }
    }
  }

  func savePendingIncomingCall(_ payload: [String: String], uuid: UUID) {
    saveMap(payload, forKey: IOSCallStoreKey.pendingIncoming)
    saveMap(payload, forKey: IOSCallStoreKey.activeCall)
    defaults.set(uuid.uuidString, forKey: IOSCallStoreKey.activeCallUuid)
    saveLaunchPayload(payload)
  }

  func consumePendingIncomingCall() -> [String: String]? {
    let payload = map(forKey: IOSCallStoreKey.pendingIncoming)
    defaults.removeObject(forKey: IOSCallStoreKey.pendingIncoming)
    return payload
  }

  func savePendingAnswer(_ payload: [String: String]) {
    saveMap(payload, forKey: IOSCallStoreKey.pendingAnswer)
    saveLaunchPayload(payload)
  }

  func consumePendingAnswer() -> [String: String]? {
    let payload = map(forKey: IOSCallStoreKey.pendingAnswer)
    defaults.removeObject(forKey: IOSCallStoreKey.pendingAnswer)
    return payload
  }

  func savePendingDecline(_ invitationId: String) {
    defaults.set(invitationId, forKey: IOSCallStoreKey.pendingDecline)
  }

  func consumePendingDecline() -> String? {
    let invitationId = defaults.string(forKey: IOSCallStoreKey.pendingDecline)
    defaults.removeObject(forKey: IOSCallStoreKey.pendingDecline)
    return invitationId
  }

  func saveLaunchPayload(_ payload: [String: String]) {
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
      let encoded = String(data: data, encoding: .utf8)
    else { return }
    defaults.set(encoded, forKey: IOSCallStoreKey.launchPayload)
  }

  func consumeLaunchPayload() -> String? {
    let payload = defaults.string(forKey: IOSCallStoreKey.launchPayload)
    defaults.removeObject(forKey: IOSCallStoreKey.launchPayload)
    return payload
  }

  func currentActiveCall() -> [String: String]? {
    map(forKey: IOSCallStoreKey.activeCall)
  }

  func currentActiveCallUuid() -> UUID? {
    guard let value = defaults.string(forKey: IOSCallStoreKey.activeCallUuid) else {
      return nil
    }
    return UUID(uuidString: value)
  }

  func clearActiveCall() {
    defaults.removeObject(forKey: IOSCallStoreKey.activeCall)
    defaults.removeObject(forKey: IOSCallStoreKey.activeCallUuid)
  }

  private func saveMap(_ payload: [String: String], forKey key: String) {
    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
      let encoded = String(data: data, encoding: .utf8)
    else { return }
    defaults.set(encoded, forKey: key)
  }

  private func map(forKey key: String) -> [String: String]? {
    guard
      let encoded = defaults.string(forKey: key),
      let data = encoded.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data, options: []),
      let dict = object as? [String: Any]
    else { return nil }
    return dict.reduce(into: [String: String]()) { partialResult, entry in
      partialResult[entry.key] = String(describing: entry.value)
    }
  }
}

private final class IOSCallKitManager: NSObject, CXProviderDelegate {
  static let shared = IOSCallKitManager()

  private let provider: CXProvider
  private let callController = CXCallController()
  private let store = IOSCallStateStore.shared
  private var answeredInvitationId: String?

  private override init() {
    let config = CXProviderConfiguration(localizedName: "Teacher Hub")
    config.supportedHandleTypes = [.generic]
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    config.includesCallsInRecents = false
    config.iconTemplateImageData = nil
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  @discardableResult
  func reportIncomingCall(payload: [String: String]) -> Bool {
    guard
      let invitationId = payload["invitationId"], !invitationId.isEmpty,
      let channelId = payload["channelId"], !channelId.isEmpty
    else {
      return false
    }
    if let active = store.currentActiveCall(),
       active["invitationId"] == invitationId,
       store.currentActiveCallUuid() != nil {
      return true
    }
    let uuid = UUID()
    let update = CXCallUpdate()
    let callerName = payload["fromUserName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = (callerName?.isEmpty == false ? callerName! : "对方")
    update.localizedCallerName = displayName
    update.remoteHandle = CXHandle(type: .generic, value: displayName)
    update.hasVideo = payload["callType"] == "video"
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false

    var normalized = payload
    normalized["invitationId"] = invitationId
    normalized["channelId"] = channelId
    normalized["fromUserName"] = displayName
    normalized["uuid"] = uuid.uuidString
    store.savePendingIncomingCall(normalized, uuid: uuid)

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if error != nil {
        self?.store.clearActiveCall()
      }
    }
    return true
  }

  @discardableResult
  func dismissIncomingCall() -> Bool {
    guard let uuid = store.currentActiveCallUuid() else { return false }
    provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    answeredInvitationId = nil
    store.clearActiveCall()
    return true
  }

  func providerDidReset(_ provider: CXProvider) {
    answeredInvitationId = nil
    store.clearActiveCall()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let payload = store.currentActiveCall() else {
      action.fail()
      return
    }
    answeredInvitationId = payload["invitationId"]
    configureAudioSession()
    store.savePendingAnswer(payload)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    if let payload = store.currentActiveCall(),
       let invitationId = payload["invitationId"],
       answeredInvitationId != invitationId {
      store.savePendingDecline(invitationId)
    }
    answeredInvitationId = nil
    store.clearActiveCall()
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    try? audioSession.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
    )
    try? audioSession.setActive(true)
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    try? audioSession.setActive(false)
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
    )
    try? session.setActive(true)
  }
}

private final class IOSVoIPPushManager: NSObject, PKPushRegistryDelegate {
  static let shared = IOSVoIPPushManager()

  private let store = IOSCallStateStore.shared
  private var registry: PKPushRegistry?

  func start() {
    guard registry == nil else { return }
    let newRegistry = PKPushRegistry(queue: DispatchQueue.main)
    newRegistry.delegate = self
    newRegistry.desiredPushTypes = [.voIP]
    registry = newRegistry
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    store.voipToken = token
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    store.voipToken = nil
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    handleIncomingPush(payload.dictionaryPayload)
  }

  @available(iOS 11.0, *)
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    handleIncomingPush(payload.dictionaryPayload)
    completion()
  }

  private func handleIncomingPush(_ payload: [AnyHashable: Any]) {
    guard let normalized = normalizePayload(payload) else { return }
    _ = IOSCallKitManager.shared.reportIncomingCall(payload: normalized)
  }

  private func normalizePayload(_ payload: [AnyHashable: Any]) -> [String: String]? {
    func readValue(_ key: String, from dict: [AnyHashable: Any]) -> String? {
      if let value = dict[key] {
        let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
      }
      return nil
    }

    var source = payload
    if let callData = payload["callData"] as? [AnyHashable: Any] {
      source = callData
    }

    let messageType = readValue("messageType", from: source) ??
      readValue("message_type", from: source) ??
      readValue("messageType", from: payload)
    guard messageType == "call_invitation" else { return nil }

    guard
      let invitationId = readValue("invitationId", from: source) ?? readValue("invitationId", from: payload),
      let channelId = readValue("channelId", from: source) ?? readValue("channelId", from: payload)
    else {
      return nil
    }

    return [
      "messageType": "call_invitation",
      "invitationId": invitationId,
      "channelId": channelId,
      "callType": readValue("callType", from: source) ??
        readValue("callType", from: payload) ??
        "voice",
      "fromUserName": readValue("fromUserName", from: source) ??
        readValue("fromUserName", from: payload) ??
        "对方",
      "fromAvatarUrl": readValue("fromAvatarUrl", from: source) ??
        readValue("fromAvatarUrl", from: payload) ??
        "",
    ]
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let launchChannelName = "com.example.teacher_hub/launch"
  private let callChannelName = "teacherhub.call"
  private var channelsConfigured = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    IOSVoIPPushManager.shared.start()
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureFlutterChannelsIfNeeded()
    return launched
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureFlutterChannelsIfNeeded()
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  private func configureFlutterChannelsIfNeeded() {
    guard !channelsConfigured,
          let controller = currentFlutterViewController() else {
      return
    }
    channelsConfigured = true

    let launchChannel = FlutterMethodChannel(
      name: launchChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    launchChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getLaunchPayload":
        result(IOSCallStateStore.shared.consumeLaunchPayload())
      case "canUseFullScreenIntent":
        result(true)
      case "openFullScreenIntentSettings":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let callChannel = FlutterMethodChannel(
      name: callChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    callChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "showIncomingCall":
        let args = call.arguments as? [String: Any] ?? [:]
        let caller = String(describing: args["caller"] ?? "对方")
        let invitationId = String(describing: args["invitationId"] ?? "")
        let channelId = String(describing: args["channelId"] ?? "")
        let callType = String(describing: args["callType"] ?? "voice")
        let payload = [
          "messageType": "call_invitation",
          "invitationId": invitationId,
          "channelId": channelId,
          "callType": callType,
          "fromUserName": caller,
        ]
        result(IOSCallKitManager.shared.reportIncomingCall(payload: payload))
      case "getPendingIncomingCall":
        result(IOSCallStateStore.shared.consumePendingIncomingCall())
      case "getPendingCallAnswer":
        result(IOSCallStateStore.shared.consumePendingAnswer())
      case "getPendingCallDecline":
        result(IOSCallStateStore.shared.consumePendingDecline())
      case "getVoipToken":
        result(IOSCallStateStore.shared.voipToken)
      case "dismissIncomingCall":
        result(IOSCallKitManager.shared.dismissIncomingCall())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func currentFlutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for candidate in windowScene.windows {
        if let controller = candidate.rootViewController as? FlutterViewController {
          return controller
        }
      }
    }
    return nil
  }
}
