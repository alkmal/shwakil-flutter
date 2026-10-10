package com.alkmal.shwakil

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

class ExternalAppNotificationListenerService : NotificationListenerService() {
    companion object {
        const val PREFS = "shwakil_external_app_notifications"
        const val SELECTED_PACKAGES = "selected_packages"
        const val SELECTION_INITIALIZED = "selection_initialized"
        const val PENDING_EVENTS = "pending_events"
        const val ACTIVE_WORKSPACE_ID = "active_workspace_id"
        private const val MAX_PENDING_EVENTS = 200
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val workspaceId = prefs.getString(ACTIVE_WORKSPACE_ID, null)?.trim().orEmpty()
        if (workspaceId.isEmpty()) return
        if (sbn.packageName == packageName || sbn.packageName !in (prefs.getStringSet(SELECTED_PACKAGES, emptySet()) ?: emptySet())) return

        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val message = sequenceOf(
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString()
        ).mapNotNull { it?.trim()?.takeIf(String::isNotEmpty) }.firstOrNull().orEmpty()
        if (title.isEmpty() && message.isEmpty()) return

        val appName = try {
            packageManager.getApplicationInfo(sbn.packageName, 0).loadLabel(packageManager).toString()
        } catch (_: Exception) {
            sbn.packageName
        }
        val notificationKey = sbn.key
        val eventId = sha256("${sbn.packageName}|$notificationKey|${sbn.postTime}")
        val event = JSONObject()
            .put("eventId", eventId)
            .put("workspaceId", workspaceId)
            .put("notificationKey", notificationKey)
            .put("packageName", sbn.packageName)
            .put("appName", appName)
            .put("title", title.take(500))
            .put("message", message.take(4000))
            .put("postedAt", sbn.postTime)

        synchronized(this) {
            val current = JSONArray(prefs.getString(PENDING_EVENTS, "[]") ?: "[]")
            val updated = JSONArray()
            for (index in 0 until current.length()) {
                val previous = current.getJSONObject(index)
                if (previous.optString("eventId") != eventId) updated.put(previous)
            }
            updated.put(event)
            val bounded = JSONArray()
            val start = (updated.length() - MAX_PENDING_EVENTS).coerceAtLeast(0)
            for (index in start until updated.length()) bounded.put(updated.getJSONObject(index))
            prefs.edit().putString(PENDING_EVENTS, bounded.toString()).apply()
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}
