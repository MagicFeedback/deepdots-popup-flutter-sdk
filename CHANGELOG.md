## 1.1.0

* Native Deepdots SDK 0.7.11 (was 0.7.9; 0.7.10 was never published). Changes that reach
  Flutter apps:
  * Popups draw the survey with the survey version assigned in the Admin when the native SDK
    supports its survey SDK (2.2.38, 2.2.39); otherwise the bundled one (2.2.39, was 2.2.31).
    See docs.deepdots.com/popup-native/reference/survey-compatibility/.
  * The popup's own texts in the 24 official EU languages, and error notices in the survey's
    language.
  * "Please enter a valid email address." for an email with a typo.
  * The batch that closes an analytics session is resent on the next `init()` if the app died
    before it was sent.
* Popup responses and analytics say they came from this plugin: `deepdots_sdk=flutter@<version>`
  (and `deepdots_channel=popup` on responses), with the native SDK in `deepdots_sdk_core`
  (`android@0.7.11` / `ios@0.7.11`). The version comes from `lib/src/version.dart`, which a test
  keeps equal to `version:` in pubspec.yaml.

## 1.0.1

Same plugin and native SDK as 1.0.0 (0.7.9); first version on pub.dev.

* Install it with `deepdots_popups: ^1.0.1`. Installing from git with a tag (`ref: v1.0.1`) still
  works.
* Package metadata, documentation links and formatting for pub.dev. No change in behaviour.

## 1.0.0

First release (no longer a beta). Same Dart API as 0.1.0-beta.2; install it with `ref: v1.0.0`.

* Known limitation: a Flutter dialog does not hold a popup back (README, Known limitations).

* Native Deepdots SDK 0.7.9 (was 0.7.6). Fixes that reach Flutter apps:
  * iOS: a popup triggered right after launch is shown (it was counted as shown but not
    presented). The README limitation is removed.
  * A time-on-screen popup is scheduled once (up to 0.7.5 it could show twice at app start).
  * No Back button on the first screen after a failed Send; the "required" message stays.
  * The title and the close button (X) stay visible when the survey is taller than the screen.
  * iOS: a popup at the top stays inside the safe area (not under the status bar).
  * iOS: the keyboard no longer covers Back and Send; a survey taller than its box scrolls.
  * Android 8–10: the keyboard no longer covers Back and Send; Send, Back and close work on old
    WebViews (Chrome < 80).

## 0.1.0-beta.2

* Supports Flutter 3.24 or later (Dart 3.5); it required Flutter 3.47 before. Apps on AGP 8 now
  build: the plugin applies the Kotlin plugin itself when the Android Gradle plugin does not
  compile Kotlin. Apps created with Flutter 3.24 to 3.32 need a newer Android toolchain
  (INSTALL.md).
* Apache License 2.0.
* README in English for pub.dev; the internal notes moved to `doc/development.md`.

## 0.1.0-beta.1

First beta.

* Native Deepdots SDK 0.7.6: Android from Maven Central (`com.deepdots.sdk:shared-android`), iOS
  from `MagicFeedback/DeepdotsSDK-SPM` (Swift Package Manager, or CocoaPods through the same
  XCFramework with a sha256 check).
* Dart API over the native SDK: `init`, navigation (`DeepdotsNavigatorObserver`, `setPath`),
  triggers (`triggerEvent`, `triggerClick`, `triggerSurvey`, scroll with `DeepdotsScrollListener`,
  exit), manual `show`/`showByPopupId`/`close`, language, user and contact attributes, analytics
  tracking, and the `events` and `feedbackSessions` streams.
* App lifecycle handled by the plugin (foreground/background).
* The plugin declares the `INTERNET` permission on Android, so release builds reach the API.
