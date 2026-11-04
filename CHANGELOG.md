## Unreleased

* Popup responses and analytics say they came from this plugin: `deepdots_sdk=flutter@<version>`
  (and `deepdots_channel=popup` on responses), with the native SDK in `deepdots_sdk_core`. Needs
  the native Deepdots SDK release that adds `SdkIdentity` (after 0.7.9). The version comes from
  `lib/src/version.dart`, which a test keeps equal to `version:` in pubspec.yaml.

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
