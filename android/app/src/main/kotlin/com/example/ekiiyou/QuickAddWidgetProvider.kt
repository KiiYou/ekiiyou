package com.example.ekiiyou

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews

class QuickAddWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, QuickAddWidgetProvider::class.java)
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
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
            val isAr = NativeBridgeStore.isArabic(context)
            val reviewed = NativeBridgeStore.getReviewedToday(context)
            val target = NativeBridgeStore.getDailyTarget(context)
            val total = NativeBridgeStore.getTotalWords(context)

            views.setTextViewText(
                R.id.quick_progress_title,
                if (isAr) {
                    "مراجعة اليوم: $reviewed من $target"
                } else {
                    "Today's Review: $reviewed of $target"
                }
            )

            views.setTextViewText(
                R.id.quick_total_subtitle,
                if (isAr) {
                    "إجمالي الكلمات المحفوظة: $total"
                } else {
                    "Total saved words: $total"
                }
            )

            views.setTextViewText(
                R.id.btn_launch_add_word,
                if (isAr) "＋ إضافة كلمة" else "＋ Add Word"
            )
            views.setTextViewText(
                R.id.btn_launch_review,
                if (isAr) "▶ ابدأ المراجعة" else "▶ Start Review"
            )

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

            val addIntent = NativeBridgeStore.createAppLaunchIntent(
                context,
                NativeBridgeStore.ACTION_QUICK_ADD
            )
            views.setOnClickPendingIntent(
                R.id.btn_launch_add_word,
                PendingIntent.getActivity(context, 201, addIntent, flags)
            )

            val reviewIntent = NativeBridgeStore.createAppLaunchIntent(
                context,
                NativeBridgeStore.ACTION_START_REVIEW
            )
            views.setOnClickPendingIntent(
                R.id.btn_launch_review,
                PendingIntent.getActivity(context, 202, reviewIntent, flags)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
