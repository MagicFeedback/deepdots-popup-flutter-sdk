# deepdots_popups (prueba de concepto)

Plugin de Flutter que envuelve el SDK nativo de Deepdots (KMP, repo
`deepdots-popup-mobile-native-sdk`) para Android e iOS. No reimplementa lógica: la API de Dart
traduce cada llamada a `DeepdotsPopups` nativo por un `MethodChannel` y reenvía sus eventos.

**Estado: prueba de concepto, no publicable.** El SDK nativo va vendorizado (0.6.0, compilado
desde `origin/dev` el 2026-10-06): repo Maven local en `android/maven` y XCFramework en
`ios/deepdots_popups/Frameworks`.

## Uso

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DeepdotsPopups.init(publicKey: '…', userId: 'user-123', language: 'da');
  runApp(MaterialApp(
    navigatorObservers: [DeepdotsNavigatorObserver()], // setPath automático
    routes: {...},
  ));
}

DeepdotsPopups.triggerEvent('general-survey');
DeepdotsPopups.events.listen((e) => print(e)); // popup_shown, popup_clicked, survey_completed
```

El ciclo de vida (`onForeground`/`onBackground`) se conecta solo con `AppLifecycleListener`,
usando `hide`/`show` y no `inactive`, porque en el SDK nativo `onBackground()` cierra la sesión.

Control manual, idioma y opciones de `init`:

```dart
DeepdotsPopups.init(
  publicKey: '…',
  userId: 'user-123',
  renderChrome: false,            // sin scrim ni tarjeta: el host pone el marco
  showProgressBar: true,          // null = lo que diga el survey en la plataforma
  metadata: {'plan': 'pro'},      // nulos fuera; `userId` gana sobre metadata['userId']
);
DeepdotsPopups.show('survey-id', 'product-id', {'source': 'banner'}); // sin triggers ni segmentación
DeepdotsPopups.showByPopupId('popup-id');
DeepdotsPopups.triggerSurvey('survey-id');  // respeta segmentación y cooldown
DeepdotsPopups.triggerClick('buy-button');
DeepdotsPopups.close();
DeepdotsPopups.setLanguage('es');           // textos del chrome del siguiente popup
```

`show`, `showByPopupId`, `triggerSurvey` y `close` fallan con `PlatformException(no_context)` si
aún no hay Activity (Android) o root view controller (iOS). `DeepdotsEvent` trae además `extra`
(p. ej. `action` en `popup_clicked`, o el `data` de `show` en `popup_shown`) y `timestamp`.
`setLanguage` no cambia el idioma del contexto de analytics: el SDK nativo lo resuelve una vez en
`init()`. En iOS, `close()` cierra lo que esté presentado sobre el root view controller, sea o no
el popup (así lo implementa el SDK nativo).

Triggers de scroll y de salida:

- **Scroll:** envolver el cuerpo de la pantalla en `DeepdotsScrollListener(child: ListView(...))`.
  Reporta `onScroll` (0-100, scrollable principal vertical) solo cuando cambia el entero. Con
  scroll propio, `DeepdotsPopups.onScroll(pct)` a mano.
- **Salida (`exit`):** automático con `DeepdotsNavigatorObserver`, sin llamar a `onExit()`: el
  `setPath` nativo de la ruta nueva ya encola los popups de salida de la anterior.
  `DeepdotsPopups.onExit()` solo sirve para adelantar la cuenta atrás (botón Atrás propio,
  llamado ANTES de navegar), como en los ejemplos nativos.

Requisitos del host:

- **Android:** `MainActivity` tiene que extender `FlutterFragmentActivity`. El popup es Compose
  y el renderer de KMP exige una `ComponentActivity`. Con `FlutterActivity` no sale nada y el
  SDK no avisa (el plugin escribe un aviso en logcat).
- **iOS:** excluir `x86_64` en el simulador (`EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`):
  el SDK KMP no trae slice `iosX64`. Solo afecta a simuladores en Macs Intel.

## Qué se verificó (2026-10-06)

En el emulador Android (API 36) y en el simulador iOS (iPhone 17 Pro, iOS 26.5):

- `init` desde Dart: el SDK baja las definiciones de la API y registra los triggers.
- Trigger por evento (`triggerEvent`) y por tiempo en página (vía
  `DeepdotsNavigatorObserver`): el popup nativo se pinta encima de Flutter con scrim y tarjeta.
- **El survey carga dentro del popup** con la clave del demo público de docs.deepdots.com
  (popup "Event rateing", evento `custom-event`): capturas en `docs/screenshots/`.
- El estado del popup llega al backend (el cooldown de servidor por `userId` lo confirma).
- Los eventos nativos llegan a Dart (`popup_shown`, `popup_clicked`).
- Ir a segundo plano cierra la sesión de analytics (`session_end: background`).

No se probó a responder y enviar el survey, para no mandar respuestas reales al demo.

| Android | iOS |
|---|---|
| ![Android](docs/screenshots/android-survey.png) | ![iOS](docs/screenshots/ios-survey.png) |

## Hallazgos

1. **Android, `FlutterActivity`:** ver requisitos arriba. Se puede arreglar en KMP montando el
   `ComposeView` con `ViewTreeLifecycleOwner`/`SavedStateRegistryOwner` propios, y así
   funcionaría con cualquier `Activity`.
2. **Android, botón Atrás:** no cierra el popup, cierra la app. El renderer de KMP no
   intercepta el Atrás. Seguramente pasa igual en nativo.
3. **iOS, presentación:** el popup se presenta desde el `rootViewController`. Si el host tiene
   un VC nativo presentado encima (picker, share sheet), UIKit no deja presentar y no sale.
4. **Eventos antes de cargar las definiciones:** un `triggerEvent` que llega antes de que el
   SDK baje los popups de la API se descarta (`No eligible event popup`), no se encola. Se
   reprodujo pulsando el botón nada más arrancar. Pasa igual en nativo.
5. **`popup_clicked` al cargar:** KMP emite `popup_clicked` hacia el host cuando el survey carga
   (o falla), sin interacción. No toca el estado del backend (PARTIAL solo con
   `action == "partial"`), pero confunde a quien lo escuche. Pasa igual en nativo.
6. **Tamaño:** el XCFramework estático ocupa 231 MB (símbolos de depuración incluidos). El
   binario final de la app es mucho menor, pero para publicar conviene tirar del paquete SPM y
   del artefacto de Maven Central, no vendorizar.
7. **Distribución:** para publicar en pub.dev, el plugin necesita el SDK nativo publicado:
   Maven Central (parado en 0.3.0) y SPM (`DeepdotsSDK-SPM`).

## Regenerar el SDK vendorizado

Desde un worktree limpio del repo KMP:

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :shared:publishAndroidReleasePublicationToReleaseStagingRepository :shared:publishKotlinMultiplatformPublicationToReleaseStagingRepository :shared:assembleSharedReleaseXCFramework -PskipGradleSigning=true
```

Copiar `build/release-staging-repo/com` a `android/maven/` y
`shared/build/XCFrameworks/release/shared.xcframework` a
`ios/deepdots_popups/Frameworks/DeepdotsSDK.xcframework`.

## Ejecutar el ejemplo

Por defecto usa la clave del demo de docs.deepdots.com (`DD_KEY`, `DD_LANG`, `DD_EVENT` la
cambian). El backend aplica el cooldown por `userId`; para repetir, cambia el usuario:

```bash
cd example && flutter run --dart-define=DD_USER=flutter-poc-3
```
