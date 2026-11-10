package com.example.ekiiyou

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class FloatingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                NativeBridgeStore.refreshAllWidgets(context)
                if (NativeBridgeStore.isFloatingEnabled(context)) {
                    FloatingWordService.syncServiceState(context, showImmediately = false)
                }
            }
        }
    }
}
