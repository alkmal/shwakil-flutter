import Flutter
import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, MessagingDelegate {
  private let referralChannelName = "com.alkmal.shwakil/referrals"
  private var initialReferralCode: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let launchUrl = launchOptions?[.url] as? URL {
      initialReferralCode = Self.extractReferralCode(from: launchUrl)
    }

    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    application.registerForRemoteNotifications()

    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: referralChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "getInitialReferralPayload":
          result([
            "urlCode": self?.initialReferralCode as Any,
          ])
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return didFinish
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

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    initialReferralCode = Self.extractReferralCode(from: url)
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      initialReferralCode = Self.extractReferralCode(from: url)
    }

    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private static func extractReferralCode(from url: URL) -> String? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }

    let names = ["ref", "referral", "code", "referralPhone"]
    for name in names {
      if let value = components.queryItems?.first(where: { $0.name == name })?.value,
         let sanitized = sanitizeReferralCode(value) {
        return sanitized
      }
    }

    if url.scheme == "shwakil", url.host == "invite" {
      for name in ["ref", "referral", "code"] {
        if let value = components.queryItems?.first(where: { $0.name == name })?.value,
           let sanitized = sanitizeReferralCode(value) {
          return sanitized
        }
      }
    }

    return nil
  }

  private static func sanitizeReferralCode(_ value: String?) -> String? {
    let normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.count <= 64 else {
      return nil
    }

    let invalidCharacters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "/?#&"))
    if normalized.rangeOfCharacter(from: invalidCharacters) != nil {
      return nil
    }

    return normalized
  }
}
