package com.pondz.ngoen_ku_pai_nai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object NotificationCapturePlugin {
    private const val CHANNEL = "ngoen_ku_pai_nai/notification_capture"

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationAccess" -> {
                    context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "hasNotificationAccess" -> {
                    val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: ""
                    val component = ComponentName(context, GenericNotificationListenerService::class.java).flattenToString()
                    result.success(enabled.split(":").contains(component))
                }
                "configureCapture" -> {
                    val profileId = call.argument<String>("profileId")!!
                    val sourceRows = call.argument<List<Map<String, String>>>("sources") ?: emptyList()
                    NativeNotificationQueue.configure(context, profileId, sourceRows)
                    result.success(null)
                }
                "readCapturedNotifications" -> result.success(NativeNotificationQueue.read(context))
                "acknowledgeCapturedNotifications" -> {
                    NativeNotificationQueue.acknowledge(
                        context,
                        call.argument<List<String>>("identities") ?: emptyList(),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
