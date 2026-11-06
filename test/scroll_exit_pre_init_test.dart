import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Fichero aparte: el estado de init() es estático y aquí hace falta el SDK SIN inicializar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  testWidgets(
      'antes de init() ni onScroll ni onExit tocan el canal, y el listener no pierde el valor',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: DeepdotsScrollListener(
        child: ListView.builder(
          controller: controller,
          itemExtent: 100,
          itemCount: 20,
          itemBuilder: (_, i) => Text('item $i'),
        ),
      ),
    ));
    await DeepdotsPopups.onScroll(50);
    await DeepdotsPopups.onExit();
    controller.jumpTo(
        700); // 50%, sin SDK: no se envía (el nativo respondería not_initialized)
    await tester.pump();
    expect(calls, isEmpty);

    await DeepdotsPopups.init(publicKey: 'test-key');
    calls.clear();
    controller.jumpTo(701); // sigue en 50%, pero no se llegó a enviar: ahora sí
    await tester.pump();
    expect([for (final c in calls) c.method], ['onScroll']);
    expect((calls.single.arguments as Map)['percentage'], 50);
  });
}
