import DeepdotsSDK
import Flutter
import UIKit

/// Puente Flutter -> SDK nativo KMP. No reimplementa nada: traduce las llamadas del canal a la
/// API pública de `DeepdotsPopups` y reenvía los eventos del SDK a Dart.
public class DeepdotsPopupsPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var sdk: DeepdotsSDK.DeepdotsPopups?
  // Lo que devuelve `provideLang`. El SDK nativo lo vuelve a leer cada vez que pinta un popup,
  // así que `setLanguage` lo cambia en caliente.
  private var language: String?

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
    if call.method == "setLanguage" {
      // Funciona también antes de init(): solo cambia lo que devolverá `provideLang`.
      language = args["language"] as? String
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
    case "onScroll":
      attachTopViewController() // el scroll puede mostrar un popup en el acto
      sdk.onScroll(percentage: Int32(args["percentage"] as! Int))
    case "onExit":
      attachTopViewController()
      sdk.onExit()
    case "track":
      sdk.track(name: args["name"] as! String, params: kotlinMap(args["params"]))
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
    case "getFeedbackSessionId":
      return result(sdk.getFeedbackSessionId())
    // ───────── Analytics ─────────
    case "setUserAttributes":
      sdk.setUserAttributes(attributes: kotlinMap(args["attributes"]) ?? [:])
    case "setContactAttributes":
      return setContactAttributes(sdk, args, result)
    case "setMetric":
      sdk.setMetric(key: args["key"] as! String, value: kotlinValue(args["value"]))
    case "reportError":
      reportError(sdk, args)
    case "endSession":
      sdk.endSession()
    case "flushAnalytics":
      // Kotlin no exporta el valor por defecto: este es el `AnalyticsFlushMeta()` de nativo.
      sdk.flushAnalytics(meta: AnalyticsFlushMeta(final: false, sessionEnd: false))
    case "trackSearch":
      sdk.trackSearch(
        query: args["query"] as! String,
        resultsCount: (args["resultsCount"] as! NSNumber).int32Value,
        params: kotlinMap(args["params"])
      )
    case "trackFindabilityFriction":
      sdk.trackFindabilityFriction(frictionTopic: args["frictionTopic"] as! String, params: kotlinMap(args["params"]))
    case "trackFunnelStep":
      sdk.trackFunnelStep(
        funnel: args["funnel"] as! String,
        step: args["step"] as! String,
        taskId: args["taskId"] as! String,
        params: kotlinMap(args["params"])
      )
    case "trackMeaningfulInteraction":
      sdk.trackMeaningfulInteraction(interactionType: args["interactionType"] as! String, params: kotlinMap(args["params"]))
    case "trackMessage":
      sdk.trackMessage(
        stage: args["stage"] as! String,
        id: args["id"] as! String,
        title: args["title"] as! String,
        channel: args["channel"] as! String,
        campaign: args["campaign"] as? String,
        value: (args["value"] as? NSNumber).map { KotlinDouble(value: $0.doubleValue) },
        currency: args["currency"] as? String,
        params: kotlinMap(args["params"])
      )
    case "enterMiniService":
      sdk.enterMiniService(name: args["name"] as! String, entryPointType: args["entryPointType"] as? String)
    case "exitMiniService":
      sdk.exitMiniService(name: args["name"] as! String)

    // Control manual de popups
    case "show":
      guard let context = platformContext(result) else { return }
      let options = ShowOptions(
        surveyId: args["surveyId"] as! String,
        productId: args["productId"] as! String,
        data: (args["data"] as? [String: Any])?.filter { !($0.value is NSNull) }
      )
      sdk.show(options: options, context: context)
    case "showByPopupId":
      guard let context = platformContext(result) else { return }
      sdk.showByPopupId(popupId: args["popupId"] as! String, context: context)
    case "triggerSurvey":
      guard let context = platformContext(result) else { return }
      sdk.triggerSurvey(surveyId: args["surveyId"] as! String, context: context, popupId: args["popupId"] as? String)
    case "close":
      guard let context = platformContext(result) else { return }
      sdk.close(context: context)
    case "markSurveyAnswered":
      sdk.markSurveyAnswered(surveyId: args["surveyId"] as! String)
    case "triggerClick":
      attachTopViewController()
      sdk.triggerClick(targetId: args["targetId"] as! String)
    default:
      return result(FlutterMethodNotImplemented)
    }
    result(nil)
  }

  private func initialize(_ args: [String: Any]) {
    if sdk != nil { return } // init() es idempotente, igual que en el SDK nativo
    if let initial = args["language"] as? String { language = initial } // valor inicial de setLanguage()
    var analytics: AnalyticsKeys?
    if let key = args["analyticsPublicKey"] as? String, let integration = args["analyticsIntegration"] as? String {
      analytics = AnalyticsKeys(publicKey: key, integration: integration)
    }
    // `metadata` libre del host + `userId`, que gana. El SDK no admite valores nulos.
    var metadata = (args["metadata"] as? [String: Any])?.filter { !($0.value is NSNull) } ?? [:]
    if let userId = args["userId"] as? String { metadata["userId"] = userId }

    // Kotlin no exporta los valores por defecto a Swift: hay que pasar todos los parámetros.
    let options = InitOptions(
      debug: KotlinBoolean(bool: args["debug"] as? Bool ?? false),
      environment: (args["environment"] as? String) == "development" ? Environment.development : Environment.production,
      mode: Mode.server,
      popupOptions: PopupOptions(id: nil, publicKey: args["publicKey"] as? String, popups: nil, companyId: nil),
      provideLang: { [weak self] in self?.language },
      autoLaunch: KotlinBoolean(bool: true),
      storage: nil,
      trackingEnabled: KotlinBoolean(bool: args["trackingEnabled"] as? Bool ?? true),
      analytics: analytics,
      onFeedbackSession: { [weak self] session in self?.emitFeedbackSession(session) },
      geolocation: KotlinBoolean(bool: args["geolocation"] as? Bool ?? true),
      contactAttributes: kotlinMap(args["contactAttributes"]),
      renderChrome: (args["renderChrome"] as? Bool).map { KotlinBoolean(bool: $0) },
      showProgressBar: (args["showProgressBar"] as? Bool).map { KotlinBoolean(bool: $0) },
      metadata: metadata.isEmpty ? nil : metadata
    )
    let instance = DeepdotsSDK.DeepdotsPopups()
    instance.initialize(options: options)
    for event in Event.entries {
      instance.on(event: event) { [weak self] data in self?.emit(event, data) }
    }
    sdk = instance
    attachTopViewController()
  }

  // ───────── Analytics ─────────

  /// `setContactAttributes` es `suspend` en Kotlin: en Swift llega con completion handler, que
  /// puede volver en cualquier hilo; el `FlutterResult` se completa en el principal.
  private func setContactAttributes(_ sdk: DeepdotsSDK.DeepdotsPopups, _ args: [String: Any], _ result: @escaping FlutterResult) {
    sdk.setContactAttributes(attributes: kotlinMap(args["attributes"]) ?? [:]) { sent, error in
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "set_contact_attributes_failed", message: error.localizedDescription, details: nil))
        } else {
          result(sent?.boolValue ?? false)
        }
      }
    }
  }

  /// `reportError` pide un `Throwable` de Kotlin. Desde Swift no se puede fijar su pila (Kotlin
  /// la captura al construirlo y `stackTraceToString()` no se puede sobrescribir), así que la de
  /// Dart viaja en `context` como `dart_stack`, junto al tipo (`dart_error_type`). El
  /// `crash_type` nativo será el de la clase (`Throwable`) y el `stack`, el del puente.
  private func reportError(_ sdk: DeepdotsSDK.DeepdotsPopups, _ args: [String: Any]) {
    var context = kotlinMap(args["context"]) ?? [:]
    context["dart_error_type"] = args["errorType"] as? String
    if let stack = args["stack"] as? String { context["dart_stack"] = stack }
    sdk.reportError(
      error: KotlinThrowable(message: args["message"] as? String ?? ""),
      severity: args["severity"] as? String ?? "error",
      handled: args["handled"] as? Bool ?? true,
      context: context
    )
  }

  /// Un `NSNumber` del canal no llega a Kotlin como `Boolean`/`Long`/`Double`, así que el SDK lo
  /// trataría como texto (`true` acabaría como "1"). Se convierte a las cajas de Kotlin, para
  /// que el resultado sea el mismo que en Android. `NSNull` (un `null` de Dart) pasa a `nil`
  /// en un valor suelto; dentro de un mapa o una lista se queda como `NSNull`, que Kotlin/Native
  /// lee como `null` en las colecciones.
  private func kotlinValue(_ value: Any?) -> Any? {
    switch value {
    case nil, is NSNull:
      return nil
    case let number as NSNumber:
      if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() { return KotlinBoolean(bool: number.boolValue) }
      if CFNumberIsFloatType(number as CFNumber) { return KotlinDouble(value: number.doubleValue) }
      return KotlinLong(value: number.int64Value)
    case let map as [String: Any]:
      return kotlinMap(map)
    case let list as [Any]:
      return list.map { kotlinValue($0) ?? NSNull() }
    default:
      return value
    }
  }

  /// Mapa del canal con los valores convertidos por [kotlinValue].
  private func kotlinMap(_ value: Any?) -> [String: Any]? {
    guard let map = value as? [String: Any] else { return nil }
    return map.mapValues { kotlinValue($0) ?? NSNull() }
  }

  /// Llega desde un hilo de fondo del SDK: el canal se usa en el principal.
  private func emitFeedbackSession(_ session: FeedbackSession) {
    let payload: [String: Any] = [
      "sessionId": session.sessionId,
      "status": session.status == FeedbackSessionStatus.closed ? "closed" : "open",
    ]
    DispatchQueue.main.async { self.channel.invokeMethod("onFeedbackSession", arguments: payload) }
  }

  private func emit(_ event: Event, _ data: EventData) {
    let payload: [String: Any] = [
      "type": event.code(),
      "popupId": data.popupId,
      "surveyId": data.surveyId,
      "productId": data.productId,
      "extra": channelSafe(data.extra),
      "timestamp": data.timestamp,
    ]
    DispatchQueue.main.async { self.channel.invokeMethod("onEvent", arguments: payload) }
  }

  /// El `extra` de los eventos sale del JSON del survey (texto, números, booleanos, listas y
  /// mapas), pero el tipo es `Any`: lo que el códec del canal no sepa serializar va como texto.
  /// Los números y booleanos de Kotlin llegan como subclases de `NSNumber`.
  private func channelSafe(_ value: Any) -> Any {
    switch value {
    case is NSNull, is String, is NSNumber:
      return value
    case let map as [AnyHashable: Any]:
      return Dictionary(uniqueKeysWithValues: map.map { ("\($0.key)", channelSafe($0.value)) })
    case let list as [Any]:
      return list.map { channelSafe($0) }
    default:
      return String(describing: value)
    }
  }

  /// Contexto para los métodos que pintan o cierran un popup; sin root view controller, error
  /// a Dart. Misma búsqueda que `attachTopViewController`.
  private func platformContext(_ result: FlutterResult) -> PlatformContext? {
    let root = rootViewController()
    guard let root = root else {
      result(FlutterError(code: "no_context", message: "No root view controller yet: cannot show or close popups", details: nil))
      return nil
    }
    return PlatformContext(viewController: root)
  }

  /// Root view controller de la ventana principal. `UIWindowScene.keyWindow` es de iOS 15.
  private func rootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { scene in (scene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
      .first?.rootViewController
  }

  /// El contexto es el root view controller (en Flutter, el `FlutterViewController`). Se refresca
  /// antes de cada trigger porque en `init()` la ventana puede no existir todavía. No se sube por
  /// `presentedViewController`: desde 0.7.2 el SDK presenta desde lo alto de la cadena de
  /// presentados (sheets del host incluidas) y espera si hay una alerta encima.
  private func attachTopViewController() {
    let root = rootViewController()
    guard let root = root else { return }
    sdk?.attachContext(context: PlatformContext(viewController: root))
  }
}
