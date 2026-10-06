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
import com.deepdots.sdk.models.ShowOptions
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
    // Lo que devuelve `provideLang`. El SDK nativo lo vuelve a leer cada vez que pinta un
    // popup, así que `setLanguage` lo cambia en caliente.
    @Volatile private var language: String? = null

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
        if (call.method == "setLanguage") {
            // Funciona también antes de init(): solo cambia lo que devolverá `provideLang`.
            language = call.argument<String>("language")
            result.success(null)
            return
        }
        val sdk = sdk ?: return result.error("not_initialized", "Call DeepdotsPopups.init() first", null)
        when (call.method) {
            "setPath" -> sdk.setPath(call.argument<String>("path"))
            "triggerEvent" -> sdk.triggerEvent(call.argument<String>("name")!!)
            "track" -> sdk.track(call.argument<String>("name")!!, call.argument<Map<String, Any?>>("params"))
            "setUserId" -> sdk.setUserId(call.argument<String>("userId"))
            "setTrackingEnabled" -> sdk.setTrackingEnabled(call.argument<Boolean>("enabled")!!)
            "onForeground" -> sdk.onForeground()
            "onBackground" -> sdk.onBackground()
            "getUserId" -> return result.success(sdk.getUserId())
            "getSessionId" -> return result.success(sdk.getSessionId())
            // Control manual de popups
            "show" -> sdk.show(
                ShowOptions(
                    surveyId = call.argument<String>("surveyId")!!,
                    productId = call.argument<String>("productId")!!,
                    data = call.argument<Map<String, Any?>>("data")?.withoutNulls(),
                ),
                platformContext(result) ?: return,
            )
            "showByPopupId" -> sdk.showByPopupId(call.argument<String>("popupId")!!, platformContext(result) ?: return)
            "triggerSurvey" -> sdk.triggerSurvey(
                call.argument<String>("surveyId")!!,
                platformContext(result) ?: return,
                call.argument<String>("popupId"),
            )
            "close" -> sdk.close(platformContext(result) ?: return)
            "markSurveyAnswered" -> sdk.markSurveyAnswered(call.argument<String>("surveyId")!!)
            "triggerClick" -> sdk.triggerClick(call.argument<String>("targetId")!!)
            else -> return result.notImplemented()
        }
        result.success(null)
    }

    private fun init(call: MethodCall) {
        if (sdk != null) return // init() es idempotente, igual que en el SDK nativo
        call.argument<String>("language")?.let { language = it } // valor inicial de setLanguage()
        val userId = call.argument<String>("userId")
        val analyticsPublicKey = call.argument<String>("analyticsPublicKey")
        val analyticsIntegration = call.argument<String>("analyticsIntegration")
        val options = InitOptions(
            debug = call.argument<Boolean>("debug") ?: false,
            environment = if (call.argument<String>("environment") == "development") Environment.Development else Environment.Production,
            popupOptions = PopupOptions(publicKey = call.argument<String>("publicKey")),
            provideLang = { this.language },
            autoLaunch = true,
            trackingEnabled = call.argument<Boolean>("trackingEnabled") ?: true,
            analytics = if (analyticsPublicKey != null && analyticsIntegration != null) {
                AnalyticsKeys(publicKey = analyticsPublicKey, integration = analyticsIntegration)
            } else null,
            metadata = buildMetadata(userId, call.argument<Map<String, Any?>>("metadata")),
            renderChrome = call.argument<Boolean>("renderChrome"),
            showProgressBar = call.argument<Boolean>("showProgressBar"),
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
            "extra" to channelSafe(data.extra),
            "timestamp" to data.timestamp,
        )
        mainHandler.post { channel.invokeMethod("onEvent", payload) }
    }

    /** `metadata` libre del host + `userId`, que gana. El SDK no admite valores nulos. */
    private fun buildMetadata(userId: String?, metadata: Map<String, Any?>?): Map<String, Any>? {
        val merged = metadata?.withoutNulls().orEmpty().toMutableMap()
        if (userId != null) merged["userId"] = userId
        return merged.ifEmpty { null }
    }

    private fun Map<String, Any?>.withoutNulls(): Map<String, Any> =
        entries.mapNotNull { (k, v) -> v?.let { k to it } }.toMap()

    /**
     * El `extra` de los eventos sale del JSON del survey (String, Boolean, Long, Double, listas y
     * mapas), pero el tipo es `Any?`: lo que el códec del canal no sepa serializar va como texto.
     */
    private fun channelSafe(value: Any?): Any? = when (value) {
        null, is String, is Boolean, is Int, is Long, is Double -> value
        is Number -> value.toDouble()
        is Map<*, *> -> value.entries.associate { (k, v) -> k.toString() to channelSafe(v) }
        is Iterable<*> -> value.map { channelSafe(it) }
        is Array<*> -> value.map { channelSafe(it) }
        else -> value.toString()
    }

    /** Contexto para los métodos que pintan o cierran un popup; sin Activity, error a Dart. */
    private fun platformContext(result: Result): PlatformContext? {
        val activity = activity
        if (activity == null) {
            result.error("no_context", "No Activity attached yet: cannot show or close popups", null)
            return null
        }
        return PlatformContext(activity)
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
