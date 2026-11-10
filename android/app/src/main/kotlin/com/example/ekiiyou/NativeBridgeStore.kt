package com.example.ekiiyou

import android.content.Context
import android.content.Intent
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

object NativeBridgeStore {
    private const val PREFS_NAME = "ekiiyou_native_store"
    private const val KEY_WORDS_JSON = "words_json"
    private const val KEY_CURRENT_INDEX = "current_word_index"
    private const val KEY_FLASHCARD_REVEALED = "flashcard_revealed"
    private const val KEY_REVIEWED_TODAY = "reviewed_today_count"
    private const val KEY_DAILY_TARGET = "daily_target"
    private const val KEY_TOTAL_WORDS = "total_words_count"
    private const val KEY_LANGUAGE_CODE = "language_code"
    private const val KEY_FLOATING_ENABLED = "floating_enabled"
    private const val KEY_FLOATING_INTERVAL = "floating_interval_minutes"
    private const val KEY_PENDING_REVIEWS = "pending_reviews_json"

    const val ACTION_QUICK_ADD = "com.example.ekiiyou.ACTION_QUICK_ADD"
    const val ACTION_START_REVIEW = "com.example.ekiiyou.ACTION_START_REVIEW"
    const val ACTION_OPEN_WORD = "com.example.ekiiyou.ACTION_OPEN_WORD"

    private var sharedMediaPlayer: MediaPlayer? = null
    private var sharedTts: TextToSpeech? = null
    private var sharedTtsReady = false

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun saveSyncPayload(
        context: Context,
        wordsJson: String,
        reviewedToday: Int,
        dailyTarget: Int,
        totalWords: Int,
        languageCode: String,
        floatingEnabled: Boolean,
        floatingIntervalMinutes: Int
    ) {
        prefs(context).edit()
            .putString(KEY_WORDS_JSON, wordsJson)
            .putInt(KEY_REVIEWED_TODAY, reviewedToday)
            .putInt(KEY_DAILY_TARGET, dailyTarget)
            .putInt(KEY_TOTAL_WORDS, totalWords)
            .putString(KEY_LANGUAGE_CODE, languageCode)
            .putBoolean(KEY_FLOATING_ENABLED, floatingEnabled)
            .putInt(KEY_FLOATING_INTERVAL, floatingIntervalMinutes.coerceAtLeast(15))
            .apply()
        refreshAllWidgets(context)
    }

    fun getWordsArray(context: Context): JSONArray {
        val raw = prefs(context).getString(KEY_WORDS_JSON, "[]") ?: "[]"
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    fun getCurrentWord(context: Context): JSONObject? {
        val arr = getWordsArray(context)
        if (arr.length() == 0) return null
        var idx = prefs(context).getInt(KEY_CURRENT_INDEX, 0)
        if (idx < 0 || idx >= arr.length()) {
            idx = 0
            prefs(context).edit().putInt(KEY_CURRENT_INDEX, 0).apply()
        }
        return arr.optJSONObject(idx)
    }

    fun advanceToNextWord(context: Context): JSONObject? {
        val arr = getWordsArray(context)
        if (arr.length() == 0) return null
        val nextIdx = (prefs(context).getInt(KEY_CURRENT_INDEX, 0) + 1) % arr.length()
        prefs(context).edit()
            .putInt(KEY_CURRENT_INDEX, nextIdx)
            .putBoolean(KEY_FLASHCARD_REVEALED, false)
            .apply()
        refreshAllWidgets(context)
        return arr.optJSONObject(nextIdx)
    }

    fun isFlashcardRevealed(context: Context): Boolean =
        prefs(context).getBoolean(KEY_FLASHCARD_REVEALED, false)

    fun setFlashcardRevealed(context: Context, revealed: Boolean) {
        prefs(context).edit().putBoolean(KEY_FLASHCARD_REVEALED, revealed).apply()
        refreshAllWidgets(context)
    }

    fun getReviewedToday(context: Context): Int =
        prefs(context).getInt(KEY_REVIEWED_TODAY, 0)

    fun getDailyTarget(context: Context): Int =
        prefs(context).getInt(KEY_DAILY_TARGET, 10)

    fun getTotalWords(context: Context): Int =
        prefs(context).getInt(KEY_TOTAL_WORDS, 0)

    fun isArabic(context: Context): Boolean =
        (prefs(context).getString(KEY_LANGUAGE_CODE, "ar") ?: "ar") == "ar"

    fun isFloatingEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_FLOATING_ENABLED, false)

    fun getFloatingIntervalMinutes(context: Context): Int =
        prefs(context).getInt(KEY_FLOATING_INTERVAL, 60).coerceAtLeast(15)

    fun recordNativeReview(context: Context, wordId: Int, remembered: Boolean) {
        val p = prefs(context)
        val pendingRaw = p.getString(KEY_PENDING_REVIEWS, "[]") ?: "[]"
        val pendingArr = try {
            JSONArray(pendingRaw)
        } catch (_: Exception) {
            JSONArray()
        }

        val entry = JSONObject().apply {
            put("wordId", wordId)
            put("remembered", remembered)
            put("timestamp", System.currentTimeMillis())
        }
        pendingArr.put(entry)

        val newReviewedToday = p.getInt(KEY_REVIEWED_TODAY, 0) + 1
        val wordsArr = getWordsArray(context)
        val nextIdx = if (wordsArr.length() > 0) {
            (p.getInt(KEY_CURRENT_INDEX, 0) + 1) % wordsArr.length()
        } else {
            0
        }

        p.edit()
            .putString(KEY_PENDING_REVIEWS, pendingArr.toString())
            .putInt(KEY_REVIEWED_TODAY, newReviewedToday)
            .putInt(KEY_CURRENT_INDEX, nextIdx)
            .putBoolean(KEY_FLASHCARD_REVEALED, false)
            .apply()

        refreshAllWidgets(context)
        MainActivity.notifyFlutterReviewRecorded()
    }

    fun drainPendingReviews(context: Context): String {
        val p = prefs(context)
        val raw = p.getString(KEY_PENDING_REVIEWS, "[]") ?: "[]"
        p.edit().putString(KEY_PENDING_REVIEWS, "[]").apply()
        return raw
    }

    fun playCurrentWordAudio(context: Context) {
        val wordObj = getCurrentWord(context) ?: return
        val wordText = wordObj.optString("word", "").trim()
        val localPath = wordObj.optString("audioLocalPath", "").trim()

        if (localPath.isNotBlank()) {
            val file = File(localPath)
            if (file.exists() && file.length() > 256) {
                try {
                    sharedMediaPlayer?.release()
                    sharedMediaPlayer = MediaPlayer().apply {
                        setDataSource(file.absolutePath)
                        prepare()
                        start()
                    }
                    return
                } catch (_: Exception) {
                }
            }
        }

        if (wordText.isNotBlank()) {
            val appCtx = context.applicationContext
            if (sharedTts == null) {
                sharedTts = TextToSpeech(appCtx) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        sharedTts?.language = Locale.US
                        sharedTtsReady = true
                        sharedTts?.speak(
                            wordText,
                            TextToSpeech.QUEUE_FLUSH,
                            null,
                            "ekiiyou_widget_tts"
                        )
                    }
                }
            } else if (sharedTtsReady) {
                sharedTts?.speak(
                    wordText,
                    TextToSpeech.QUEUE_FLUSH,
                    null,
                    "ekiiyou_widget_tts"
                )
            }
        }
    }

    fun refreshAllWidgets(context: Context) {
        try {
            ReviewWordWidgetProvider.updateAll(context)
            QuickAddWidgetProvider.updateAll(context)
            FlashcardWidgetProvider.updateAll(context)
        } catch (_: Exception) {}
    }

    fun createAppLaunchIntent(context: Context, action: String, wordId: Int? = null): Intent {
        return Intent(context, MainActivity::class.java).apply {
            this.action = action
            if (wordId != null) {
                putExtra("word_id", wordId)
            }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
    }
}
