/// Deepdots popups para Flutter: envoltorio fino sobre el SDK nativo (KMP) de Android e iOS.
///
/// Toda la lógica (triggers, segmentación, sesión, analytics, render del survey) vive en el
/// SDK nativo. Este paquete solo la expone a Dart y conecta la navegación y el ciclo de vida
/// de Flutter, para que el host no tenga que instrumentarlos a mano.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/version.dart';

enum DeepdotsEnvironment { production, development }

/// Evento del SDK nativo (`popup_shown`, `popup_clicked`, `survey_completed`).
class DeepdotsEvent {
  const DeepdotsEvent({
    required this.type,
    required this.popupId,
    required this.surveyId,
    required this.productId,
    this.extra = const {},
    this.timestamp,
  });

  final String type;
  final String popupId;
  final String surveyId;
  final String productId;

  /// Datos extra del evento nativo (`EventData.extra`), p. ej. `action` en `popup_clicked` o
  /// el `data` de [DeepdotsPopups.show] en `popup_shown`. Vacío si el evento no trae nada.
  final Map<String, Object?> extra;

  /// Momento en que el SDK nativo emitió el evento (`EventData.timestamp`).
  final DateTime? timestamp;

  @override
  String toString() => 'DeepdotsEvent($type, popup=$popupId, survey=$surveyId)';
}

/// Sesión de analytics tal como la ve la API de Deepdots: cada sesión acaba siendo UN feedback y
/// [sessionId] es su `sdkSessionId`. Llega por [DeepdotsPopups.feedbackSessions].
class DeepdotsFeedbackSession {
  const DeepdotsFeedbackSession(
      {required this.sessionId, required this.closed});

  final String sessionId;

  /// `false` cuando la API acepta el primer lote de la sesión; `true` cuando acepta el de cierre.
  final bool closed;

  @override
  String toString() =>
      'DeepdotsFeedbackSession($sessionId, ${closed ? 'closed' : 'open'})';
}

class DeepdotsPopups {
  DeepdotsPopups._();

  static const MethodChannel _channel = MethodChannel('com.deepdots/popups');
  static final StreamController<DeepdotsEvent> _events =
      StreamController.broadcast();
  static final StreamController<DeepdotsFeedbackSession> _feedbackSessions =
      StreamController.broadcast();
  static AppLifecycleListener? _lifecycle;
  static bool _initialized = false;
  static String? _pendingPath;

  /// Eventos de los popups, para analítica propia del host o para reaccionar en la UI.
  static Stream<DeepdotsEvent> get events => _events.stream;

  /// Apertura y cierre de cada sesión de analytics (`onFeedbackSession` nativo; necesita
  /// `analyticsPublicKey`). Agrupa por `sessionId`, no por orden: el `open` de la siguiente sesión
  /// puede llegar antes que el `closed` de la anterior. Si la app muere antes de cerrar, el
  /// `closed` no llega.
  static Stream<DeepdotsFeedbackSession> get feedbackSessions =>
      _feedbackSessions.stream;

  /// Inicializa el SDK nativo. Idempotente: una segunda llamada no hace nada.
  ///
  /// - [language]: idioma inicial; se cambia después con [setLanguage].
  /// - [renderChrome]: con `false` el popup se pinta sin scrim ni tarjeta (el host pone el
  ///   marco). `null` = valor por defecto del SDK (`true`).
  /// - [showProgressBar]: fuerza la barra de progreso; `null` respeta la configuración del
  ///   survey en la plataforma.
  /// - [metadata]: metadata libre que el SDK reenvía al backend con cada respuesta de survey.
  ///   Las entradas con valor `null` se descartan y, si se pasa [userId], este gana sobre una
  ///   clave `userId` de [metadata].
  /// - [contactAttributes]: atributos del Contact enviados al arrancar (requiere [userId]); ver
  ///   [setContactAttributes].
  /// - [geolocation]: país/ciudad por IP en analytics (`false` no llama nunca a los servicios
  ///   de geolocalización).
  static Future<void> init({
    required String publicKey,
    DeepdotsEnvironment environment = DeepdotsEnvironment.production,
    String? userId,
    String? language,
    bool debug = false,
    bool trackingEnabled = true,
    String? analyticsPublicKey,
    String? analyticsIntegration,
    Map<String, Object?>? contactAttributes,
    bool geolocation = true,
    bool? renderChrome,
    bool? showProgressBar,
    Map<String, Object?>? metadata,
  }) async {
    _channel.setMethodCallHandler(_onNativeCall);
    await _channel.invokeMethod<void>('init', {
      'publicKey': publicKey,
      'environment': environment.name,
      'userId': userId,
      'language': language,
      'debug': debug,
      'trackingEnabled': trackingEnabled,
      'analyticsPublicKey': analyticsPublicKey,
      'analyticsIntegration': analyticsIntegration,
      'contactAttributes': contactAttributes,
      'geolocation': geolocation,
      'renderChrome': renderChrome,
      'showProgressBar': showProgressBar,
      'metadata': metadata,
      // El nativo lo declara como wrapper: `deepdots_sdk=flutter@<versión>` en respuestas y
      // analítica, con el núcleo nativo en `deepdots_sdk_core`.
      'sdkName': 'flutter',
      'sdkVersion': deepdotsPopupsVersion,
    });
    // Ciclo de vida automático. `hide`/`show` (no `pause`/`resume`) porque en el SDK nativo
    // `onBackground()` es FIN DE SESIÓN: `inactive` es transitorio (llamada entrante, app
    // switcher en iOS) y partiría la sesión en dos.
    _initialized = true;
    final pending = _pendingPath;
    _pendingPath = null;
    if (pending != null) await setPath(pending);
    _lifecycle ??= AppLifecycleListener(
      onHide: () => _channel.invokeMethod<void>('onBackground'),
      onShow: () => _channel.invokeMethod<void>('onForeground'),
    );
  }

  /// Pantalla actual. Alimenta los triggers por ruta/tiempo y el `page_view` de analytics.
  /// Con [DeepdotsNavigatorObserver] no hace falta llamarlo a mano.
  /// Si llega antes de `init()` (la ruta inicial suele hacerlo) se guarda y se envía al terminar.
  static Future<void> setPath(String path) async {
    if (!_initialized) {
      _pendingPath = path;
      return;
    }
    await _channel.invokeMethod<void>('setPath', {'path': path});
  }

  /// Dispara los popups con trigger de tipo `event` y ese nombre.
  static Future<void> triggerEvent(String name) =>
      _channel.invokeMethod('triggerEvent', {'name': name});

  // --- Triggers de scroll y de salida ---

  /// Porcentaje de scroll (0-100) de la pantalla actual. Alimenta los popups con trigger de tipo
  /// `scroll`, que saltan al llegar a su umbral (una vez por pantalla: `setPath` lo rearma).
  /// [DeepdotsScrollListener] lo llama solo; a mano solo hace falta con scroll propio.
  /// Antes de `init()` no hace nada: todavía no hay definiciones que evaluar.
  static Future<void> onScroll(int percentage) async {
    if (!_initialized) return;
    await _channel.invokeMethod<void>(
        'onScroll', {'percentage': percentage.clamp(0, 100)});
  }

  /// Avisa de que el usuario va a salir de la pantalla actual: encola los popups con trigger
  /// `exit` contra ESTA pantalla y se muestran (tras su retardo) cuando la ruta ya es otra.
  ///
  /// No hace falta llamarlo al navegar con [DeepdotsNavigatorObserver]: el `setPath` de la ruta
  /// nueva ya encola los de la anterior. Sirve para adelantar la cuenta atrás a la intención de
  /// salir (p. ej. en un botón Atrás propio, ANTES de navegar). Si al vencer el retardo la ruta
  /// no ha cambiado, el SDK lo descarta. Antes de `init()` no hace nada.
  static Future<void> onExit() async {
    if (!_initialized) return;
    await _channel.invokeMethod<void>('onExit');
  }

  static Future<void> track(String name, [Map<String, Object?>? params]) =>
      _channel.invokeMethod('track', {'name': name, 'params': params});

  /// Cambio de usuario (login/logout). Sin argumento vuelve al id anónimo del SDK.
  static Future<void> setUserId([String? userId]) =>
      _channel.invokeMethod('setUserId', {'userId': userId});

  static Future<void> setTrackingEnabled(bool enabled) =>
      _channel.invokeMethod('setTrackingEnabled', {'enabled': enabled});

  static Future<String?> getUserId() =>
      _channel.invokeMethod<String>('getUserId');

  static Future<String?> getSessionId() =>
      _channel.invokeMethod<String>('getSessionId');

  /// Id del feedback en que se convertirá la sesión de analytics abierta (`sdkSessionId` en la
  /// API). `null` hasta que la API acepta el primer lote, tras cerrar la sesión y sin
  /// `analyticsPublicKey`. Para saber también qué sesión se cerró, usa [feedbackSessions].
  static Future<String?> getFeedbackSessionId() =>
      _channel.invokeMethod<String>('getFeedbackSessionId');

  // ───────── Analytics ─────────
  //
  // Valores que cruzan el canal: String, num, bool y null. El SDK nativo convierte los
  // atributos y las métricas a texto (`toString()`), y los `params` de los eventos a primitivos
  // JSON; un Map o una List anidados llegan como texto y con un formato distinto en Android y
  // en iOS, así que mejor aplanarlos antes. Todo es no-op con el tracking desactivado.

  /// Atributos del usuario para los desgloses de analytics (`registration_status`, `plan`…).
  /// Se envían en el contexto de cada lote. Nativo: `setUserAttributes(attributes)`.
  static Future<void> setUserAttributes(Map<String, Object?> attributes) =>
      _channel.invokeMethod('setUserAttributes', {'attributes': attributes});

  /// Atributos internos del usuario (plan, edad, idioma preferido…) que se guardan en el
  /// Contact del backend para segmentar popups. Requiere `userId` en el `init`. Devuelve `true`
  /// si se enviaron y `false` si no cambiaron, falta el `userId` o el tracking está desactivado.
  /// Nativo: `suspend setContactAttributes(attributes)`.
  static Future<bool> setContactAttributes(
          Map<String, Object?> attributes) async =>
      await _channel.invokeMethod<bool>(
          'setContactAttributes', {'attributes': attributes}) ??
      false;

  /// Métrica medible del host (campo `feedback.metrics`). Persistente: se reenvía en cada lote
  /// y la misma `key` sobrescribe. Un `value` nulo se ignora. Nativo: `setMetric(key, value)`.
  static Future<void> setMetric(String key, Object? value) =>
      _channel.invokeMethod('setMetric', {'key': key, 'value': value});

  /// Reporta un error de la app (evento `deepdots_app_crash`). Pensado para
  /// `FlutterError.onError` y `PlatformDispatcher.instance.onError`. `severity: 'fatal'` lo
  /// marca como fatal. Nativo: `reportError(error, severity, handled, context)`, que recibe un
  /// `Throwable`: el puente lo construye con el texto del error, y el tipo de Dart viaja en
  /// `context` como `dart_error_type` (el `crash_type` nativo es el de la clase del puente).
  static Future<void> reportError(
    Object error, {
    StackTrace? stackTrace,
    String severity = 'error',
    bool handled = true,
    Map<String, Object?>? context,
  }) =>
      _channel.invokeMethod('reportError', {
        'message': error.toString(),
        'errorType': error.runtimeType.toString(),
        'stack': stackTrace?.toString(),
        'severity': severity,
        'handled': handled,
        'context': context,
      });

  /// Cierre explícito de la sesión (logout, fin de flujo): `session_end` y último lote con
  /// `completed:true`. Nativo: `endSession()`.
  static Future<void> endSession() => _channel.invokeMethod('endSession');

  /// Envía ya el lote de analytics acumulado (si falla por red se re-encola). Nativo:
  /// `flushAnalytics()` con el `AnalyticsFlushMeta` por defecto.
  static Future<void> flushAnalytics() =>
      _channel.invokeMethod('flushAnalytics');

  /// Una búsqueda del usuario (Findability #31/#35). `has_results` lo deriva el SDK de
  /// [resultsCount]. Nativo: `trackSearch(query, resultsCount, params)`.
  static Future<void> trackSearch(String query, int resultsCount,
          [Map<String, Object?>? params]) =>
      _channel.invokeMethod('trackSearch',
          {'query': query, 'resultsCount': resultsCount, 'params': params});

  /// Fricción al encontrar algo (#34/#35), agrupada por [frictionTopic]. Nativo:
  /// `trackFindabilityFriction(frictionTopic, params)`.
  static Future<void> trackFindabilityFriction(String frictionTopic,
          [Map<String, Object?>? params]) =>
      _channel.invokeMethod('trackFindabilityFriction',
          {'frictionTopic': frictionTopic, 'params': params});

  /// Un paso de un embudo; el backend correlaciona los pasos por [taskId] para la conversión,
  /// el abandono y el tiempo. Nativo: `trackFunnelStep(funnel, step, taskId, params)`.
  static Future<void> trackFunnelStep(String funnel, String step, String taskId,
          [Map<String, Object?>? params]) =>
      _channel.invokeMethod('trackFunnelStep',
          {'funnel': funnel, 'step': step, 'taskId': taskId, 'params': params});

  /// Interacción significativa (Product Effectiveness), agrupada por [interactionType]
  /// (`get_help`, `contact_support`…). Un tipo vacío lo descarta el SDK con un aviso. Nativo:
  /// `trackMeaningfulInteraction(interactionType, params)`.
  static Future<void> trackMeaningfulInteraction(String interactionType,
          [Map<String, Object?>? params]) =>
      _channel.invokeMethod('trackMeaningfulInteraction',
          {'interactionType': interactionType, 'params': params});

  /// Una etapa del funnel de una notificación del host (Messaging #18–22): [stage] (p. ej.
  /// `delivered`, `opened`), [id] del mensaje, [title] para agrupar y [channel] (`push` o
  /// `in_app`). El SDK nativo (`MessageGuard`) descarta con un aviso un canal no válido, una
  /// etapa repetida o un mensaje que ya llegó por otro canal. Nativo:
  /// `trackMessage(stage, id, title, channel, campaign, value, currency, params)`.
  static Future<void> trackMessage({
    required String stage,
    required String id,
    required String title,
    required String channel,
    String? campaign,
    num? value,
    String? currency,
    Map<String, Object?>? params,
  }) =>
      _channel.invokeMethod('trackMessage', {
        'stage': stage,
        'id': id,
        'title': title,
        'channel': channel,
        'campaign': campaign,
        'value': value?.toDouble(),
        'currency': currency,
        'params': params,
      });

  /// Entrada en un mini-service: etiqueta los eventos siguientes y la metadata del survey con
  /// `mini_service`. Nativo: `enterMiniService(name, entryPointType)`.
  static Future<void> enterMiniService(String name, [String? entryPointType]) =>
      _channel.invokeMethod(
          'enterMiniService', {'name': name, 'entryPointType': entryPointType});

  /// Salida del mini-service [name]: emite `mini_service_exit` con la duración. No hace nada
  /// si ese mini-service no está activo. Nativo: `exitMiniService(name)`.
  static Future<void> exitMiniService(String name) =>
      _channel.invokeMethod('exitMiniService', {'name': name});

  // Control manual de popups. Los que pintan algo (`show`, `showByPopupId`, `triggerSurvey`,
  // `close`) necesitan la Activity (Android) o el root view controller (iOS) y fallan con
  // `PlatformException(no_context)` si todavía no hay.

  /// Muestra el popup del survey [surveyId] saltándose triggers y segmentación. [data] llega
  /// como `extra` del evento `popup_shown`. El SDK nativo busca el popup solo por [surveyId];
  /// [productId] se pasa tal cual pero hoy no se usa.
  static Future<void> show(String surveyId, String productId,
          [Map<String, Object?>? data]) =>
      _channel.invokeMethod(
          'show', {'surveyId': surveyId, 'productId': productId, 'data': data});

  /// Muestra el popup con ese id, sin evaluar triggers ni segmentación.
  static Future<void> showByPopupId(String popupId) =>
      _channel.invokeMethod('showByPopupId', {'popupId': popupId});

  /// Muestra el popup del survey [surveyId] (o [popupId], si hay varios) solo si pasa la
  /// segmentación y el cooldown, como si hubiese saltado su trigger.
  static Future<void> triggerSurvey(String surveyId, [String? popupId]) =>
      _channel.invokeMethod(
          'triggerSurvey', {'surveyId': surveyId, 'popupId': popupId});

  /// Cierra el popup abierto.
  static Future<void> close() => _channel.invokeMethod('close');

  /// Marca el survey como respondido. Normalmente no hace falta: el SDK lo hace solo al
  /// completar el survey.
  static Future<void> markSurveyAnswered(String surveyId) =>
      _channel.invokeMethod('markSurveyAnswered', {'surveyId': surveyId});

  /// Dispara los popups con trigger de tipo `click` y ese [targetId].
  static Future<void> triggerClick(String targetId) =>
      _channel.invokeMethod('triggerClick', {'targetId': targetId});

  /// Cambia el idioma que el SDK nativo lee de `provideLang`. Decide qué popups se muestran
  /// (`segments.lang`, por prefijo: `en-US` encaja con `en`), en qué idioma se pide el survey y
  /// los textos del popup. Aplica al siguiente popup; con `null` manda el idioma del dispositivo.
  /// Se puede llamar antes de [init]; un `language` no nulo en [init] lo sustituye.
  static Future<void> setLanguage(String? language) =>
      _channel.invokeMethod('setLanguage', {'language': language});

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onFeedbackSession') {
      final args = Map<String, Object?>.from(call.arguments as Map);
      _feedbackSessions.add(DeepdotsFeedbackSession(
        sessionId: args['sessionId'] as String,
        closed: args['status'] == 'closed',
      ));
      return;
    }
    if (call.method != 'onEvent') return;
    final args = Map<String, Object?>.from(call.arguments as Map);
    _events.add(DeepdotsEvent(
      type: args['type'] as String,
      popupId: args['popupId'] as String? ?? '',
      surveyId: args['surveyId'] as String? ?? '',
      productId: args['productId'] as String? ?? '',
      extra: Map<String, Object?>.from(args['extra'] as Map? ?? const {}),
      timestamp: switch (args['timestamp']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
    ));
  }
}

/// Reporta cada cambio de ruta con nombre al SDK (`setPath`). Añádelo a
/// `MaterialApp.navigatorObservers`. Las rutas sin nombre (diálogos, bottom sheets) se ignoran:
/// no son pantallas y cortarían la visita de la pantalla de debajo.
///
/// Triggers de salida (`exit`): no llama a `onExit()`, a propósito. El `setPath` nativo ya encola
/// los popups de salida de la ruta ANTERIOR antes de cambiar de pantalla, así que el popup queda
/// asociado a la pantalla de origen sin hacer nada más. Llamarlo aquí sobraría (antes del
/// `setPath`, el SDK deduplica por popup+origen; con retardo 0 podría vencer antes y descartarse por
/// "ruta sin cambiar" para que lo vuelva a encolar el `setPath`) o sería incorrecto (después, el origen ya sería
/// la pantalla nueva).
class DeepdotsNavigatorObserver extends NavigatorObserver {
  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (route is PageRoute && name != null) DeepdotsPopups.setPath(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);
}

/// Reporta al SDK (`onScroll`) el porcentaje de scroll vertical de su subárbol, para los popups
/// con trigger de tipo `scroll`. Envuelve el cuerpo de la pantalla:
///
/// ```dart
/// body: DeepdotsScrollListener(child: ListView(...))
/// ```
///
/// Solo escucha el scrollable principal (profundidad 0, eje vertical): las listas horizontales
/// o anidadas no son "el scroll de la pantalla". El porcentaje es `pixels / maxScrollExtent`
/// redondeado a entero, y solo se envía cuando cambia, igual que los ejemplos nativos
/// (`distinctUntilChanged` en Android, `lastScrollPct` en iOS): los umbrales son enteros, así
/// que un cambio por debajo del 1% no puede disparar nada y no merece una llamada al canal.
/// Si el contenido cabe entero (`maxScrollExtent` 0) no se reporta nada: no hay progreso que
/// medir, y el rebote de iOS daría una división por cero.
class DeepdotsScrollListener extends StatefulWidget {
  const DeepdotsScrollListener({super.key, required this.child});

  final Widget child;

  @override
  State<DeepdotsScrollListener> createState() => _DeepdotsScrollListenerState();
}

class _DeepdotsScrollListenerState extends State<DeepdotsScrollListener> {
  int? _lastReported;

  bool _onNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    if (range <= 0) return false;
    // Se acota a 0-100: el rebote (overscroll) de iOS lleva `pixels` fuera del rango.
    final pct = ((metrics.pixels - metrics.minScrollExtent) / range * 100)
        .round()
        .clamp(0, 100);
    // Antes de init() no se envía ni se apunta, para no perder el valor cuando ya se pueda enviar.
    if (pct == _lastReported || !DeepdotsPopups._initialized) return false;
    _lastReported = pct;
    DeepdotsPopups.onScroll(pct);
    return false; // deja que la notificación siga subiendo
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
        onNotification: _onNotification, child: widget.child);
  }
}
