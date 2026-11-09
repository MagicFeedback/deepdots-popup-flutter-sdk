# deepdots_popups — install guide

Flutter plugin for Deepdots popups and surveys. It wraps the native Deepdots SDK for Android and
iOS: targeting, triggers, sessions, analytics and the survey UI all run in the native SDK, and the
plugin exposes them to Dart and wires in Flutter's navigation and app lifecycle.

| | |
|---|---|
| Plugin | `1.0.1` |
| Native SDK | `0.7.9` (Android: Maven Central; iOS: Swift Package Manager or CocoaPods) |
| Flutter | 3.24 or later (Dart 3.5). Build checked on every stable release from 3.24 to 3.47 |
| Android | minSdk 24, compileSdk 36; Android Gradle plugin 8.9.1, Gradle 8.11.1, Kotlin 2.1 or later |
| iOS | 13.0 or later; Swift Package Manager needs Flutter 3.41 or later, CocoaPods works on all |

## 1. Add the dependency

The plugin is on [pub.dev](https://pub.dev/packages/deepdots_popups):

```bash
flutter pub add deepdots_popups
```

or in `pubspec.yaml`:

```yaml
dependencies:
  deepdots_popups: ^1.0.1
```

`^1.0.1` takes every 1.x release (fixes and new features) with `flutter pub upgrade`, never a 2.0.

**Alternative: from git.** Apps that already install it from GitHub can keep doing so. Pin `ref`
to a release tag, and change the tag to update:

```yaml
dependencies:
  deepdots_popups:
    git:
      url: https://github.com/MagicFeedback/deepdots-popup-flutter-sdk.git
      ref: v1.0.1
```

```bash
flutter pub get
```

## 2. Platform setup

### Android

Apps created with Flutter 3.35 or later need nothing. The native SDK comes from Maven Central
(`mavenCentral()` is in the repositories of a default Flutter project), the plugin declares the
`INTERNET` permission, and any `Activity` works, including the default `FlutterActivity`.

Apps created with an older Flutter (3.24 to 3.32) need a newer Android toolchain than their
template, because of the libraries the native SDK uses. In `android/settings.gradle(.kts)`:

```kotlin
id("com.android.application") version "8.9.1" apply false       // or later
id("org.jetbrains.kotlin.android") version "2.1.21" apply false  // 2.1 or later
```

In `android/gradle/wrapper/gradle-wrapper.properties`, Gradle 8.11.1 or later:

```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-all.zip
```

In `android/app/build.gradle(.kts)`, inside `android { ... }`:

```kotlin
compileSdk = 36
defaultConfig {
    minSdk = 24
}
```

Without these, the build stops with a message that names the missing version (for example
"requires Android Gradle plugin 8.9.1 or higher" or "compiled with an incompatible version of
Kotlin").

### iOS

The app must target iOS 13.0 or later. Apps created with Flutter 3.32 or earlier target 12.0:
raise `IPHONEOS_DEPLOYMENT_TARGET` to 13.0 in Xcode (Runner target, General → Minimum
Deployments) and, with CocoaPods, set `platform :ios, '13.0'` at the top of `ios/Podfile`.

Flutter builds iOS plugins with Swift Package Manager when it is enabled, and with CocoaPods
otherwise. Both work; Swift Package Manager needs Flutter 3.41 or later. On an older Flutter with
Swift Package Manager enabled, the build fails with "The folder FlutterFramework doesn't exist":
turn it off with `flutter config --no-enable-swift-package-manager` and the app uses CocoaPods. The native SDK ships no `x86_64` simulator slice, so Intel
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

## Known limitations

- A dialog or bottom sheet drawn by Flutter (`showDialog`, `showModalBottomSheet`) does not hold a
  popup back: the native SDK waits only for native dialogs, so a popup on a timer (for example 5 s
  after launch) can open over your own consent dialog. If your app asks for consent at start, call
  `DeepdotsPopups.init()` after the user answers it.
- Flutter 3.24 to 3.32: the Android toolchain changes of step 2 are needed.
