import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// autoTrack.errors: FlutterError.onError y PlatformDispatcher.onError sin código del host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];

  late FlutterExceptionHandler? originalFlutterOnError;
  late ErrorCallback? originalPlatformOnError;

  // Handlers "de otra librería" (Sentry, Crashlytics, el del host) instalados antes del init.
  final previousFlutterErrors = <FlutterErrorDetails>[];
  final previousPlatformErrors = <Object>[];
  void previousFlutter(FlutterErrorDetails d) => previousFlutterErrors.add(d);
  bool previousPlatform(Object e, StackTrace s) {
    previousPlatformErrors.add(e);
    return true;
  }

  setUp(() {
    calls.clear();
    previousFlutterErrors.clear();
    previousPlatformErrors.clear();
    originalFlutterOnError = FlutterError.onError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    DeepdotsPopups.debugReset();
    FlutterError.onError = originalFlutterOnError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
  });

  List<Map<Object?, Object?>> reported() =>
      [for (final c in calls.where((c) => c.method == 'reportError')) c.arguments as Map];

  FlutterErrorDetails details(Object error, {bool silent = false}) => FlutterErrorDetails(
        exception: error,
        stack: StackTrace.current,
        library: 'widgets library',
        context: ErrorDescription('building Foo'),
        silent: silent,
      );

  group('activado por defecto', () {
    test('FlutterError.onError reporta el error al SDK', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      FlutterError.onError!(details(StateError('boom')));
      await Future<void>.delayed(Duration.zero);

      final r = reported().single;
      expect(r['message'], 'Bad state: boom');
      expect(r['errorType'], 'StateError');
      expect(r['severity'], 'error');
      expect(r['handled'], false);
      expect(r['stack'], isNotNull);
      expect(r['context'], {
        'dart_error_source': 'flutter_error',
        'dart_error_library': 'widgets library',
        'dart_error_context': 'building Foo',
      });
    });

    test('PlatformDispatcher.onError reporta el error como fatal', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      PlatformDispatcher.instance.onError!(ArgumentError('async'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);

      final r = reported().single;
      expect(r['errorType'], 'ArgumentError');
      expect(r['severity'], 'fatal');
      expect(r['handled'], false);
      expect(r['context'], {'dart_error_source': 'platform_dispatcher'});
    });

    test('un error silent de Flutter no se reporta', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      FlutterError.onError!(details(Exception('image'), silent: true));
      await Future<void>.delayed(Duration.zero);
      expect(reported(), isEmpty);
    });

    test('se instala una sola vez aunque init() se llame dos veces', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      final installed = FlutterError.onError;
      final installedPlatform = PlatformDispatcher.instance.onError;
      await DeepdotsPopups.init(publicKey: 'test-key');
      expect(FlutterError.onError, same(installed));
      expect(PlatformDispatcher.instance.onError, same(installedPlatform));

      FlutterError.onError!(details(StateError('once')));
      await Future<void>.delayed(Duration.zero);
      expect(reported(), hasLength(1));
    });

    test('un fallo del canal no lanza otro error desde el handler', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'reportError') throw PlatformException(code: 'not_initialized');
        return null;
      });
      expect(() => FlutterError.onError!(details(StateError('x'))), returnsNormally);
      expect(PlatformDispatcher.instance.onError!(StateError('y'), StackTrace.current), isFalse);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('autoTrack.errors = false', () {
    test('no instala ningún handler', () async {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
      await DeepdotsPopups.init(publicKey: 'test-key', autoTrack: const DeepdotsAutoTrack(errors: false));

      expect(FlutterError.onError, previousFlutter);
      expect(PlatformDispatcher.instance.onError, previousPlatform);
      FlutterError.onError!(details(StateError('x')));
      await Future<void>.delayed(Duration.zero);
      expect(reported(), isEmpty);
    });

    test('reportError manual sigue funcionando', () async {
      await DeepdotsPopups.init(publicKey: 'test-key', autoTrack: const DeepdotsAutoTrack.none());
      await DeepdotsPopups.reportError(StateError('manual'));
      expect(reported().single['handled'], true);
    });
  });

  group('encadena a los handlers anteriores', () {
    test('FlutterError.onError anterior recibe el mismo error', () async {
      FlutterError.onError = previousFlutter;
      await DeepdotsPopups.init(publicKey: 'test-key');
      expect(FlutterError.onError, isNot(previousFlutter));

      final d = details(StateError('chained'));
      FlutterError.onError!(d);
      await Future<void>.delayed(Duration.zero);
      expect(previousFlutterErrors.single, same(d));
      expect(reported(), hasLength(1));
    });

    test('un error silent también llega al handler anterior', () async {
      FlutterError.onError = previousFlutter;
      await DeepdotsPopups.init(publicKey: 'test-key');
      FlutterError.onError!(details(Exception('image'), silent: true));
      expect(previousFlutterErrors, hasLength(1));
    });

    test('PlatformDispatcher.onError anterior recibe el error y su resultado se respeta', () async {
      PlatformDispatcher.instance.onError = previousPlatform;
      await DeepdotsPopups.init(publicKey: 'test-key');

      final error = StateError('async');
      final handled = PlatformDispatcher.instance.onError!(error, StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(handled, isTrue);
      expect(previousPlatformErrors.single, same(error));
      expect(reported(), hasLength(1));
    });

    test('sin handler anterior, PlatformDispatcher.onError devuelve false (comportamiento del engine)', () async {
      PlatformDispatcher.instance.onError = null;
      await DeepdotsPopups.init(publicKey: 'test-key');
      expect(PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.current), isFalse);
    });
  });

  group('sin duplicados con reportError manual', () {
    test('host con su propio FlutterError.onError que llama a reportError: un solo envío', () async {
      FlutterError.onError = (d) => DeepdotsPopups.reportError(d.exception, stackTrace: d.stack);
      await DeepdotsPopups.init(publicKey: 'test-key');

      FlutterError.onError!(details(StateError('dup')));
      await Future<void>.delayed(Duration.zero);
      expect(reported(), hasLength(1));
      expect(reported().single['handled'], false, reason: 'gana el envío automático, el primero');
    });

    test('host que instala su handler DESPUÉS del init y encadena al del plugin: un solo envío', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      final pluginHandler = PlatformDispatcher.instance.onError!;
      PlatformDispatcher.instance.onError = (e, s) {
        DeepdotsPopups.reportError(e, stackTrace: s, severity: 'fatal', handled: false);
        return pluginHandler(e, s);
      };

      PlatformDispatcher.instance.onError!(StateError('dup'), StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(reported(), hasLength(1));
    });

    test('dos errores distintos se envían los dos', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      FlutterError.onError!(details(StateError('a')));
      FlutterError.onError!(details(StateError('b')));
      await Future<void>.delayed(Duration.zero);
      expect(reported(), hasLength(2));
    });

    test('reportError manual con el mismo objeto dos veces: un solo envío', () async {
      await DeepdotsPopups.init(publicKey: 'test-key');
      final error = StateError('same');
      await DeepdotsPopups.reportError(error);
      await DeepdotsPopups.reportError(error);
      expect(reported(), hasLength(1));
    });
  });
}
