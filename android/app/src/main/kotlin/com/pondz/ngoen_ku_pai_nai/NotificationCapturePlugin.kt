package com.pondz.ngoen_ku_pai_nai

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ContentUris
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import android.provider.Settings
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object NotificationCapturePlugin {
    private const val CHANNEL = "ngoen_ku_pai_nai/notification_capture"
    private const val APP_CHANNEL = "finance_candidate_review"
    private const val CANDIDATE_EXTRA = "candidate_id"
    private var launchIntent: Intent? = null
    private const val PICK_SLIP_IMAGE = 1903
    private var pendingSlipPickerResult: MethodChannel.Result? = null

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
                "slipImagePermissionState" -> result.success(imagePermissionState(context))
                "requestSlipImagePermission" -> {
                    when {
                        Build.VERSION.SDK_INT >= 34 -> context.requestPermissions(
                            arrayOf(
                                "android.permission.READ_MEDIA_IMAGES",
                                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
                            ),
                            1902,
                        )
                        Build.VERSION.SDK_INT >= 33 -> context.requestPermissions(
                            arrayOf("android.permission.READ_MEDIA_IMAGES"),
                            1902,
                        )
                        else -> context.requestPermissions(
                            arrayOf("android.permission.READ_EXTERNAL_STORAGE"),
                            1902,
                        )
                    }
                    result.success("requested")
                }
                "scanNewSlipImages" -> {
                    val afterMillis = call.argument<Number>("afterMillis")?.toLong() ?: 0L
                    result.success(scanNewSlipImages(context, afterMillis))
                }
                "pickSlipImages" -> {
                    if (pendingSlipPickerResult != null) {
                        result.error("picker_in_progress", "A slip picker is already open", null)
                    } else {
                        pendingSlipPickerResult = result
                        context.startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "image/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
                            },
                            PICK_SLIP_IMAGE,
                        )
                    }
                }
                "isPackageInstalled" -> {
                    val packageName = call.argument<String>("packageName")
                    Thread {
                        val installed = try {
                            if (packageName.isNullOrBlank()) false
                            else {
                                @Suppress("DEPRECATION")
                                context.packageManager.getPackageInfo(packageName, 0)
                                true
                            }
                        } catch (_: Exception) { false }
                        context.runOnUiThread { result.success(installed) }
                    }.start()
                }
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

    fun onActivityResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_SLIP_IMAGE) return false
        val result = pendingSlipPickerResult ?: return true
        pendingSlipPickerResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return true
        }
        val uris = buildList {
            data.clipData?.let { clip ->
                for (index in 0 until clip.itemCount) add(clip.getItemAt(index).uri)
            }
            data.data?.let { uri -> if (!contains(uri)) add(uri) }
        }
        val items = uris.mapNotNull { uri -> slipMetadata(context, uri) }
        result.success(items)
        return true
    }

    private fun slipMetadata(context: Context, uri: android.net.Uri): Map<String, Any?>? {
        val mimeType = context.contentResolver.getType(uri)?.lowercase()
        if (mimeType !in setOf("image/jpeg", "image/png", "image/webp")) {
            return null
        }
        val sizeBytes = context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else null }
        val now = System.currentTimeMillis()
        return mapOf(
            "mediaStoreId" to uri.toString(),
            "contentUri" to uri.toString(),
            "mimeType" to mimeType,
            "dateAddedMillis" to now,
            "dateTakenMillis" to 0L,
            "sizeBytes" to sizeBytes,
        )
    }

    private fun imagePermissionState(context: Context): String {
        val granted = android.content.pm.PackageManager.PERMISSION_GRANTED
        if (Build.VERSION.SDK_INT >= 34 &&
            context.checkSelfPermission("android.permission.READ_MEDIA_IMAGES") == granted
        ) return "granted"
        if (Build.VERSION.SDK_INT >= 34 &&
            context.checkSelfPermission("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") == granted
        ) return "limited"
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission("android.permission.READ_MEDIA_IMAGES") == granted
        ) return "granted"
        if (Build.VERSION.SDK_INT < 33 &&
            context.checkSelfPermission("android.permission.READ_EXTERNAL_STORAGE") == granted
        ) return "granted"
        return "denied"
    }

    private fun scanNewSlipImages(context: Context, afterMillis: Long): List<Map<String, Any?>> {
        if (imagePermissionState(context) == "denied") return emptyList()
        val result = mutableListOf<Map<String, Any?>>()
        val afterSeconds = afterMillis / 1000L
        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.SIZE,
        )
        val selection = "${MediaStore.Images.Media.DATE_ADDED} > ?"
        context.contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            arrayOf(afterSeconds.toString()),
            "${MediaStore.Images.Media.DATE_ADDED} ASC",
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            val added = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
            val taken = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
            val mime = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
            val width = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
            val height = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
            val size = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
            while (cursor.moveToNext()) {
                val mimeType = cursor.getString(mime) ?: continue
                if (mimeType.lowercase() !in setOf("image/jpeg", "image/png", "image/webp")) continue
                val mediaId = cursor.getLong(id).toString()
                result += mapOf(
                    "mediaStoreId" to mediaId,
                    "contentUri" to ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cursor.getLong(id)).toString(),
                    "mimeType" to mimeType,
                    "dateAddedMillis" to cursor.getLong(added) * 1000L,
                    "dateTakenMillis" to cursor.getLong(taken),
                    "width" to cursor.getInt(width),
                    "height" to cursor.getInt(height),
                    "sizeBytes" to cursor.getLong(size),
                )
            }
        }
        return result
    }

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
