package com.example.ekiiyou

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.Toast

class ReviewWordWidgetProvider : AppWidgetProvider() {

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
            ACTION_MARK_READ -> {
                val word = NativeBridgeStore.getCurrentWord(context)
                val wordId = word?.optInt("id", -1) ?: -1
                if (wordId > 0) {
                    NativeBridgeStore.recordNativeReview(context, wordId, true)
                    val msg = if (NativeBridgeStore.isArabic(context)) {
                        "✓ ممتاز! تم تسجيل قراءة الكلمة"
                    } else {
                        "✓ Great! Marked word as read"
                    }
                    Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                } else {
                    NativeBridgeStore.advanceToNextWord(context)
                }
            }
            ACTION_NEXT_WORD -> {
                NativeBridgeStore.advanceToNextWord(context)
            }
        }
    }

    companion object {
        const val ACTION_MARK_READ = "com.example.ekiiyou.WIDGET_MARK_READ"
        const val ACTION_NEXT_WORD = "com.example.ekiiyou.WIDGET_NEXT_WORD"

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ReviewWordWidgetProvider::class.java)
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
            val views = RemoteViews(context.packageName, R.layout.widget_review_word)
            val isAr = NativeBridgeStore.isArabic(context)
            val reviewed = NativeBridgeStore.getReviewedToday(context)
            val target = NativeBridgeStore.getDailyTarget(context)
            val wordObj = NativeBridgeStore.getCurrentWord(context)

            views.setTextViewText(
                R.id.widget_header_title,
                if (isAr) "EKiiYou • كلمة للمراجعة" else "EKiiYou • Review Word"
            )
            views.setTextViewText(R.id.widget_progress_badge, "$reviewed/$target")

            val wordId: Int?
            if (wordObj != null) {
                wordId = wordObj.optInt("id", -1).takeIf { it > 0 }
                val wordText = wordObj.optString("word", "")
                val arabicText = wordObj.optString("arabicMeaning", "")
                val defText = wordObj.optString("englishDefinition", "")
                val exText = wordObj.optString("exampleSentence", "")

                views.setTextViewText(R.id.widget_english_word, wordText)
                views.setTextViewText(
                    R.id.widget_arabic_meaning,
                    if (arabicText.isNotBlank()) arabicText else defText
                )
                views.setTextViewText(
                    R.id.widget_definition,
                    when {
                        defText.isNotBlank() -> defText
                        exText.isNotBlank() -> exText
                        else -> if (isAr) "اضغط على الكلمة لفتح التفاصيل والنطق" else "Tap word for details & audio"
                    }
                )
            } else {
                wordId = null
                views.setTextViewText(
                    R.id.widget_english_word,
                    if (isAr) "أضف كلمتك الأولى ✨" else "Add your first word ✨"
                )
                views.setTextViewText(
                    R.id.widget_arabic_meaning,
                    if (isAr) "اضغط على زر ＋ لإضافة كلمة جديدة" else "Tap ＋ to add a new vocabulary word"
                )
                views.setTextViewText(
                    R.id.widget_definition,
                    "EKiiYou Smart Vocabulary Notebook"
                )
            }

            views.setTextViewText(
                R.id.btn_mark_read,
                if (isAr) "✓ قرأتها" else "✓ Read"
            )
            views.setTextViewText(
                R.id.btn_next_word,
                if (isAr) "↻ التالية" else "↻ Next"
            )

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

            // Mark Read broadcast
            val markReadIntent = Intent(context, ReviewWordWidgetProvider::class.java).apply {
                action = ACTION_MARK_READ
            }
            views.setOnClickPendingIntent(
                R.id.btn_mark_read,
                PendingIntent.getBroadcast(context, 101, markReadIntent, flags)
            )

            // Next Word broadcast
            val nextIntent = Intent(context, ReviewWordWidgetProvider::class.java).apply {
                action = ACTION_NEXT_WORD
            }
            views.setOnClickPendingIntent(
                R.id.btn_next_word,
                PendingIntent.getBroadcast(context, 102, nextIntent, flags)
            )

            // Quick Add launch
            val quickAddIntent = NativeBridgeStore.createAppLaunchIntent(
                context,
                NativeBridgeStore.ACTION_QUICK_ADD
            )
            views.setOnClickPendingIntent(
                R.id.btn_quick_add_small,
                PendingIntent.getActivity(context, 103, quickAddIntent, flags)
            )

            // Open Word / App on word container tap
            val openWordIntent = if (wordId != null) {
                NativeBridgeStore.createAppLaunchIntent(
                    context,
                    NativeBridgeStore.ACTION_OPEN_WORD,
                    wordId
                )
            } else {
                NativeBridgeStore.createAppLaunchIntent(
                    context,
                    NativeBridgeStore.ACTION_QUICK_ADD
                )
            }
            views.setOnClickPendingIntent(
                R.id.widget_word_container,
                PendingIntent.getActivity(context, 104, openWordIntent, flags)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
