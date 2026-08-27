package com.pondz.ngoen_ku_pai_nai

import android.app.Notification
import android.os.Bundle
import android.service.notification.StatusBarNotification
import java.security.MessageDigest

data class NativeCapturedNotification(
    val packageName: String,
    val notificationKeyHash: String,
    val capturedAtMillis: Long,
    val title: String?,
    val body: String?,
    val senderOrChat: String?,
)

object CapturedNotificationMapper {
    fun map(sbn: StatusBarNotification): NativeCapturedNotification {
        val extras = sbn.notification.extras ?: Bundle.EMPTY
        val messages = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        val lastMessage = messages?.lastOrNull() as? Bundle
        val messageText = lastMessage?.getCharSequence("text")?.toString().clean()
        val sender = lastMessage?.getCharSequence("sender")?.toString().clean()
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().clean()
        val body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().clean()
            ?: messageText
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().clean()
        val conversation = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString().clean()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().clean()
        return NativeCapturedNotification(
            packageName = sbn.packageName,
            notificationKeyHash = sha256(sbn.key),
            capturedAtMillis = sbn.postTime,
            title = title,
            body = body,
            senderOrChat = conversation ?: sender ?: subText,
        )
    }

    private fun String?.clean(): String? = this?.trim()?.takeIf { it.isNotEmpty() }
    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}
