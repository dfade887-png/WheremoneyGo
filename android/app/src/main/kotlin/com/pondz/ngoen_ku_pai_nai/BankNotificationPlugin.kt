package com.pondz.ngoen_ku_pai_nai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object BankNotificationPlugin {
    private const val CHANNEL = "ngoen_ku_pai_nai/bank_notifications"

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationAccess" -> {
                    context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "hasNotificationAccess" -> {
                    val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
                    val component = ComponentName(context, BankNotificationListenerService::class.java).flattenToString()
                    result.success(enabled.contains(component))
                }
                "supportedInstitutions" -> result.success(emptyList<String>())
                else -> result.notImplemented()
            }
        }
    }
}
