package com.example.ekiiyou

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast

class FlashcardWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REVEAL -> {
                NativeBridgeStore.setFlashcardRevealed(context, true)
            }
            ACTION_REMEMBERED -> {
                val word = NativeBridgeStore.getCurrentWord(context)
                val wordId = word?.optInt("id", -1) ?: -1
                if (wordId > 0) {
                    NativeBridgeStore.recordNativeReview(context, wordId, true)
                    val msg = if (NativeBridgeStore.isArabic(context)) {
                        "✓ رائع! تم تسجيل تذكّر الكلمة"
                    } else {
                        "✓ Awesome! Marked as remembered"
                    }
                    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                } else {
                    NativeBridgeStore.advanceToNextWord(context)
                }
            }
            ACTION_FORGOT -> {
                val word = NativeBridgeStore.getCurrentWord(context)
                val wordId = word?.optInt("id", -1) ?: -1
                if (wordId > 0) {
                    NativeBridgeStore.recordNativeReview(context, wordId, false)
                    val msg = if (NativeBridgeStore.isArabic(context)) {
                        "↻ سنذكرك بها قريباً لتثبيتها"
                    } else {
                        "↻ Scheduled for quick review soon"
                    }
                    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                } else {
                    NativeBridgeStore.advanceToNextWord(context)
                }
            }
        }
    }

    companion object {
        const val ACTION_REVEAL = "com.example.ekiiyou.FLASHCARD_REVEAL"
        const val ACTION_REMEMBERED = "com.example.ekiiyou.FLASHCARD_REMEMBERED"
        const val ACTION_FORGOT = "com.example.ekiiyou.FLASHCARD_FORGOT"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, FlashcardWidgetProvider::class.java)
            )
            if (ids.isNotEmpty()) {
                for (id in ids) {
                    updateWidget(context, manager, id)
                }
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_flashcard)
            val isAr = NativeBridgeStore.isArabic(context)
            val reviewed = NativeBridgeStore.getReviewedToday(context)
            val target = NativeBridgeStore.getDailyTarget(context)
            val revealed = NativeBridgeStore.isFlashcardRevealed(context)
            val wordObj = NativeBridgeStore.getCurrentWord(context)

            views.setTextViewText(R.id.flashcard_progress_badge, "$reviewed/$target")

            if (wordObj != null) {
                val wordText = wordObj.optString("word", "")
                val arabicText = wordObj.optString("arabicMeaning", "")
                val defText = wordObj.optString("englishDefinition", "")
                val answerDisplay = when {
                    arabicText.isNotBlank() && defText.isNotBlank() -> "$arabicText\n$defText"
                    arabicText.isNotBlank() -> arabicText
                    defText.isNotBlank() -> defText
                    else -> "—"
                }

                views.setTextViewText(R.id.flashcard_english_word, wordText)
                if (revealed) {
                    views.setTextViewText(R.id.flashcard_answer_text, answerDisplay)
                    views.setTextColor(R.id.flashcard_answer_text, Color.parseColor("#60A5FA"))
                    views.setViewVisibility(R.id.btn_flashcard_reveal, View.GONE)
                    views.setViewVisibility(R.id.flashcard_answer_actions, View.VISIBLE)
                } else {
                    views.setTextViewText(
                        R.id.flashcard_answer_text,
                        if (isAr) "فكّر في المعنى ثم اضغط إظهار المعنى" else "Think of the meaning, then tap Show Answer"
                    )
                    views.setTextColor(R.id.flashcard_answer_text, Color.parseColor("#94A3B8"))
                    views.setViewVisibility(R.id.btn_flashcard_reveal, View.VISIBLE)
                    views.setViewVisibility(R.id.flashcard_answer_actions, View.GONE)
                }
            } else {
                views.setTextViewText(
                    R.id.flashcard_english_word,
                    if (isAr) "لا توجد كلمات بعد" else "No words yet"
                )
                views.setTextViewText(
                    R.id.flashcard_answer_text,
                    if (isAr) "افتح التطبيق لإضافة كلماتك" else "Open the app to add words"
                )
                views.setViewVisibility(R.id.btn_flashcard_reveal, View.VISIBLE)
                views.setViewVisibility(R.id.flashcard_answer_actions, View.GONE)
            }

            views.setTextViewText(
                R.id.btn_flashcard_reveal,
                if (isAr) "👁 إظهار المعنى" else "👁 Show Meaning"
            )
            views.setTextViewText(
                R.id.btn_flashcard_forgot,
                if (isAr) "✗ نسيتها" else "✗ Forgot"
            )
            views.setTextViewText(
                R.id.btn_flashcard_remembered,
                if (isAr) "✓ تذكرتها" else "✓ Remembered"
            )

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

            val revealIntent = Intent(context, FlashcardWidgetProvider::class.java).apply {
                action = ACTION_REVEAL
            }
            views.setOnClickPendingIntent(
                R.id.btn_flashcard_reveal,
                PendingIntent.getBroadcast(context, 301, revealIntent, flags)
            )

            val forgotIntent = Intent(context, FlashcardWidgetProvider::class.java).apply {
                action = ACTION_FORGOT
            }
            views.setOnClickPendingIntent(
                R.id.btn_flashcard_forgot,
                PendingIntent.getBroadcast(context, 302, forgotIntent, flags)
            )

            val rememberedIntent = Intent(context, FlashcardWidgetProvider::class.java).apply {
                action = ACTION_REMEMBERED
            }
            views.setOnClickPendingIntent(
                R.id.btn_flashcard_remembered,
                PendingIntent.getBroadcast(context, 303, rememberedIntent, flags)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
