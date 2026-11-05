import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// autoTrack.lifecycle / screens / scroll: activados por defecto, apagados con su flag.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.deepdots/popups');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(DeepdotsPopups.debugReset);

  List<String> methods() => [for (final c in calls) c.method];

  test('DeepdotsAutoTrack: todo activado por defecto, none() lo apaga todo', () {
    const all = DeepdotsAutoTrack();
    expect([all.lifecycle, all.screens, all.scroll, all.clicks, all.errors], everyElement(isTrue));
    const none = DeepdotsAutoTrack.none();
    expect([none.lifecycle, none.screens, none.scroll, none.clicks, none.errors], everyElement(isFalse));
    expect(const DeepdotsAutoTrack(errors: false), const DeepdotsAutoTrack(errors: false));
  });

  test('el autoTrack del primer init() es el que cuenta', () async {
    await DeepdotsPopups.init(publicKey: 'k', autoTrack: const DeepdotsAutoTrack(screens: false));
    await DeepdotsPopups.init(publicKey: 'k');
    expect(DeepdotsPopups.autoTrack, const DeepdotsAutoTrack(screens: false));
  });

  group('lifecycle', () {
    Future<void> goBackgroundAndBack(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    testWidgets('por defecto envía onBackground / onForeground', (tester) async {
      await DeepdotsPopups.init(publicKey: 'k');
      await goBackgroundAndBack(tester);
      expect(methods(), ['onBackground', 'onForeground']);
    });

    testWidgets('con lifecycle: false no envía nada', (tester) async {
      await DeepdotsPopups.init(publicKey: 'k', autoTrack: const DeepdotsAutoTrack(lifecycle: false));
      await goBackgroundAndBack(tester);
      expect(methods(), isEmpty);
    });
  });

  group('screens', () {
    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [DeepdotsNavigatorObserver()],
        initialRoute: '/home',
        routes: {
          '/home': (_) => const Text('home'),
          '/cart': (_) => const Text('cart'),
        },
      ));
    }

    List<String> paths() => [for (final c in calls.where((c) => c.method == 'setPath')) (c.arguments as Map)['path'] as String];

    testWidgets('por defecto el observer envía la ruta inicial (guardada antes de init) y las siguientes', (tester) async {
      await pumpApp(tester);
      await DeepdotsPopups.init(publicKey: 'k');
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/cart');
      await tester.pumpAndSettle();
      expect(paths(), ['/home', '/cart']);
    });

    testWidgets('con screens: false el observer no envía nada, setPath manual sí', (tester) async {
      await pumpApp(tester);
      await DeepdotsPopups.init(publicKey: 'k', autoTrack: const DeepdotsAutoTrack(screens: false));
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/cart');
      await tester.pumpAndSettle();
      expect(paths(), isEmpty);

      await DeepdotsPopups.setPath('/manual');
      expect(paths(), ['/manual']);
    });

    testWidgets('con screens: false se envía un setPath manual hecho antes de init', (tester) async {
      await DeepdotsPopups.setPath('/manual-before-init');
      await DeepdotsPopups.init(publicKey: 'k', autoTrack: const DeepdotsAutoTrack(screens: false));
      expect(paths(), ['/manual-before-init']);
    });
  });

  group('scroll', () {
    Future<ScrollController> pumpList(WidgetTester tester) async {
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
      return controller;
    }

    testWidgets('por defecto el listener envía onScroll', (tester) async {
      await DeepdotsPopups.init(publicKey: 'k');
      final controller = await pumpList(tester);
      calls.clear();
      controller.jumpTo(700);
      await tester.pump();
      expect(methods(), ['onScroll']);
    });

    testWidgets('con scroll: false el listener no envía nada, onScroll manual sí', (tester) async {
      await DeepdotsPopups.init(publicKey: 'k', autoTrack: const DeepdotsAutoTrack(scroll: false));
      final controller = await pumpList(tester);
      calls.clear();
      controller.jumpTo(700);
      await tester.pump();
      expect(methods(), isEmpty);

      await DeepdotsPopups.onScroll(30);
      expect(methods(), ['onScroll']);
    });
  });
}
