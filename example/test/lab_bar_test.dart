import 'package:deepdots_popups_example/lab.dart';
import 'package:deepdots_popups_example/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The Maestro flows of the native test apps find the run by these ids (subflows/launch.yaml).
void main() {
  testWidgets('the Lab bar shows the run and the tabs carry their ids', (tester) async {
    final semantics = tester.ensureSemantics();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('nordly/lab'),
      (call) async => switch (call.method) {
        'launchArguments' => {'scenario': 'rate-product'},
        'load' => {'consent': 'all'},
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(const MethodChannel('com.deepdots/popups'), (call) async => null);
    final scenarios = await Scenarios.load(rootBundle);
    final config = await LabConfig.resolve(scenarios);
    await tester.pumpWidget(NordlyApp(host: SdkHost(config, scenarios)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsIdentifier('lab-env'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
    expect(find.bySemanticsIdentifier('lab-scenario'), findsOneWidget);
    expect(find.text('rate-product'), findsOneWidget);
    expect(find.bySemanticsIdentifier('lab-open'), findsOneWidget);
    for (final tab in ['tab-home', 'tab-shop', 'tab-cart', 'tab-account']) {
      expect(find.bySemanticsIdentifier(tab), findsOneWidget);
    }

    await tester.tap(find.bySemanticsIdentifier('tab-cart'));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);
    semantics.dispose();
  });
}
