import 'dart:io';

import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:deepdots_popups/src/version.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `deepdots_sdk=flutter@<versión>` tiene que llevar la versión publicada: la del pubspec.
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('la versión del plugin coincide con la del pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(deepdotsPopupsVersion, version);
  });

  test('init se identifica ante el nativo como flutter@<versión>', () async {
    await DeepdotsPopups.init(publicKey: 'pk');
    final args = calls.firstWhere((c) => c.method == 'init').arguments as Map;
    expect(args['sdkName'], 'flutter');
    expect(args['sdkVersion'], deepdotsPopupsVersion);
  });
}
