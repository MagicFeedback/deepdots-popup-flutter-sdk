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
