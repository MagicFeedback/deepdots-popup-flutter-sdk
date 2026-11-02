# NORDLY (Flutter)

A small test shop that integrates `deepdots_popups` the way a customer's app would. It is the
Flutter twin of the native SDK's test apps (`test-apps/` in deepdots-popup-mobile-native-sdk):
same screens, accessibility ids, scenarios and launch arguments, so the native Maestro flows run
against it unchanged (only the `appId` differs).

- It always uses **DEV** (`DeepdotsEnvironment.development`, `api-dev.deepdots.com`, company
  MAGICFEEDBACK_DEV). The public keys in `assets/scenarios.json` are public by design: they are
  what an app ships with.
- App id `com.deepdots.flutterexample` on Android and iOS.
- The **SDK Lab** bar on top shows the native SDK version, the environment and the scenario; the
  gear opens the Lab panel (ids, scenario events, run log). Every step is logged with the `[lab]`
  prefix (logcat tag `flutter` on Android, the `Runner` process on iOS).

## Integration points worth reading

- `lib/main.dart` · `SdkHost`: `DeepdotsPopups.init()` (at launch, or after the cookie consent
  with `load=consent`), popup events, `triggerEvent()` / `triggerClick()`.
- `MaterialApp.navigatorObservers: [DeepdotsNavigatorObserver()]`: every named route goes to
  `setPath()`; dialogs and bottom sheets are not screens and are ignored.
- `lib/shop.dart`: routes `/`, `/shop`, `/product/<id>`, `/cart`, `/checkout`, `/account`;
  **Product › Rate › Submit rating** fires `rate_product`, **Account › Help** fires the click
  trigger `help-button`, the Shop list reports scroll with `DeepdotsScrollListener`.
- App lifecycle: nothing to do, the plugin calls `onBackground()` / `onForeground()` itself.

## Run

```bash
flutter run --dart-define=scenario=rate-product
```

| Argument | Values | What it does |
|---|---|---|
| `scenario` | see `assets/scenarios.json` | Which DEV popup config (public key) the SDK loads. |
| `nav` | `history` · `silent` | `silent` leaves out the navigator observer: the SDK never sees the navigation. |
| `lang` | `en` · `es` | Language passed to `init()` (audience segmentation). |
| `load` | `immediate` · `consent` | Init at launch, or after "Accept all" in the cookie dialog. |
| `user` | text | `userId` for `init()`. Without it the SDK uses its anonymous id. |
| `start` | `home` · `shop` · `cart` · `checkout` · `account` | First screen (not saved). |

They are read from launch arguments (Maestro `launchApp: arguments`, `adb shell am start --es`,
`-key value` on iOS) or `--dart-define`, and saved, so a relaunch without arguments keeps the same
run. The Lab panel can change them (**Apply & quit**; the new run starts on the next launch).

The backend shows a popup once per user and cooldown: reinstall the app (or clear its data) to
see it again, as the Maestro flows do with `clearState`.

## Maestro suite of the native test apps

```bash
# from a checkout of deepdots-popup-mobile-native-sdk
cp -R test-apps/maestro test-apps/scripts /tmp/nordly-flutter/
grep -rl com.deepdots.testapp /tmp/nordly-flutter | xargs sed -i '' 's/com\.deepdots\.testapp/com.deepdots.flutterexample/g'
DEVICE=<udid or serial> /tmp/nordly-flutter/scripts/run-maestro.sh ios 0.7.6 out/ios
```

30 Oct 2026, plugin on native 0.7.5: all flows pass on the iOS simulator (iPhone 17 Pro, iOS
26.5) and the Android emulator (API 36), as on the native apps; `rate-product-close` is the
known 0.7.5 issue (popup title on two lines hides the X).

2 Nov 2026, plugin on native 0.7.6: `rate-product` and `rate-product-close` pass on the iOS
simulator and the X shows next to a two-line title; the full suite runs in CI on both platforms.
