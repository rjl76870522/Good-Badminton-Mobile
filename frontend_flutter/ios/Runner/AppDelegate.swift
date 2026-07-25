import Flutter
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let deviceIdentityChannel = "good_badminton/device_identity"
  private let guestUserIdAccount = "stable_guest_user_id"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    let launchResult = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      registerDeviceIdentityChannel(binaryMessenger: controller.binaryMessenger)
    }
    return launchResult
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func stableGuestUserId() -> String {
    if let stored = readKeychainValue(account: guestUserIdAccount), !stored.isEmpty {
      return stored
    }
    let generated = "guest_device_ios_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    saveKeychainValue(generated, account: guestUserIdAccount)
    return generated
  }

  private func registerDeviceIdentityChannel(binaryMessenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(
      name: deviceIdentityChannel,
      binaryMessenger: binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard call.method == "stableGuestUserId" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.stableGuestUserId())
    }
  }

  private func keychainService() -> String {
    Bundle.main.bundleIdentifier ?? "com.rundon2026.goodbadminton"
  }

  private func readKeychainValue(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService(),
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data,
          let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return value
  }

  private func saveKeychainValue(_ value: String, account: String) {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService(),
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(attributes as CFDictionary, nil)
  }
}
