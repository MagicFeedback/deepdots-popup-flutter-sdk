import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  MethodCall last() => calls.last;

  group('init', () {
    test('pasa renderChrome, showProgressBar y metadata al nativo', () async {
      await DeepdotsPopups.init(
        publicKey: 'pk',
        userId: 'u-1',
        language: 'da',
        renderChrome: false,
        showProgressBar: true,
        metadata: {'plan': 'pro', 'age': 30},
      );
      final init = calls.firstWhere((c) => c.method == 'init');
      final args = init.arguments as Map;
      expect(args['renderChrome'], false);
      expect(args['showProgressBar'], true);
      expect(args['metadata'], {'plan': 'pro', 'age': 30});
      expect(args['userId'], 'u-1');
      expect(args['language'], 'da');
    });
  });

  group('control manual', () {
    test('show', () async {
      await DeepdotsPopups.show('s-1', 'p-1', {'source': 'button'});
      expect(last().method, 'show');
      expect(last().arguments, {
        'surveyId': 's-1',
        'productId': 'p-1',
        'data': {'source': 'button'},
      });
    });

    test('show sin data', () async {
      await DeepdotsPopups.show('s-1', 'p-1');
      expect(last().arguments,
          {'surveyId': 's-1', 'productId': 'p-1', 'data': null});
    });

    test('showByPopupId', () async {
      await DeepdotsPopups.showByPopupId('pop-1');
      expect(last().method, 'showByPopupId');
      expect(last().arguments, {'popupId': 'pop-1'});
    });

    test('triggerSurvey con y sin popupId', () async {
      await DeepdotsPopups.triggerSurvey('s-1');
      expect(last().method, 'triggerSurvey');
      expect(last().arguments, {'surveyId': 's-1', 'popupId': null});
      await DeepdotsPopups.triggerSurvey('s-1', 'pop-2');
      expect(last().arguments, {'surveyId': 's-1', 'popupId': 'pop-2'});
    });

    test('close', () async {
      await DeepdotsPopups.close();
      expect(last().method, 'close');
      expect(last().arguments, isNull);
    });

    test('markSurveyAnswered', () async {
      await DeepdotsPopups.markSurveyAnswered('s-1');
      expect(last().method, 'markSurveyAnswered');
      expect(last().arguments, {'surveyId': 's-1'});
    });

    test('triggerClick', () async {
      await DeepdotsPopups.triggerClick('buy-button');
      expect(last().method, 'triggerClick');
      expect(last().arguments, {'targetId': 'buy-button'});
    });

    test('el error de contexto nativo llega a Dart como PlatformException',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
            code: 'no_context', message: 'No Activity attached yet');
      });
      expect(
        DeepdotsPopups.show('s-1', 'p-1'),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'no_context')),
      );
    });
  });

  group('setLanguage', () {
    test('envía el idioma y admite null', () async {
      await DeepdotsPopups.setLanguage('es');
      expect(last().method, 'setLanguage');
      expect(last().arguments, {'language': 'es'});
      await DeepdotsPopups.setLanguage(null);
      expect(last().arguments, {'language': null});
    });
  });

  group('eventos', () {
    Future<void> sendFromNative(Map<String, Object?> payload) async {
      const codec = StandardMethodCodec();
      await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('onEvent', payload)),
        (_) {},
      );
    }

    test('onEvent con extra y timestamp produce el DeepdotsEvent completo',
        () async {
      // El handler de llamadas nativas se registra en init().
      await DeepdotsPopups.init(publicKey: 'pk');
      final next = DeepdotsPopups.events.first;
      await sendFromNative({
        'type': 'popup_clicked',
        'popupId': 'pop-1',
        'surveyId': 's-1',
        'productId': 'p-1',
        'extra': {
          'action': 'partial',
          'page': 2,
          'nested': {'ok': true},
        },
        'timestamp': 1759752000000,
      });
      final event = await next;
      expect(event.type, 'popup_clicked');
      expect(event.popupId, 'pop-1');
      expect(event.extra['action'], 'partial');
      expect(event.extra['page'], 2);
      expect(event.extra['nested'], {'ok': true});
      expect(
          event.timestamp, DateTime.fromMillisecondsSinceEpoch(1759752000000));
    });

    test('onEvent sin extra ni timestamp deja valores vacíos', () async {
      await DeepdotsPopups.init(publicKey: 'pk');
      final next = DeepdotsPopups.events.first;
      await sendFromNative({
        'type': 'popup_shown',
        'popupId': 'pop-1',
        'surveyId': 's-1',
        'productId': 'p-1',
      });
      final event = await next;
      expect(event.extra, isEmpty);
      expect(event.timestamp, isNull);
    });
  });
}
