import 'dart:async';

import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

// Por defecto, el escenario `rate-product` de los test apps nativos en DEV (MAGICFEEDBACK_DEV,
// test-apps/scenarios.json del repo nativo): un popup que salta con el evento `rate_product`.
// Las claves públicas son públicas por diseño (van dentro de la app). Todo se puede cambiar con
// --dart-define (DD_KEY, DD_ENV=production, DD_LANG, DD_EVENT, DD_USER).
const _publicKey = String.fromEnvironment('DD_KEY', defaultValue: 'BxA1C4uaFsrQAR5PsYn4ESafn29jHAbd');
const _environment = String.fromEnvironment('DD_ENV') == 'production'
    ? DeepdotsEnvironment.production
    : DeepdotsEnvironment.development;
const _language = String.fromEnvironment('DD_LANG', defaultValue: 'en');
const _eventName = String.fromEnvironment('DD_EVENT', defaultValue: 'rate_product');

// Con --dart-define=DD_EVENT_AT_START=true el evento sale justo después de init(), antes de
// que el SDK haya bajado los popups de la API: sirve para probar que no se pierde.
const _eventAtStart = bool.fromEnvironment('DD_EVENT_AT_START');
// Con --dart-define=DD_AUTO_CLOSE_MS=… se llama a DeepdotsPopups.close() ese tiempo después de
// cada popup_shown: sirve para probar el cierre programático (el popup tapa los botones).
const _autoCloseMs = int.fromEnvironment('DD_AUTO_CLOSE_MS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeepdotsPopups.init(
    publicKey: _publicKey,
    environment: _environment,
    // El backend aplica el cooldown por userId: cámbialo con --dart-define=DD_USER=… para repetir.
    userId: const String.fromEnvironment('DD_USER', defaultValue: 'flutter-poc'),
    language: _language,
    debug: true,
  );
  if (_eventAtStart) await DeepdotsPopups.triggerEvent(_eventName);
  runApp(const PocApp());
}

class PocApp extends StatelessWidget {
  const PocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deepdots Flutter PoC',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      navigatorObservers: [DeepdotsNavigatorObserver()],
      initialRoute: '/home',
      routes: {
        '/home': (_) => const HomeScreen(),
        '/game': (_) => const GameScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _log = <String>[];
  StreamSubscription<DeepdotsEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = DeepdotsPopups.events.listen((e) {
      debugPrint('[PoC] $e');
      if (_autoCloseMs > 0 && e.type == 'popup_shown') {
        Future.delayed(const Duration(milliseconds: _autoCloseMs), DeepdotsPopups.close);
      }
      setState(() => _log.insert(0, e.toString()));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deepdots · Flutter PoC')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('trigger-event'),
              onPressed: () => DeepdotsPopups.triggerEvent(_eventName),
              child: const Text('Disparar evento "$_eventName"'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('go-game'),
              onPressed: () => Navigator.of(context).pushNamed('/game'),
              child: const Text('Ir a /game'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final user = await DeepdotsPopups.getUserId();
                final session = await DeepdotsPopups.getSessionId();
                setState(() => _log.insert(0, 'userId=$user sessionId=$session'));
              },
              child: const Text('Ver identidad'),
            ),
            const Divider(),
            const Text('Eventos del SDK nativo:'),
            Expanded(
              child: ListView(children: [for (final line in _log) Text(line)]),
            ),
          ],
        ),
      ),
    );
  }
}

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('/game')),
      // Contenido largo para probar los triggers de scroll: DeepdotsScrollListener reporta el %
      // del ListView al SDK (onScroll) sin más código en la pantalla.
      body: DeepdotsScrollListener(
        child: ListView.builder(
          key: const Key('game-list'),
          padding: const EdgeInsets.all(16),
          itemCount: 40,
          itemBuilder: (_, i) => i == 0
              ? const Text('Espera 5 segundos… o haz scroll para los triggers de scroll.')
              : ListTile(title: Text('Elemento $i')),
        ),
      ),
    );
  }
}
