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
