package com.pondz.ngoen_ku_pai_nai

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class GenericNotificationListenerService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        // Never log notification content. Unknown packages are discarded here.
        NativeNotificationQueue.enqueueIfAllowed(this, CapturedNotificationMapper.map(sbn))
    }
}
