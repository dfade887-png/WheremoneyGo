package com.pondz.ngoen_ku_pai_nai

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.security.MessageDigest

/**
 * Experimental, opt-in listener. No real bank is enabled until a verified,
 * anonymized fixture supplies its package and format.
 */
class BankNotificationListenerService : NotificationListenerService() {
    private val allowedPackages: Set<String> = emptySet()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!allowedPackages.contains(sbn.packageName)) return
        // Adapter registration is intentionally empty. Never persist or log raw text.
        val keyHash = sha256(sbn.key)
        getSharedPreferences("bank_event_queue", MODE_PRIVATE)
            .edit()
            .putString("last_unsupported_key_hash", keyHash)
            .apply()
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
