import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NordlyLab") {
      NordlyLab.register(messenger: registrar.messenger())
    }
  }
}

/// `nordly/lab` (lib/lab.dart): the run's launch arguments (Maestro `launchApp: arguments`,
/// `-key value`, `key value` or `key=value`) and the saved run config.
enum NordlyLab {
  private static let keys = ["scenario", "nav", "lang", "load", "user", "start"]
  private static let defaults = UserDefaults(suiteName: "lab")!

  static func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "nordly/lab", binaryMessenger: messenger).setMethodCallHandler { call, result in
      switch call.method {
      case "launchArguments":
        result(launchArguments(ProcessInfo.processInfo.arguments))
      case "load":
        result(defaults.dictionaryRepresentation().compactMapValues { $0 as? String }
          .filter { keys.contains($0.key) || $0.key == "consent" })
      case "save":
        (call.arguments as? [String: String])?.forEach { defaults.set($0.value, forKey: $0.key) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func launchArguments(_ arguments: [String]) -> [String: String] {
    var args: [String: String] = [:]
    var i = 1
    while i < arguments.count {
      let raw = arguments[i]
      let key = raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
      if let eq = key.firstIndex(of: "="), keys.contains(String(key[..<eq])) {
        args[String(key[..<eq])] = String(key[key.index(after: eq)...])
      } else if keys.contains(key), i + 1 < arguments.count {
        args[key] = arguments[i + 1]
        i += 1
      }
      i += 1
    }
    return args
  }
}
