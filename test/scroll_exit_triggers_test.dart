import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Triggers de scroll y de salida: lo que llega al canal nativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await DeepdotsPopups.init(publicKey: 'test-key');
  });

  setUp(calls.clear);

  List<int> scrollCalls() => [
        for (final c in calls.where((c) => c.method == 'onScroll'))
          (c.arguments as Map)['percentage'] as int
      ];

  group('passthrough', () {
    test('onScroll envía el porcentaje acotado a 0-100', () async {
      await DeepdotsPopups.onScroll(42);
      await DeepdotsPopups.onScroll(150);
      await DeepdotsPopups.onScroll(-3);
      expect(scrollCalls(), [42, 100, 0]);
    });

    test('onExit envía onExit sin argumentos', () async {
      await DeepdotsPopups.onExit();
      expect(calls.single.method, 'onExit');
      expect(calls.single.arguments, isNull);
    });
  });

  group('DeepdotsScrollListener', () {
    // Viewport de 600 (superficie de test 800x600) y 20 elementos de 100 → maxScrollExtent 1400.
    Future<ScrollController> pumpList(WidgetTester tester,
        {int items = 20, ScrollPhysics? physics}) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: DeepdotsScrollListener(
          child: ListView.builder(
            controller: controller,
            physics: physics,
            itemExtent: 100,
            itemCount: items,
            itemBuilder: (_, i) => Text('item $i'),
          ),
        ),
      ));
      return controller;
    }

    testWidgets('reporta pixels / maxScrollExtent redondeado', (tester) async {
      final controller = await pumpList(tester);
      expect(controller.position.maxScrollExtent, 1400);
      controller.jumpTo(350); // 25%
      controller.jumpTo(700); // 50%
      controller.jumpTo(1400); // 100%
      await tester.pump();
      expect(scrollCalls(), [25, 50, 100]);
    });

    testWidgets('no repite el mismo valor entero', (tester) async {
      final controller = await pumpList(tester);
      controller.jumpTo(700); // 50%
      controller.jumpTo(703); // 50,2% → 50: no se envía
      controller.jumpTo(706); // 50,4% → 50: no se envía
      controller.jumpTo(714); // 51%
      controller.jumpTo(700); // vuelve a 50%: cambió, se envía
      await tester.pump();
      expect(scrollCalls(), [50, 51, 50]);
    });

    testWidgets(
        'un drag real produce valores crecientes sin duplicados consecutivos',
        (tester) async {
      await pumpList(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final values = scrollCalls();
      expect(values, isNotEmpty);
      for (var i = 1; i < values.length; i++) {
        expect(values[i], isNot(values[i - 1]));
        expect(values[i], greaterThan(values[i - 1]));
      }
      expect(values.every((v) => v >= 0 && v <= 100), isTrue);
    });

    testWidgets(
        'si el contenido cabe (maxScrollExtent 0) no reporta nada, ni con rebote',
        (tester) async {
      await pumpList(tester,
          items: 3,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()));
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollCalls(), isEmpty);
    });

    testWidgets('el rebote por encima del final se acota a 100',
        (tester) async {
      await pumpList(tester, physics: const BouncingScrollPhysics());
      final controller =
          tester.widget<ListView>(find.byType(ListView)).controller!;
      controller.jumpTo(1400);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(scrollCalls(), everyElement(inInclusiveRange(0, 100)));
      expect(scrollCalls().first, 100);
    });

    testWidgets('ignora scrollables horizontales y anidados', (tester) async {
      final horizontal = ScrollController();
      final inner = ScrollController();
      addTearDown(horizontal.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(MaterialApp(
        home: DeepdotsScrollListener(
          child: Column(children: [
            SizedBox(
              height: 100,
              child: ListView(
                controller: horizontal,
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 20; i++) const SizedBox(width: 100)
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: ListView(
                      controller: inner,
                      children: [
                        for (var i = 0; i < 20; i++) const SizedBox(height: 100)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ));
      horizontal.jumpTo(500); // eje horizontal (profundidad 0): se ignora
      inner.jumpTo(500); // vertical pero anidado (profundidad 1): se ignora
      await tester.pump();
      expect(scrollCalls(), isEmpty);
    });
  });

  group('DeepdotsNavigatorObserver y triggers de salida', () {
    Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [DeepdotsNavigatorObserver()],
        initialRoute: '/home',
        routes: {
          '/home': (_) => const Text('home'),
          '/game': (_) => const Text('game'),
        },
      ));
      await tester.pumpAndSettle();
      calls.clear();
      return navigator;
    }

    // El setPath nativo ya encola los popups `exit` de la ruta ANTERIOR. Un onExit automático
    // sobraría (antes) o los asociaría a la pantalla nueva (después): el observer no lo llama.
    testWidgets('al navegar solo envía setPath de la ruta nueva, sin onExit',
        (tester) async {
      final navigator = await pumpApp(tester);
      navigator.currentState!.pushNamed('/game');
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['setPath', 'setPath']);
      expect([for (final c in calls) (c.arguments as Map)['path']],
          ['/game', '/home']);
    });

    testWidgets(
        'onExit manual antes de navegar llega ANTES que el setPath de la ruta nueva',
        (tester) async {
      final navigator = await pumpApp(tester);
      // Patrón de los ejemplos nativos: onExit() en el botón Atrás/salir y después navegar.
      await DeepdotsPopups.onExit();
      navigator.currentState!.pushNamed('/game');
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['onExit', 'setPath']);
    });
  });
}
