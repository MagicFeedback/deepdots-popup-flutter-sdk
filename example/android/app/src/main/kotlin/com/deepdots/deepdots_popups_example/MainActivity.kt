package com.deepdots.deepdots_popups_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// La FlutterActivity por defecto: desde el arreglo de KMP (fix/popup-any-activity) el popup
// nativo ya no necesita una ComponentActivity.
class MainActivity : FlutterActivity() {
    // `nordly/lab` (lib/lab.dart): the run's launch arguments (Maestro `launchApp: arguments`
    // and `adb shell am start --es` arrive as intent extras) and the saved run config.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val prefs = getSharedPreferences("lab", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nordly/lab").setMethodCallHandler { call, result ->
            when (call.method) {
                "launchArguments" -> result.success(
                    LAUNCH_KEYS.mapNotNull { key -> intent?.extras?.get(key)?.let { key to it.toString() } }.toMap()
                )
                "load" -> result.success(prefs.all.mapValues { it.value.toString() })
                "save" -> {
                    val edit = prefs.edit()
                    (call.arguments as Map<*, *>).forEach { (key, value) -> edit.putString(key as String, value as String) }
                    edit.apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        val LAUNCH_KEYS = listOf("scenario", "nav", "lang", "load", "user", "start", "consent", "instances", "event")
    }
}
