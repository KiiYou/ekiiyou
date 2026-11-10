package com.example.ekiiyou

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var pendingLaunchPayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractLaunchPayload(intent)?.let {
            pendingLaunchPayload = it
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractLaunchPayload(intent)?.let { payload ->
            val ch = activeChannel
            if (ch != null) {
                ch.invokeMethod("onLaunchAction", payload)
            } else {
                pendingLaunchPayload = payload
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
        activeChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "syncState" -> {
                    val wordsJson = call.argument<String>("wordsJson") ?: "[]"
                    val reviewedToday = call.argument<Int>("reviewedToday") ?: 0
                    val dailyTarget = call.argument<Int>("dailyTarget") ?: 10
                    val totalWords = call.argument<Int>("totalWords") ?: 0
                    val languageCode = call.argument<String>("languageCode") ?: "ar"
                    val floatingEnabled = call.argument<Boolean>("floatingEnabled") ?: false
                    val floatingIntervalMinutes =
                        call.argument<Int>("floatingIntervalMinutes") ?: 60

                    NativeBridgeStore.saveSyncPayload(
                        context = applicationContext,
                        wordsJson = wordsJson,
                        reviewedToday = reviewedToday,
                        dailyTarget = dailyTarget,
                        totalWords = totalWords,
                        languageCode = languageCode,
                        floatingEnabled = floatingEnabled,
                        floatingIntervalMinutes = floatingIntervalMinutes
                    )
                    FloatingWordService.syncServiceState(
                        applicationContext,
                        showImmediately = false
                    )
                    result.success(true)
                }

                "drainPendingReviews" -> {
                    val json = NativeBridgeStore.drainPendingReviews(applicationContext)
                    result.success(json)
                }

                "checkOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }

                "requestOverlayPermission" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "showFloatingPopupNow" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        result.success(false)
                    } else {
                        FloatingWordService.syncServiceState(
                            applicationContext,
                            showImmediately = true
                        )
                        result.success(true)
                    }
                }

                "requestPinWidget" -> {
                    val widgetType = call.argument<String>("widgetType") ?: "review"
                    val pinned = requestPinHomeWidget(widgetType)
                    result.success(pinned)
                }

                "consumeLaunchAction" -> {
                    val payload = pendingLaunchPayload
                    pendingLaunchPayload = null
                    result.success(payload)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (activeChannel != null) {
            activeChannel = null
        }
        super.onDestroy()
    }

    private fun extractLaunchPayload(intent: Intent?): Map<String, Any?>? {
        val action = intent?.action ?: return null
        return when (action) {
            NativeBridgeStore.ACTION_QUICK_ADD -> mapOf("action" to "quick_add")
            NativeBridgeStore.ACTION_START_REVIEW -> mapOf("action" to "start_review")
            NativeBridgeStore.ACTION_OPEN_WORD -> {
                val wordId = intent.getIntExtra("word_id", -1).takeIf { it > 0 }
                mapOf("action" to "open_word", "wordId" to wordId)
            }
            else -> null
        }
    }

    private fun requestPinHomeWidget(widgetType: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val appWidgetManager = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!appWidgetManager.isRequestPinAppWidgetSupported) return false

        val providerClass = when (widgetType) {
            "quick_add" -> QuickAddWidgetProvider::class.java
            "flashcard" -> FlashcardWidgetProvider::class.java
            else -> ReviewWordWidgetProvider::class.java
        }
        val provider = ComponentName(this, providerClass)
        return try {
            appWidgetManager.requestPinAppWidget(provider, null, null)
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.example.ekiiyou/native_features"
        private var activeChannel: MethodChannel? = null

        fun notifyFlutterReviewRecorded() {
            Handler(Looper.getMainLooper()).post {
                try {
                    activeChannel?.invokeMethod("onNativeReviewRecorded", null)
                } catch (_: Exception) {
                }
            }
        }
    }
}
