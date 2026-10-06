package com.deepdots.deepdots_popups

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import com.deepdots.sdk.DeepdotsPopups
import com.deepdots.sdk.analytics.AnalyticsKeys
import com.deepdots.sdk.models.Environment
import com.deepdots.sdk.models.Event
import com.deepdots.sdk.models.EventData
import com.deepdots.sdk.models.InitOptions
import com.deepdots.sdk.models.PopupOptions
import com.deepdots.sdk.models.code
import com.deepdots.sdk.platform.PlatformContext
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Puente Flutter -> SDK nativo KMP. No reimplementa nada: traduce las llamadas del canal a la
 * API pública de `DeepdotsPopups` y reenvía los eventos del SDK a Dart.
 */
class DeepdotsPopupsPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sdk: DeepdotsPopups? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "init") {
            init(call)
            result.success(null)
            return
        }
        val sdk = sdk ?: return result.error("not_initialized", "Call DeepdotsPopups.init() first", null)
        when (call.method) {
            "setPath" -> sdk.setPath(call.argument<String>("path"))
            "triggerEvent" -> sdk.triggerEvent(call.argument<String>("name")!!)
            "onScroll" -> sdk.onScroll(call.argument<Int>("percentage")!!)
            "onExit" -> sdk.onExit()
            "track" -> sdk.track(call.argument<String>("name")!!, call.argument<Map<String, Any?>>("params"))
            "setUserId" -> sdk.setUserId(call.argument<String>("userId"))
            "setTrackingEnabled" -> sdk.setTrackingEnabled(call.argument<Boolean>("enabled")!!)
            "onForeground" -> sdk.onForeground()
            "onBackground" -> sdk.onBackground()
            "getUserId" -> return result.success(sdk.getUserId())
            "getSessionId" -> return result.success(sdk.getSessionId())
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    private fun init(call: MethodCall) {
        if (sdk != null) return // init() es idempotente, igual que en el SDK nativo
        val language = call.argument<String>("language")
        val userId = call.argument<String>("userId")
        val analyticsPublicKey = call.argument<String>("analyticsPublicKey")
        val analyticsIntegration = call.argument<String>("analyticsIntegration")
        val options = InitOptions(
            debug = call.argument<Boolean>("debug") ?: false,
            environment = if (call.argument<String>("environment") == "development") Environment.Development else Environment.Production,
            popupOptions = PopupOptions(publicKey = call.argument<String>("publicKey")),
            provideLang = { language },
            autoLaunch = true,
            trackingEnabled = call.argument<Boolean>("trackingEnabled") ?: true,
            analytics = if (analyticsPublicKey != null && analyticsIntegration != null) {
                AnalyticsKeys(publicKey = analyticsPublicKey, integration = analyticsIntegration)
            } else null,
            metadata = userId?.let { mapOf("userId" to it) },
        )
        val instance = DeepdotsPopups()
        instance.init(options)
        Event.entries.forEach { event ->
            instance.on(event) { data -> emit(event, data) }
        }
        sdk = instance
        attachActivity()
    }

    private fun emit(event: Event, data: EventData) {
        val payload = mapOf(
            "type" to event.code(),
            "popupId" to data.popupId,
            "surveyId" to data.surveyId,
            "productId" to data.productId,
        )
        mainHandler.post { channel.invokeMethod("onEvent", payload) }
    }

    private fun attachActivity() {
        val activity = activity ?: return
        if (activity !is ComponentActivity) {
            // El renderer de KMP monta un ComposeView y necesita ComponentActivity; con la
            // FlutterActivity por defecto el popup no se pinta y el SDK no avisa.
            Log.w(TAG, "${activity.javaClass.simpleName} is not a ComponentActivity: popups will not render. " +
                "Make MainActivity extend io.flutter.embedding.android.FlutterFragmentActivity.")
        }
        sdk?.attachContext(PlatformContext(activity))
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        attachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private companion object {
        const val CHANNEL = "com.deepdots/popups"
        const val TAG = "DeepdotsPopups"
    }
}
