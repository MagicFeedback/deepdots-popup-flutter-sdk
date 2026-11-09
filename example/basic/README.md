# basic_example

Minimal host app for `deepdots_popups`: `DeepdotsPopups.init()` before `runApp`, the
`DeepdotsNavigatorObserver` and one screen. It is the Flutter form of the native test apps' "basic
app" and runs the Maestro `basic/` flows (app id `com.deepdots.flutterbasic`).

DEV only (MAGICFEEDBACK_DEV): by default it uses the DEV scenario `client-exact-launch`, whose popup
opens by itself 5 s after launch. Another DEV key: `flutter run --dart-define=publicKey=<key>`.
