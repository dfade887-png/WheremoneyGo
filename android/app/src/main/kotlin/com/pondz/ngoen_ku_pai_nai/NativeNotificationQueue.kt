package com.pondz.ngoen_ku_pai_nai

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object NativeNotificationQueue {
    private const val PREFS = "generic_notification_capture"
    private const val CONFIG = "capture_config"
    private const val QUEUE = "pending_queue"
    private const val MAX_QUEUE_SIZE = 200

    @Synchronized
    fun configure(context: Context, profileId: String, sources: List<Map<String, String>>) {
        val root = JSONObject().put("profileId", profileId)
        val array = JSONArray()
        sources.forEach { source ->
            array.put(JSONObject().put("sourceId", source["sourceId"]).put("packageName", source["packageName"]))
        }
        root.put("sources", array)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(CONFIG, root.toString()).apply()
    }

    @Synchronized
    fun enqueueIfAllowed(context: Context, captured: NativeCapturedNotification): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val config = prefs.getString(CONFIG, null)?.let(::JSONObject) ?: return false
        val sources = config.getJSONArray("sources")
        var sourceId: String? = null
        for (index in 0 until sources.length()) {
            val source = sources.getJSONObject(index)
            if (source.getString("packageName") == captured.packageName) {
                sourceId = source.getString("sourceId")
                break
            }
        }
        if (sourceId == null) return false
        val queue = JSONArray(prefs.getString(QUEUE, "[]"))
        val item = JSONObject()
            .put("profileId", config.getString("profileId"))
            .put("sourceId", sourceId)
            .put("packageName", captured.packageName)
            .put("notificationKeyHash", captured.notificationKeyHash)
            .put("capturedAtMillis", captured.capturedAtMillis)
            .putNullable("title", captured.title)
            .putNullable("body", captured.body)
            .putNullable("senderOrChat", captured.senderOrChat)
        // Stable notification identity: replace an older queued revision.
        val revised = JSONArray()
        for (index in 0 until queue.length()) {
            val old = queue.getJSONObject(index)
            if (old.getString("profileId") != config.getString("profileId") ||
                old.getString("packageName") != captured.packageName ||
                old.getString("notificationKeyHash") != captured.notificationKeyHash
            ) revised.put(old)
        }
        revised.put(item)
        while (revised.length() > MAX_QUEUE_SIZE) revised.remove(0)
        prefs.edit().putString(QUEUE, revised.toString()).apply()
        return true
    }

    @Synchronized
    fun read(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(QUEUE, "[]"))
        val result = mutableListOf<Map<String, Any?>>()
        for (index in 0 until queue.length()) {
            val item = queue.getJSONObject(index)
            result += mapOf(
                "profileId" to item.getString("profileId"),
                "sourceId" to item.getString("sourceId"),
                "packageName" to item.getString("packageName"),
                "notificationKeyHash" to item.getString("notificationKeyHash"),
                "capturedAtMillis" to item.getLong("capturedAtMillis"),
                "title" to item.optString("title").ifEmpty { null },
                "body" to item.optString("body").ifEmpty { null },
                "senderOrChat" to item.optString("senderOrChat").ifEmpty { null },
            )
        }
        return result
    }

    @Synchronized
    fun acknowledge(context: Context, identities: List<String>) {
        if (identities.isEmpty()) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(QUEUE, "[]"))
        val retained = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.getJSONObject(index)
            val identity = listOf(
                item.getString("profileId"),
                item.getString("packageName"),
                item.getString("notificationKeyHash"),
            ).joinToString("|")
            if (!identities.contains(identity)) retained.put(item)
        }
        prefs.edit().putString(QUEUE, retained.toString()).commit()
    }

    private fun JSONObject.putNullable(key: String, value: String?): JSONObject =
        if (value == null) this else put(key, value)
}
