import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// DD-243: modo claro/oscuro, pasado tal cual al SDK nativo (DD-240).
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

  test('init pasa appearance por su nombre', () async {
    await DeepdotsPopups.init(
        publicKey: 'pk', appearance: DeepdotsAppearance.system);
    final args = calls.firstWhere((c) => c.method == 'init').arguments as Map;
    expect(args['appearance'], 'system');
  });

  test('sin appearance va null: deciden los colores del Style', () async {
    await DeepdotsPopups.init(publicKey: 'pk');
    final args = calls.firstWhere((c) => c.method == 'init').arguments as Map;
    expect(args.containsKey('appearance'), isTrue);
    expect(args['appearance'], isNull);
  });

  test('setAppearance manda dark, light y null', () async {
    await DeepdotsPopups.setAppearance(DeepdotsAppearance.dark);
    await DeepdotsPopups.setAppearance(DeepdotsAppearance.light);
    await DeepdotsPopups.setAppearance(null);
    final sent = calls
        .where((c) => c.method == 'setAppearance')
        .map((c) => (c.arguments as Map)['appearance'])
        .toList();
    expect(sent, ['dark', 'light', null]);
  });
}
