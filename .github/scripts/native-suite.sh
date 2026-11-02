#!/usr/bin/env bash
# Fetches the Maestro suite of the native SDK's test apps (test-apps/maestro + scripts) at
# $NATIVE_TEST_APPS_REF into native-suite/ and points it at the example app. Exports NATIVE_SDK,
# the native version the plugin wraps (the runner uses it for the known issues of each version).
set -euo pipefail

gradle=$(sed -n 's/.*com\.deepdots\.sdk:shared-android:\([0-9.]*\)".*/\1/p' android/build.gradle.kts)
spm=$(sed -n 's/.*DeepdotsSDK-SPM", exact: "\([0-9.]*\)".*/\1/p' ios/deepdots_popups/Package.swift)
pod=$(sed -n "s/^DEEPDOTS_SDK_VERSION = '\([0-9.]*\)'.*/\1/p" ios/deepdots_popups.podspec)
echo "[lab] native SDK: gradle=$gradle spm=$spm podspec=$pod"
if [ -z "$gradle" ] || [ "$gradle" != "$spm" ] || [ "$gradle" != "$pod" ]; then
  echo "::error::[lab] the plugin wraps different native versions (gradle=$gradle spm=$spm podspec=$pod)"
  exit 1
fi
echo "NATIVE_SDK=$gradle" >> "${GITHUB_ENV:-/dev/null}"

rm -rf native-suite && mkdir -p native-suite/src
curl -fsSL "https://codeload.github.com/$NATIVE_REPO/tar.gz/$NATIVE_TEST_APPS_REF" | tar -xz -C native-suite/src
cp -R native-suite/src/*/test-apps/maestro native-suite/src/*/test-apps/scripts native-suite/
rm -rf native-suite/src
# Same flows, other app: the example's app id, and its iOS process for the device log.
grep -rl com.deepdots.testapp native-suite | xargs sed -i.bak 's/com\.deepdots\.testapp/com.deepdots.flutterexample/g'
sed -i.bak 's/process == "NordlyTestApp"/process == "Runner"/' native-suite/scripts/run-maestro.sh
find native-suite -name '*.bak' -delete
echo "[lab] native suite $NATIVE_REPO@$NATIVE_TEST_APPS_REF: $(ls native-suite/maestro/flows native-suite/maestro/failures | grep -c yaml) flows"
