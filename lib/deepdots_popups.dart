/// Deepdots popups para Flutter: envoltorio fino sobre el SDK nativo (KMP) de Android e iOS.
///
/// Toda la lógica (triggers, segmentación, sesión, analytics, render del survey) vive en el
/// SDK nativo. Este paquete solo la expone a Dart y conecta la navegación y el ciclo de vida
/// de Flutter, para que el host no tenga que instrumentarlos a mano.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum DeepdotsEnvironment { production, development }

/// Evento del SDK nativo (`popup_shown`, `popup_clicked`, `survey_completed`).
class DeepdotsEvent {
  const DeepdotsEvent({
    required this.type,
    required this.popupId,
    required this.surveyId,
    required this.productId,
  });

  final String type;
  final String popupId;
  final String surveyId;
  final String productId;

  @override
  String toString() => 'DeepdotsEvent($type, popup=$popupId, survey=$surveyId)';
}

class DeepdotsPopups {
  DeepdotsPopups._();

  static const MethodChannel _channel = MethodChannel('com.deepdots/popups');
  static final StreamController<DeepdotsEvent> _events = StreamController.broadcast();
  static AppLifecycleListener? _lifecycle;
  static bool _initialized = false;
  static String? _pendingPath;

  /// Eventos de los popups, para analítica propia del host o para reaccionar en la UI.
  static Stream<DeepdotsEvent> get events => _events.stream;

  /// Inicializa el SDK nativo. Idempotente: una segunda llamada no hace nada.
  static Future<void> init({
    required String publicKey,
    DeepdotsEnvironment environment = DeepdotsEnvironment.production,
    String? userId,
    String? language,
    bool debug = false,
    bool trackingEnabled = true,
    String? analyticsPublicKey,
    String? analyticsIntegration,
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
  static Future<void> triggerEvent(String name) => _channel.invokeMethod('triggerEvent', {'name': name});

  // --- Triggers de scroll y de salida ---

  /// Porcentaje de scroll (0-100) de la pantalla actual. Alimenta los popups con trigger de tipo
  /// `scroll`, que saltan al llegar a su umbral (una vez por pantalla: `setPath` lo rearma).
  /// [DeepdotsScrollListener] lo llama solo; a mano solo hace falta con scroll propio.
  /// Antes de `init()` no hace nada: todavía no hay definiciones que evaluar.
  static Future<void> onScroll(int percentage) async {
    if (!_initialized) return;
    await _channel.invokeMethod<void>('onScroll', {'percentage': percentage.clamp(0, 100)});
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
  static Future<void> setUserId([String? userId]) => _channel.invokeMethod('setUserId', {'userId': userId});

  static Future<void> setTrackingEnabled(bool enabled) =>
      _channel.invokeMethod('setTrackingEnabled', {'enabled': enabled});

  static Future<String?> getUserId() => _channel.invokeMethod<String>('getUserId');

  static Future<String?> getSessionId() => _channel.invokeMethod<String>('getSessionId');

  static Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onEvent') return;
    final args = Map<String, Object?>.from(call.arguments as Map);
    _events.add(DeepdotsEvent(
      type: args['type'] as String,
      popupId: args['popupId'] as String? ?? '',
      surveyId: args['surveyId'] as String? ?? '',
      productId: args['productId'] as String? ?? '',
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
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _report(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _report(previousRoute);
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
    final pct = ((metrics.pixels - metrics.minScrollExtent) / range * 100).round().clamp(0, 100);
    // Antes de init() no se envía ni se apunta, para no perder el valor cuando ya se pueda enviar.
    if (pct == _lastReported || !DeepdotsPopups._initialized) return false;
    _lastReported = pct;
    DeepdotsPopups.onScroll(pct);
    return false; // deja que la notificación siga subiendo
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(onNotification: _onNotification, child: widget.child);
  }
}
