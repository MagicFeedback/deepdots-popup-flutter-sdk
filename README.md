# deepdots_popups

Deepdots popups and surveys for Flutter apps. The plugin wraps the native Deepdots SDK for Android
and iOS: targeting, triggers, sessions, analytics and the survey UI all run in the native SDK. The
plugin exposes them to Dart and connects them to Flutter's navigation and app lifecycle.

> **Early access.** The API may still change before 1.0. Pin the version you install.

| | |
|---|---|
| Native SDK | `0.7.6` (Android: Maven Central; iOS: Swift Package Manager or CocoaPods) |
| Flutter | 3.24 or later (Dart 3.5) |
| Android | minSdk 24, compileSdk 36 (apps from Flutter 3.24–3.32 need a newer Android toolchain, see [INSTALL.md](INSTALL.md)) |
| iOS | 13.0 or later (Swift Package Manager from Flutter 3.41; CocoaPods on all) |

## Install

```yaml
# pubspec.yaml
dependencies:
  deepdots_popups:
    git:
      url: https://github.com/MagicFeedback/deepdots-popup-flutter-sdk.git
      ref: v0.1.0-beta.1
```

On iOS, exclude the Intel simulator architecture (one line in two xcconfig files, or a few lines
in the Podfile). [INSTALL.md](INSTALL.md) explains this step and the rest of the setup.

## Quick start

```dart
import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeepdotsPopups.init(publicKey: '<your public key>');
  runApp(MaterialApp(
    // Reports named routes to the SDK: page targeting, time on page and exit triggers.
    navigatorObservers: [DeepdotsNavigatorObserver()],
    routes: {...},
  ));
}

// Popups configured on an event or a click:
DeepdotsPopups.triggerEvent('purchase_completed');
DeepdotsPopups.triggerClick('help-button');

// What happens with them:
DeepdotsPopups.events.listen((e) => print(e.type)); // popup_shown, popup_clicked, survey_completed
```

The app lifecycle (foreground and background) is handled by the plugin. Scroll triggers need the
scrollable body wrapped in `DeepdotsScrollListener`.

## API

| Call | What it does |
|---|---|
| `init(publicKey:, userId:, language:, environment:, trackingEnabled:, …)` | Starts the SDK and loads the popups of the account. |
| `setPath(path)` | Reports the current screen when you do not use named routes. |
| `triggerEvent(name)` / `triggerClick(id)` | Shows the popup configured on that event or click, if the user is eligible. |
| `triggerSurvey(surveyId)` | Shows a survey's popup, respecting targeting and cooldown. |
| `show(surveyId, productId)` / `showByPopupId(id)` | Shows a popup right away, without triggers or targeting. |
| `close()` | Closes the popup on screen. |
| `setUserId(id)` / `setLanguage(code)` / `setTrackingEnabled(on)` | Identity, language of the next popup and consent. |
| `track(name, params)`, `setMetric`, `trackFunnelStep`, `trackSearch`, … | Product analytics events, sent with the user's session. |
| `events` | Stream of `DeepdotsEvent` (`popup_shown`, `popup_clicked`, `survey_completed`). |

## Known limitations

- `setLanguage` changes the texts from the next popup on. The language of analytics is set in
  `init()`.
- iOS: a popup triggered in the first instant after launch may not be shown although it is counted
  as shown. Trigger popups after the first frame. A fix is coming in the native SDK.

## Example

[`example/`](example) is a small shop app that uses every feature of the plugin against a Deepdots
test account. [example/README.md](example/README.md) explains how to run it.

## License

See [LICENSE](LICENSE).
