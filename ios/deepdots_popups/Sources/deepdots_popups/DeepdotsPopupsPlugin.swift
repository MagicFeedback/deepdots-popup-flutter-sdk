import DeepdotsSDK
import Flutter
import UIKit

/// Puente Flutter -> SDK nativo KMP. No reimplementa nada: traduce las llamadas del canal a la
/// API pública de `DeepdotsPopups` y reenvía los eventos del SDK a Dart.
public class DeepdotsPopupsPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var sdk: DeepdotsSDK.DeepdotsPopups?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.deepdots/popups", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DeepdotsPopupsPlugin(channel: channel), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "init" {
      initialize(args)
      return result(nil)
    }
    guard let sdk = sdk else {
      return result(FlutterError(code: "not_initialized", message: "Call DeepdotsPopups.init() first", details: nil))
    }
    switch call.method {
    case "setPath":
      attachTopViewController()
      sdk.setPath(path: args["path"] as? String)
    case "triggerEvent":
      attachTopViewController()
      sdk.triggerEvent(eventName: args["name"] as! String)
    case "track":
      sdk.track(name: args["name"] as! String, params: args["params"] as? [String: Any])
    case "setUserId":
      sdk.setUserId(userId: args["userId"] as? String)
    case "setTrackingEnabled":
      sdk.setTrackingEnabled(enabled: args["enabled"] as! Bool)
    case "onForeground":
      sdk.onForeground()
    case "onBackground":
      sdk.onBackground()
    case "getUserId":
      return result(sdk.getUserId())
    case "getSessionId":
      return result(sdk.getSessionId())
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }

  private func initialize(_ args: [String: Any]) {
    if sdk != nil { return } // init() es idempotente, igual que en el SDK nativo
    let language = args["language"] as? String
    var analytics: AnalyticsKeys?
    if let key = args["analyticsPublicKey"] as? String, let integration = args["analyticsIntegration"] as? String {
      analytics = AnalyticsKeys(publicKey: key, integration: integration)
    }
    var metadata: [String: Any]?
    if let userId = args["userId"] as? String { metadata = ["userId": userId] }

    // Kotlin no exporta los valores por defecto a Swift: hay que pasar todos los parámetros.
    let options = InitOptions(
      debug: KotlinBoolean(bool: args["debug"] as? Bool ?? false),
      environment: (args["environment"] as? String) == "development" ? Environment.development : Environment.production,
      mode: Mode.server,
      popupOptions: PopupOptions(id: nil, publicKey: args["publicKey"] as? String, popups: nil, companyId: nil),
      provideLang: { language },
      autoLaunch: KotlinBoolean(bool: true),
      storage: nil,
      trackingEnabled: KotlinBoolean(bool: args["trackingEnabled"] as? Bool ?? true),
      analytics: analytics,
      geolocation: nil,
      contactAttributes: nil,
      renderChrome: nil,
      showProgressBar: nil,
      metadata: metadata
    )
    let instance = DeepdotsSDK.DeepdotsPopups()
    instance.initialize(options: options)
    for event in Event.entries {
      instance.on(event: event) { [weak self] data in self?.emit(event, data) }
    }
    sdk = instance
    attachTopViewController()
  }

  private func emit(_ event: Event, _ data: EventData) {
    let payload: [String: Any] = [
      "type": event.code(),
      "popupId": data.popupId,
      "surveyId": data.surveyId,
      "productId": data.productId,
    ]
    DispatchQueue.main.async { self.channel.invokeMethod("onEvent", arguments: payload) }
  }

  /// El SDK presenta el popup desde el root view controller (en Flutter, el
  /// `FlutterViewController`). Se refresca antes de cada trigger porque en `init()` la ventana
  /// puede no existir todavía. No se sube por `presentedViewController`: con un popup abierto
  /// ese sería el propio popup, y presentar desde él rompería el siguiente.
  /// Limitación conocida: si el host tiene un VC nativo presentado (un picker, un share sheet),
  /// UIKit no deja presentar encima y el popup no sale.
  private func attachTopViewController() {
    let root = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    guard let root = root else { return }
    sdk?.attachContext(context: PlatformContext(viewController: root))
  }
}
