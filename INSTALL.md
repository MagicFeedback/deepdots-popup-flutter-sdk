# deepdots_popups — install guide (beta)

Flutter plugin for Deepdots popups and surveys. It wraps the native Deepdots SDK for Android and
iOS: targeting, triggers, sessions, analytics and the survey UI all run in the native SDK, and the
plugin exposes them to Dart and wires in Flutter's navigation and app lifecycle.

| | |
|---|---|
| Plugin | `0.1.0-beta.1` |
| Native SDK | `0.7.6` (Android: Maven Central; iOS: Swift Package Manager or CocoaPods) |
| Tested with | Flutter 3.47.6 (Dart 3.13) |
| Android | minSdk 24, compileSdk 36 |
| iOS | 13.0 or later |

## 1. Add the dependency

The beta is installed from git, pinned to a release tag:

```yaml
# pubspec.yaml
dependencies:
  deepdots_popups:
    git:
      url: https://github.com/MagicFeedback/deepdots-popup-flutter-sdk.git
      ref: v0.1.0-beta.1
```

```bash
flutter pub get
```

Always pin `ref` to a tag. Updating is a matter of changing the tag.

## 2. Platform setup

### Android

Nothing to add. The native SDK comes from Maven Central (`mavenCentral()` must be in your
repositories, which it is in a default Flutter project), and the plugin declares the `INTERNET`
permission. Any `Activity` works, including the default `FlutterActivity`.

### iOS

Flutter builds iOS plugins with Swift Package Manager when it is enabled, and with CocoaPods
otherwise. Both work. The native SDK ships no `x86_64` simulator slice, so Intel
simulator builds must be excluded:

- **Swift Package Manager:** add this line at the end of both `ios/Flutter/Debug.xcconfig` and
  `ios/Flutter/Release.xcconfig`:

  ```
  EXCLUDED_ARCHS[sdk=iphonesimulator*] = i386 x86_64
  ```

- **CocoaPods:** add this to the `post_install` block of `ios/Podfile`:

  ```ruby
  installer.aggregate_targets.each do |aggregate|
    aggregate.user_project.native_targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386 x86_64'
      end
    end
    aggregate.user_project.save
  end
  ```

  With CocoaPods, `pod install` downloads the SDK's XCFramework and checks its sha256.

Without this, `flutter run` on an Apple Silicon simulator still works, but
`flutter build ios --simulator` fails to link.

## 3. Integrate

```dart
import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeepdotsPopups.init(
    publicKey: '<your public key>',   // from the Deepdots admin
    userId: currentUser?.id,          // optional; can be set later with setUserId()
    language: 'en',                   // optional
  );
  runApp(MaterialApp(
    // Reports every named route to the SDK: page targeting, time on page and exit triggers.
    navigatorObservers: [DeepdotsNavigatorObserver()],
    routes: {...},
  ));
}
```

- **Navigation:** `DeepdotsNavigatorObserver` reports routes that have a name (`RouteSettings.name`),
  such as `/checkout`. Dialogs and bottom sheets are ignored. With a router that does not use
  named routes, call `DeepdotsPopups.setPath('/checkout')` yourself when the screen changes.
- **Lifecycle:** handled by the plugin (app hidden and shown); nothing to call.
- **Events:** popups configured on an event appear when you call
  `DeepdotsPopups.triggerEvent('purchase_completed')`. For a click trigger, call
  `DeepdotsPopups.triggerClick('help-button')`.
- **Scroll triggers:** wrap the scrollable body in `DeepdotsScrollListener(child: ListView(...))`.
- **Consent:** call `init()` only after the user has accepted, or pass `trackingEnabled: false`
  and switch it on later with `DeepdotsPopups.setTrackingEnabled(true)`.

Other calls you may need:

```dart
await DeepdotsPopups.setUserId('user-123');      // after login; null on logout
await DeepdotsPopups.setLanguage('da');          // texts of the next popup
await DeepdotsPopups.triggerSurvey('survey-id'); // respects targeting and cooldown
await DeepdotsPopups.close();

DeepdotsPopups.events.listen((e) {
  // e.type: popup_shown, popup_clicked, survey_completed
});
```

### Test environment

`init()` uses production by default. To try popups set up in a Deepdots test account, pass
`environment: DeepdotsEnvironment.development` with that account's public key, and `debug: true`
to see the SDK's log (`[DeepdotsPopups]` lines in logcat / the Xcode console). Do not ship either
setting in a release build.

## 4. Troubleshooting

- **No popup appears.** Check that the public key belongs to the environment you selected and that
  the popup is active and targets the current route or event. A popup that has already been shown
  to a user is usually not shown to the same user again: use a new `userId` to test it again.
- **iOS link error `Undefined symbol: _OBJC_CLASS_$_DSDK…` or `Module 'deepdots_popups' not
  found`.** The `EXCLUDED_ARCHS` setting from step 2 is missing.
- **`PlatformException(no_context)`** from `show`, `showByPopupId`, `triggerSurvey` or `close`:
  the call happened before the app had a visible screen. Call it after the first frame.

## Known limitations of the beta

- Installed from git only (not on pub.dev yet).
- The plugin requires Dart 3.13 (Flutter 3.47) or later. Tell us if your app is on an older
  Flutter version.
