import 'dart:async';

import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lab.dart';
import 'lab_panel.dart';
import 'shop.dart';

// NORDLY, the test shop of the native SDK's test apps (test-apps/ in deepdots-popup-mobile-native-sdk),
// on Flutter: the same screens, accessibility ids, scenarios and launch arguments, so a run is the
// same on the three apps. It always uses DEV (MAGICFEEDBACK_DEV); the public keys in
// assets/scenarios.json are public by design (they ship inside a customer's app).
//
//   flutter run --dart-define=scenario=rate-product      # or any scenario in assets/scenarios.json
//
// Launch arguments (Maestro `launchApp: arguments`, `adb shell am start --es`, `-key value` on iOS)
// override the saved run: scenario, nav (history|silent), lang, load (immediate|consent), user,
// start (home|shop|cart|checkout|account).

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scenarios = await Scenarios.load(rootBundle);
  final config = await LabConfig.resolve(scenarios);
  runApp(NordlyApp(host: SdkHost(config, scenarios)));
}

/// Owns the SDK, as a host app would. The plugin feeds it the app lifecycle by itself.
class SdkHost {
  SdkHost(this.config, this.scenarios);

  final LabConfig config;
  final Scenarios scenarios;
  final initialized = ValueNotifier(false);
  StreamSubscription<DeepdotsEvent>? _events;

  String get publicKey => scenarios.publicKey(config.scenario) ?? '';

  Future<void> init() async {
    if (initialized.value) return;
    initialized.value = true;
    final c = config;
    Lab.log('sdk', 'init $nativeSdkVersion (Flutter) env=Development api=$devAPI');
    Lab.log('sdk', 'scenario=${c.scenario} key=$publicKey nav=${c.nav} lang=${c.lang}');
    _events = DeepdotsPopups.events.listen((e) {
      switch (e.type) {
        case 'popup_shown':
          Lab.log('popup', 'shown id=${e.popupId} survey=${e.surveyId}');
        case 'popup_clicked':
          Lab.log('popup', 'clicked id=${e.popupId} action=${e.extra['action'] ?? ''}');
        case 'survey_completed':
          Lab.log('popup', 'survey_completed survey=${e.surveyId}');
      }
    });
    await DeepdotsPopups.init(
      publicKey: publicKey,
      environment: DeepdotsEnvironment.development,
      userId: c.user.isEmpty ? null : c.user,
      language: c.lang,
      debug: true,
    );
    Lab.log('sdk', 'userId=${await DeepdotsPopups.getUserId() ?? '-'}');
  }

  void triggerEvent(String name) {
    if (initialized.value) DeepdotsPopups.triggerEvent(name);
  }

  void triggerClick(String id) {
    if (initialized.value) DeepdotsPopups.triggerClick(id);
  }

  void dispose() => _events?.cancel();
}

class NordlyApp extends StatefulWidget {
  const NordlyApp({super.key, required this.host});

  final SdkHost host;

  @override
  State<NordlyApp> createState() => _NordlyAppState();
}

class _NordlyAppState extends State<NordlyApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _route = ValueNotifier<String>('/');
  late final Shop _shop = Shop(
    host: widget.host,
    navigator: _navigator,
    flash: (message) => _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2))),
  );
  late final AppLifecycleListener _lifecycle;

  LabConfig get _config => widget.host.config;

  @override
  void initState() {
    super.initState();
    // Logged only: the plugin already calls onBackground()/onForeground() on hide/show.
    _lifecycle = AppLifecycleListener(
      onHide: () => Lab.log('life', 'background'),
      onShow: () => Lab.log('life', 'foreground'),
    );
    if (_config.load == 'immediate' || _config.consent == 'all') widget.host.init();
    if (_config.consent == null) WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.host.dispose();
    super.dispose();
  }

  Future<void> _askConsent() async {
    final context = _navigator.currentContext;
    if (context == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Cookies'),
        content: const Text('We use cookies to improve your experience.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Necessary only')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accept all')),
        ],
      ),
    );
    if (accepted == true) {
      await LabConfig.saveConsent('all');
      Lab.log('host', 'consent accepted');
      // The path reported before init() is kept by the plugin and sent once init() finishes.
      await widget.host.init();
    } else {
      await LabConfig.saveConsent('necessary');
      Lab.log('host', 'consent necessary only');
    }
  }

  @override
  Widget build(BuildContext context) {
    final silent = _config.nav == 'silent';
    return MaterialApp(
      title: 'NORDLY',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      theme: ThemeData(colorSchemeSeed: ink, useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFFAFAFA)),
      // The plugin's observer is all a host needs: every named route goes to setPath().
      // `nav=silent` leaves it out, so the SDK never sees the navigation.
      navigatorObservers: [
        _RouteLog(_route, silent: silent),
        if (!silent) DeepdotsNavigatorObserver(),
      ],
      initialRoute: Shop.startRoute(_config.start),
      onGenerateInitialRoutes: (initial) => [if (initial == '/checkout') _shop.route('/cart'), _shop.route(initial)],
      onGenerateRoute: (settings) => _shop.route(settings.name ?? '/'),
      builder: (context, child) => Material(
        color: const Color(0xFFFAFAFA),
        child: Column(
          children: [
            _LabBar(host: widget.host, onOpen: _openLab),
            // The Lab bar takes the status bar inset: the screens' AppBar must not add it again.
            // Own semantics container: a route's BlockSemantics hides what was painted before it in
            // the same container, which would take the Lab bar out of the accessibility tree.
            Expanded(
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: MediaQuery.removePadding(context: context, removeTop: true, child: child!),
              ),
            ),
            const _LabLog(),
            ValueListenableBuilder(
              valueListenable: _route,
              builder: (_, route, _) => route == '/checkout' ? const SizedBox.shrink() : _shop.tabBar(route),
            ),
          ],
        ),
      ),
    );
  }

  void _openLab() {
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LabPanel(
          host: widget.host,
          onEvent: (event) {
            _navigator.currentState?.pop();
            Lab.log('host', 'triggerEvent($event)');
            widget.host.triggerEvent(event);
          },
        ),
      ),
    );
  }
}

/// Logs every screen change (`nav a → b`) and keeps the current one for the tab bar. Unnamed
/// routes (dialogs, sheets, the Lab panel) are not screens.
class _RouteLog extends NavigatorObserver {
  _RouteLog(this.current, {required this.silent});

  final ValueNotifier<String> current;
  final bool silent;
  String? _previous;

  void _changed(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (route is! PageRoute || name == null || name == _previous) return;
    Lab.log('nav', '${_previous ?? 'launch'} → $name${silent ? ' (silent: no setPath)' : ''}');
    _previous = name;
    current.value = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _changed(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _changed(previousRoute);
}

class _LabBar extends StatelessWidget {
  const _LabBar({required this.host, required this.onOpen});

  final SdkHost host;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12, color: labText);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        color: labBg,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, left: 12),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const Text(
                'SDK Lab',
                style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Semantics(
                identifier: 'lab-sdk-version',
                container: true,
                child: const Text('$nativeSdkVersion · Flutter', style: style),
              ),
              const SizedBox(width: 8),
              Semantics(
                identifier: 'lab-env',
                container: true,
                child: const Text('DEV', style: TextStyle(fontSize: 12, color: Color(0xFF6EE8A8))),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Semantics(
                  identifier: 'lab-scenario',
                  container: true,
                  child: Text(
                    host.config.scenario,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                  ),
                ),
              ),
              const Spacer(),
              Semantics(
                identifier: 'lab-open',
                container: true,
                // A label, not a tooltip: the Lab bar sits above the Navigator, with no Overlay.
                label: 'Open SDK Lab',
                child: IconButton(
                  onPressed: onOpen,
                  icon: const Icon(Icons.settings, color: labText, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabLog extends StatelessWidget {
  const _LabLog();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'lab-log',
      child: Container(
        color: labBg,
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ValueListenableBuilder(
          valueListenable: Lab.lines,
          builder: (_, lines, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines.length > 3 ? lines.sublist(lines.length - 3) : lines)
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: labText),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
