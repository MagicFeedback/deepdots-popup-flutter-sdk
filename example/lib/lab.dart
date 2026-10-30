import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Backend the app talks to. There is no production option: test data stays in MAGICFEEDBACK_DEV.
const devAPI = 'https://api-dev.deepdots.com';

/// Native SDK the plugin wraps (android/build.gradle.kts, ios/deepdots_popups/Package.swift and
/// the podspec). Shown in the Lab bar; keep it in sync when the plugin moves to another version.
const nativeSdkVersion = '0.7.5';

/// Launch arguments and the saved run config live on the native side (example's MainActivity /
/// AppDelegate): Maestro passes `launchApp: arguments` as intent extras / process arguments.
const _channel = MethodChannel('nordly/lab');

/// One DEV popup config (public key) per scenario, from assets/scenarios.json: a copy of
/// test-apps/scenarios.json in the native SDK repo, without the customer replicas.
class Scenarios {
  Scenarios._(this._scenarios);

  final Map<String, Map<String, Object?>> _scenarios;

  static Future<Scenarios> load(AssetBundle bundle) async {
    final json = jsonDecode(await bundle.loadString('assets/scenarios.json')) as Map<String, Object?>;
    final scenarios = (json['scenarios'] as Map<String, Object?>).map(
      (name, value) => MapEntry(name, Map<String, Object?>.from(value as Map)),
    );
    return Scenarios._(scenarios);
  }

  List<String> get names => _scenarios.keys.toList()..sort();
  String? publicKey(String name) => _scenarios[name]?['publicKey'] as String?;
  List<String> events(String name) => [...?(_scenarios[name]?['events'] as List?)?.cast<String>()];
}

/// What a run tests. Maestro passes it as launch arguments; the SDK Lab panel edits it. It is
/// saved, so a relaunch without arguments (re-display, background tests) keeps the same run.
class LabConfig {
  const LabConfig({
    this.scenario = 'checkout-time',
    this.nav = 'history',
    this.lang = 'en',
    this.load = 'immediate',
    this.user = '',
    this.start = 'home',
    this.consent,
  });

  final String scenario;

  /// `history`: every screen calls setPath(). `silent`: the app never tells the SDK it navigated.
  final String nav;
  final String lang;

  /// `immediate`: init at launch. `consent`: init after "Accept all" in the cookie dialog.
  final String load;
  final String user;

  /// First screen: home, shop, cart, checkout or account (one-shot, not saved).
  final String start;

  /// Cookie choice: null (not asked yet), `all` or `necessary`.
  final String? consent;

  static const _saved = ['scenario', 'nav', 'lang', 'load', 'user'];

  /// Saved config, overridden by any launch argument (or `--dart-define=scenario=…` in
  /// `flutter run`). An unknown scenario falls back to the default one.
  static Future<LabConfig> resolve(Scenarios scenarios) async {
    final args = <String, String>{
      ..._dartDefines(),
      ...?(await _channel.invokeMapMethod<String, String>('launchArguments')),
    };
    final saved = await _channel.invokeMapMethod<String, String>('load') ?? const {};
    String read(String key, String fallback) => args[key] ?? saved[key] ?? fallback;
    const base = LabConfig();
    var scenario = read('scenario', base.scenario);
    if (scenarios.publicKey(scenario) == null) scenario = base.scenario;
    final config = LabConfig(
      scenario: scenario,
      nav: read('nav', base.nav),
      lang: read('lang', base.lang),
      load: read('load', base.load),
      user: read('user', base.user),
      start: args['start'] ?? base.start,
      consent: saved['consent'],
    );
    if (_saved.any(args.containsKey)) await config.save();
    return config;
  }

  static Map<String, String> _dartDefines() => {
    if (const String.fromEnvironment('scenario').isNotEmpty) 'scenario': const String.fromEnvironment('scenario'),
    if (const String.fromEnvironment('nav').isNotEmpty) 'nav': const String.fromEnvironment('nav'),
    if (const String.fromEnvironment('lang').isNotEmpty) 'lang': const String.fromEnvironment('lang'),
    if (const String.fromEnvironment('load').isNotEmpty) 'load': const String.fromEnvironment('load'),
    if (const String.fromEnvironment('user').isNotEmpty) 'user': const String.fromEnvironment('user'),
    if (const String.fromEnvironment('start').isNotEmpty) 'start': const String.fromEnvironment('start'),
  };

  LabConfig copyWith({String? scenario, String? nav, String? lang, String? load}) => LabConfig(
    scenario: scenario ?? this.scenario,
    nav: nav ?? this.nav,
    lang: lang ?? this.lang,
    load: load ?? this.load,
    user: user,
    start: start,
    consent: consent,
  );

  Future<void> save() =>
      _channel.invokeMethod('save', {'scenario': scenario, 'nav': nav, 'lang': lang, 'load': load, 'user': user});

  static Future<void> saveConsent(String consent) => _channel.invokeMethod('save', {'consent': consent});
}

/// Run log: on screen (SDK Lab) and in the device log with the `[lab]` prefix, which is what CI
/// keeps (logcat tag `flutter` on Android, the Runner process on iOS).
class Lab {
  Lab._();

  static final lines = ValueNotifier<List<String>>(const []);

  static void log(String tag, String message) {
    debugPrint('[lab] $tag $message');
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${two(now.hour)}:${two(now.minute)}:${two(now.second)} $tag $message';
    final next = [...lines.value, line];
    lines.value = next.length > 200 ? next.sublist(next.length - 200) : next;
  }
}
