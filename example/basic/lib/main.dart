import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

// Minimal host (the native test apps' "basic app" in Flutter): init, the navigator observer and
// one screen, nothing else. The client popup of the DEV scenario `client-exact-launch` opens by
// itself at app start (time on page 5 s). DEV keys only (MAGICFEEDBACK_DEV); a key is public by
// design, it ships inside the app. Another DEV key: --dart-define=publicKey=<key>.
const publicKey = String.fromEnvironment('publicKey', defaultValue: '9C1hiLhDp7Jq5hKyFyjppXiEJ1DfeTAl');

/// Native SDK the plugin wraps; shown on the screen.
const nativeSdkVersion = '0.7.9';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // debug: SDK log lines in logcat / the Xcode console, as in the example app.
  await DeepdotsPopups.init(publicKey: publicKey, environment: DeepdotsEnvironment.development, debug: true);
  runApp(const BasicApp());
}

class BasicApp extends StatelessWidget {
  const BasicApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Basic',
    debugShowCheckedModeBanner: false,
    navigatorObservers: [DeepdotsNavigatorObserver()],
    initialRoute: '/',
    routes: {
      '/': (_) => const Scaffold(
        body: Center(child: Text('Basic app · SDK $nativeSdkVersion · Flutter', style: TextStyle(fontSize: 20))),
      ),
    },
  );
}
