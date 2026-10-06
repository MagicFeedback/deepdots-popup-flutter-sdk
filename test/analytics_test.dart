import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// La API de analytics es un puente sin lógica: cada método tiene que llegar al canal con el
/// nombre y los argumentos que espera el lado nativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];
  Object? reply;

  setUp(() {
    calls.clear();
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  void expectCall(String method, Object? arguments) {
    expect(calls, hasLength(1));
    expect(calls.single.method, method);
    expect(calls.single.arguments, arguments);
  }

  test('init pasa contactAttributes y geolocation', () async {
    await DeepdotsPopups.init(publicKey: 'pk', contactAttributes: {'plan': 'pro', 'age': 30}, geolocation: false);
    final args = calls.firstWhere((c) => c.method == 'init').arguments as Map;
    expect(args['contactAttributes'], {'plan': 'pro', 'age': 30});
    expect(args['geolocation'], false);
  });

  test('setUserAttributes', () async {
    await DeepdotsPopups.setUserAttributes({'plan': 'pro', 'beta': true, 'seats': 3});
    expectCall('setUserAttributes', {
      'attributes': {'plan': 'pro', 'beta': true, 'seats': 3},
    });
  });

  test('setContactAttributes devuelve el bool nativo', () async {
    reply = true;
    expect(await DeepdotsPopups.setContactAttributes({'plan': 'pro'}), isTrue);
    expectCall('setContactAttributes', {
      'attributes': {'plan': 'pro'},
    });
  });

  test('setContactAttributes trata una respuesta nula como false', () async {
    expect(await DeepdotsPopups.setContactAttributes({}), isFalse);
  });

  test('setMetric', () async {
    await DeepdotsPopups.setMetric('cart_value', 42.5);
    expectCall('setMetric', {'key': 'cart_value', 'value': 42.5});
  });

  test('reportError manda texto, tipo de Dart, pila y opciones', () async {
    final stack = StackTrace.fromString('#0 main (file.dart:1:1)');
    await DeepdotsPopups.reportError(
      StateError('boom'),
      stackTrace: stack,
      severity: 'fatal',
      handled: false,
      context: {'screen': '/home'},
    );
    expectCall('reportError', {
      'message': 'Bad state: boom',
      'errorType': 'StateError',
      'stack': '#0 main (file.dart:1:1)',
      'severity': 'fatal',
      'handled': false,
      'context': {'screen': '/home'},
    });
  });

  test('reportError con los valores por defecto', () async {
    await DeepdotsPopups.reportError('texto');
    expectCall('reportError', {
      'message': 'texto',
      'errorType': 'String',
      'stack': null,
      'severity': 'error',
      'handled': true,
      'context': null,
    });
  });

  test('endSession', () async {
    await DeepdotsPopups.endSession();
    expectCall('endSession', null);
  });

  test('flushAnalytics', () async {
    await DeepdotsPopups.flushAnalytics();
    expectCall('flushAnalytics', null);
  });

  test('trackSearch', () async {
    await DeepdotsPopups.trackSearch('zapatos', 0, {'source': 'header'});
    expectCall('trackSearch', {
      'query': 'zapatos',
      'resultsCount': 0,
      'params': {'source': 'header'},
    });
  });

  test('trackFindabilityFriction', () async {
    await DeepdotsPopups.trackFindabilityFriction('billing');
    expectCall('trackFindabilityFriction', {'frictionTopic': 'billing', 'params': null});
  });

  test('trackFunnelStep', () async {
    await DeepdotsPopups.trackFunnelStep('checkout', 'payment', 'task-1', {'step_index': 2});
    expectCall('trackFunnelStep', {
      'funnel': 'checkout',
      'step': 'payment',
      'taskId': 'task-1',
      'params': {'step_index': 2},
    });
  });

  test('trackMeaningfulInteraction', () async {
    await DeepdotsPopups.trackMeaningfulInteraction('get_help');
    expectCall('trackMeaningfulInteraction', {'interactionType': 'get_help', 'params': null});
  });

  test('trackMessage pasa value como double y no valida el canal', () async {
    await DeepdotsPopups.trackMessage(
      stage: 'opened',
      id: 'm-1',
      title: 'Promo',
      channel: 'email', // lo valida MessageGuard en nativo, no Dart
      campaign: 'otoño',
      value: 10,
      currency: 'EUR',
      params: {'variant': 'b'},
    );
    expectCall('trackMessage', {
      'stage': 'opened',
      'id': 'm-1',
      'title': 'Promo',
      'channel': 'email',
      'campaign': 'otoño',
      'value': 10.0,
      'currency': 'EUR',
      'params': {'variant': 'b'},
    });
    expect((calls.single.arguments as Map)['value'], isA<double>());
  });

  test('trackMessage con los opcionales a null', () async {
    await DeepdotsPopups.trackMessage(stage: 'delivered', id: 'm-2', title: 'T', channel: 'push');
    expectCall('trackMessage', {
      'stage': 'delivered',
      'id': 'm-2',
      'title': 'T',
      'channel': 'push',
      'campaign': null,
      'value': null,
      'currency': null,
      'params': null,
    });
  });

  test('enterMiniService', () async {
    await DeepdotsPopups.enterMiniService('wallet', 'tab_bar');
    expectCall('enterMiniService', {'name': 'wallet', 'entryPointType': 'tab_bar'});
  });

  test('enterMiniService sin entryPointType', () async {
    await DeepdotsPopups.enterMiniService('wallet');
    expectCall('enterMiniService', {'name': 'wallet', 'entryPointType': null});
  });

  test('exitMiniService', () async {
    await DeepdotsPopups.exitMiniService('wallet');
    expectCall('exitMiniService', {'name': 'wallet'});
  });
}
