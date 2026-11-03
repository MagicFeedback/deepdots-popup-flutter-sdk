#!/usr/bin/env bash
# Install test: a new app from `flutter create` (the installed Flutter's own template), with the
# plugin added the way INSTALL.md says, built in release. This is what a client's first build does.
#
#   install-test.sh <android|ios-spm|ios-pods> <plugin source> [app dir]
#
# Plugin source: `path:<dir>` (this checkout) or `git:<ref>` (a tag or commit of the GitHub repo).
set -euo pipefail

platform=$1
source=$2
app=${3:-${RUNNER_TEMP:-/tmp}/install_test_app}
repo_url=${PLUGIN_GIT_URL:-https://github.com/MagicFeedback/deepdots-popup-flutter-sdk.git}

flutter --version
rm -rf "$app"
case $platform in
  android) platforms=android ;;
  ios-*) platforms=ios ;;
  *) echo "::error::unknown platform $platform"; exit 2 ;;
esac
flutter create --platforms="$platforms" --org com.example --project-name install_test "$app"
cd "$app"

case $source in
  path:*) dep="    path: ${source#path:}" ;;
  git:*) dep=$(printf '    git:\n      url: %s\n      ref: %s' "$repo_url" "${source#git:}") ;;
  *) echo "::error::unknown plugin source $source"; exit 2 ;;
esac
# Under `dependencies:`, as a client would write it. Through the environment: the awk of macOS
# does not take a value with newlines in `-v`.
DEP="$dep" awk '{print} /^dependencies:/ {print "  deepdots_popups:"; print ENVIRON["DEP"]}' pubspec.yaml > pubspec.tmp
mv pubspec.tmp pubspec.yaml
cat > lib/main.dart <<'DART'
import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DeepdotsPopups.init(publicKey: 'install-test');
  runApp(MaterialApp(
    navigatorObservers: [DeepdotsNavigatorObserver()],
    home: const Scaffold(body: Center(child: Text('install test'))),
  ));
}
DART
rm -rf test
flutter pub get

case $platform in
  android)
    # INSTALL.md, step 2 (Android): compileSdk 36 and Kotlin 2.1 or later. Templates of Flutter
    # before 3.35 have older values; newer ones already meet both.
    for f in android/app/build.gradle android/app/build.gradle.kts; do
      [ -f "$f" ] && perl -pi -e 's/compileSdk(Version)?( =|) flutter\.compileSdkVersion/compileSdk$1$2 36/; s/minSdk(Version)?( =|) flutter\.minSdkVersion/minSdk$1$2 24/' "$f"
    done
    for f in android/settings.gradle android/settings.gradle.kts; do
      [ -f "$f" ] && perl -pi -e 's/("org\.jetbrains\.kotlin\.android"\)? version ")(1\.[0-9.]+|2\.0\.[0-9]+)"/${1}2.1.21"/' "$f"
    done
    if [ "${LEGACY_TOOLCHAIN:-0}" = 1 ]; then
      for f in android/settings.gradle android/settings.gradle.kts; do
        [ -f "$f" ] && perl -pi -e 's/("com\.android\.application"\)? version ")[0-9.]+"/${1}8.9.1"/' "$f"
      done
      perl -pi -e 's/gradle-[0-9.]+-(all|bin)\.zip/gradle-8.11.1-$1.zip/' android/gradle/wrapper/gradle-wrapper.properties
      grep -h distributionUrl android/gradle/wrapper/gradle-wrapper.properties
    fi
    grep -hE 'compileSdk|minSdk|kotlin.android|com.android.application' android/app/build.gradle* android/settings.gradle* || true
    flutter build apk --release
    apk=build/app/outputs/flutter-apk/app-release.apk
    aapt2=$(ls -d "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)
    if [ -n "$aapt2" ]; then
      "$aapt2" dump permissions "$apk" | tee permissions.txt
      grep -q android.permission.INTERNET permissions.txt || { echo "::error::release APK without INTERNET"; exit 1; }
    fi
    ;;
  ios-*)
    # INSTALL.md, step 2: iOS 13 or later (the template of older Flutter versions targets 12).
    sed -i.bak -E 's/IPHONEOS_DEPLOYMENT_TARGET = (9|1[0-2])\.0;/IPHONEOS_DEPLOYMENT_TARGET = 13.0;/' ios/Runner.xcodeproj/project.pbxproj
    rm -f ios/Runner.xcodeproj/project.pbxproj.bak
    ;;
esac

case $platform in
  android) ;;
  ios-spm)
    flutter config --enable-swift-package-manager
    # INSTALL.md, step 2 (Swift Package Manager).
    for f in ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig; do
      echo 'EXCLUDED_ARCHS[sdk=iphonesimulator*] = i386 x86_64' >> "$f"
    done
    # Resolve the Swift packages first, with a time limit and the log: a stuck fetch shows here.
    flutter build ios --config-only --simulator --debug
    perl -e 'alarm 600; exec @ARGV' xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme Runner \
      || { echo "::error::Swift package resolution failed or took more than 10 minutes"; exit 1; }
    flutter build ios --simulator --debug
    flutter build ios --release --no-codesign
    grep -rq DeepdotsSDK-SPM ios/Runner.xcodeproj ios/Runner.xcworkspace 2>/dev/null \
      || grep -rq DeepdotsSDK-SPM ios/Flutter/ephemeral 2>/dev/null \
      || { echo "::error::the iOS build did not use Swift Package Manager"; exit 1; }
    ;;
  ios-pods)
    flutter config --no-enable-swift-package-manager || true
    # The Podfile is written by the first iOS build of an app with plugins.
    flutter build ios --config-only --simulator --debug
    sed -i.bak -E "s/^# ?platform :ios, '[0-9.]+'/platform :ios, '13.0'/" ios/Podfile && rm -f ios/Podfile.bak
    # INSTALL.md, step 2 (CocoaPods).
    ruby -i -pe '$_ += <<~RUBY if $_ =~ /^post_install do \|installer\|/
      installer.aggregate_targets.each do |aggregate|
        aggregate.user_project.native_targets.each do |target|
          target.build_configurations.each do |config|
            config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "i386 x86_64"
          end
        end
        aggregate.user_project.save
      end
    RUBY' ios/Podfile
    grep -q 'EXCLUDED_ARCHS' ios/Podfile || { echo "::error::Podfile has no post_install block"; cat ios/Podfile; exit 1; }
    flutter build ios --simulator --debug
    flutter build ios --release --no-codesign
    grep -q 'deepdots_popups' ios/Podfile.lock || { echo "::error::the iOS build did not use CocoaPods"; exit 1; }
    ;;
esac
echo "[install-test] $platform with $source: OK"
