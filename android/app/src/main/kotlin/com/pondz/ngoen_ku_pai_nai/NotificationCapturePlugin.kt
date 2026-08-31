package com.pondz.ngoen_ku_pai_nai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object NotificationCapturePlugin {
    private const val CHANNEL = "ngoen_ku_pai_nai/notification_capture"
    private const val APP_CHANNEL = "finance_candidate_review"
    private const val CANDIDATE_EXTRA = "candidate_id"
    private var launchIntent: Intent? = null

    fun register(context: Activity, engine: FlutterEngine) {
        launchIntent = context.intent
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
                "hasPostNotificationsPermission" -> result.success(
                    Build.VERSION.SDK_INT < 33 || context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") == android.content.pm.PackageManager.PERMISSION_GRANTED
                )
                "requestPostNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33) context.requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 1901)
                    result.success(null)
                }
                "openAppNotificationSettings" -> {
                    context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
                    result.success(null)
                }
                "consumeLaunchCandidate" -> {
                    val id = launchIntent?.getStringExtra(CANDIDATE_EXTRA)
                    launchIntent?.removeExtra(CANDIDATE_EXTRA)
                    result.success(id)
                }
                "notifyCandidate" -> {
                    notifyCandidate(context, call.argument<String>("candidateId") ?: "", call.argument<String>("type") ?: "expense", call.argument<Int>("amountSatang") ?: 0, call.argument<String>("accountName"))
                    result.success(null)
                }
                "cancelCandidate" -> {
                    val id = call.argument<String>("candidateId")
                    if (id != null) context.getSystemService(NotificationManager::class.java)?.cancel(notificationId(id))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun updateIntent(intent: Intent) { launchIntent = intent }

    private fun notifyCandidate(context: Context, candidateId: String, type: String, amountSatang: Int, accountName: String?) {
        if (candidateId.isEmpty()) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(APP_CHANNEL, "รายการรอตรวจ", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "แจ้งเตือนเมื่อพบรายการทางการเงินที่รอการตรวจสอบ"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
        }
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission("android.permission.POST_NOTIFICATIONS") != android.content.pm.PackageManager.PERMISSION_GRANTED) return
        val amount = String.format("฿%.2f", amountSatang / 100.0)
        val title = when (type) { "income" -> "พบรายการใหม่"; "refund" -> "พบเงินคืน"; else -> "พบรายการใหม่" }
        val body = when (type) { "income" -> "เงินเข้า $amount${accountName?.let { " ที่$it" } ?: ""}"; "refund" -> "เงินคืน $amount"; else -> "เงินออก $amount${accountName?.let { " จาก$it" } ?: ""}" }
        val intent = Intent(context, MainActivity::class.java).putExtra(CANDIDATE_EXTRA, candidateId).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(context, notificationId(candidateId), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.notify(notificationId(candidateId), Notification.Builder(context, APP_CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(title).setContentText(body).setSubText("แตะเพื่อตรวจสอบ").setContentIntent(pending).setAutoCancel(true).setStyle(Notification.BigTextStyle().bigText("$body\nแตะเพื่อเปิดรายการรอตรวจ")).build())
    }

    private fun notificationId(candidateId: String): Int = candidateId.hashCode() and 0x7fffffff
}
