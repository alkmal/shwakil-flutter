package com.alkmal.shwakil

import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.provider.Settings
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val REFERRAL_CHANNEL = "com.alkmal.shwakil/referrals"
        private const val HCE_CHANNEL = "com.alkmal.shwakil/hce"
        private const val HCE_PREFS = "shwakil_hce_payment"
        private const val HCE_PAYLOAD_KEY = "payload"
        private const val HCE_EXPIRES_AT_KEY = "expires_at"
        private const val EXTERNAL_NOTIFICATIONS_CHANNEL = "com.alkmal.shwakil/external_notifications"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REFERRAL_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialReferralPayload" -> {
                    getInitialReferralPayload(result)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HCE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setPaymentPayload" -> {
                    val payload = call.argument<String>("payload")?.trim().orEmpty()
                    val expiresAt = call.argument<Number>("expiresAtMillis")?.toLong() ?: 0L
                    if (payload.isEmpty() || expiresAt <= System.currentTimeMillis()) {
                        result.error("invalid_payload", "Invalid HCE payment payload.", null)
                        return@setMethodCallHandler
                    }
                    getSharedPreferences(HCE_PREFS, MODE_PRIVATE)
                        .edit()
                        .putString(HCE_PAYLOAD_KEY, payload)
                        .putLong(HCE_EXPIRES_AT_KEY, expiresAt)
                        .apply()
                    result.success(true)
                }

                "clearPaymentPayload" -> {
                    getSharedPreferences(HCE_PREFS, MODE_PRIVATE)
                        .edit()
                        .remove(HCE_PAYLOAD_KEY)
                        .remove(HCE_EXPIRES_AT_KEY)
                        .apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_NOTIFICATIONS_CHANNEL
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(ExternalAppNotificationListenerService.PREFS, MODE_PRIVATE)
            when (call.method) {
                "hasAccess" -> {
                    val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                        ?.split(':')
                        ?.any { ComponentName.unflattenFromString(it)?.packageName == packageName } == true
                    result.success(enabled)
                }
                "openAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                }
                "getApps" -> {
                    val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    val apps = packageManager.queryIntentActivities(launcher, 0)
                        .mapNotNull { info ->
                            val appInfo = info.activityInfo?.applicationInfo ?: return@mapNotNull null
                            if (appInfo.packageName == packageName) return@mapNotNull null
                            mapOf(
                                "packageName" to appInfo.packageName,
                                "appName" to appInfo.loadLabel(packageManager).toString()
                            )
                        }
                        .distinctBy { it["packageName"] }
                        .sortedBy { it["appName"].toString().lowercase() }
                    result.success(apps)
                }
                "getSelectedPackages" -> {
                    var packages = prefs.getStringSet(ExternalAppNotificationListenerService.SELECTED_PACKAGES, emptySet()) ?: emptySet()
                    if (!prefs.getBoolean(ExternalAppNotificationListenerService.SELECTION_INITIALIZED, false)) {
                        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                        val recommended = packageManager.queryIntentActivities(launcher, 0)
                            .mapNotNull { info ->
                                val appInfo = info.activityInfo?.applicationInfo ?: return@mapNotNull null
                                val appName = appInfo.loadLabel(packageManager).toString()
                                val label = (appName + " " + appInfo.packageName).lowercase()
                                val looksLikeBank = listOf("bank", "بنك", "مصرف").any(label::contains)
                                val looksLikeJawwalPay = listOf("jawwal pay", "jawwalpay", "جوال باي").any(label::contains)
                                val looksLikePalPay = listOf("palpay", "pal pay", "بال باي").any(label::contains)
                                if (appInfo.packageName != packageName && (looksLikeBank || looksLikeJawwalPay || looksLikePalPay)) appInfo.packageName else null
                            }.toSet()
                        packages = recommended
                        prefs.edit()
                            .putStringSet(ExternalAppNotificationListenerService.SELECTED_PACKAGES, packages)
                            .putBoolean(ExternalAppNotificationListenerService.SELECTION_INITIALIZED, packages.isNotEmpty())
                            .apply()
                    }
                    result.success(packages.toList())
                }
                "setSelectedPackages" -> {
                    val packages = call.argument<List<String>>("packages")?.toSet() ?: emptySet()
                    prefs.edit()
                        .putStringSet(ExternalAppNotificationListenerService.SELECTED_PACKAGES, packages)
                        .putBoolean(ExternalAppNotificationListenerService.SELECTION_INITIALIZED, true)
                        .apply()
                    result.success(true)
                }
                "setActiveWorkspaceId" -> {
                    val workspaceId = call.argument<String>("workspaceId")?.trim().orEmpty()
                    prefs.edit().putString(ExternalAppNotificationListenerService.ACTIVE_WORKSPACE_ID, workspaceId.takeIf { it.isNotEmpty() }).apply()
                    result.success(true)
                }
                "getPendingEvents" -> {
                    val events = prefs.getString(ExternalAppNotificationListenerService.PENDING_EVENTS, "[]") ?: "[]"
                    result.success(org.json.JSONArray(events).let { json ->
                        (0 until json.length()).map { json.getJSONObject(it).let { item ->
                            mapOf(
                                "eventId" to item.optString("eventId"),
                                "workspaceId" to item.optString("workspaceId"),
                                "notificationKey" to item.optString("notificationKey"),
                                "packageName" to item.optString("packageName"),
                                "appName" to item.optString("appName"),
                                "title" to item.optString("title"),
                                "message" to item.optString("message"),
                                "postedAt" to item.optLong("postedAt")
                            )
                        } }
                    })
                }
                "acknowledgeEvents" -> {
                    val ids = call.argument<List<String>>("eventIds")?.toSet() ?: emptySet()
                    val old = org.json.JSONArray(prefs.getString(ExternalAppNotificationListenerService.PENDING_EVENTS, "[]") ?: "[]")
                    val kept = org.json.JSONArray()
                    for (index in 0 until old.length()) {
                        val event = old.getJSONObject(index)
                        if (event.optString("eventId") !in ids) kept.put(event)
                    }
                    prefs.edit().putString(ExternalAppNotificationListenerService.PENDING_EVENTS, kept.toString()).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun getInitialReferralPayload(result: MethodChannel.Result) {
        val intentCode = parseReferralFromIntent(intent)

        fetchInstallReferrerCode { installReferrerCode ->
            val payload = hashMapOf<String, String?>(
                "intentCode" to intentCode,
                "installReferrerCode" to installReferrerCode
            )
            runOnUiThread {
                result.success(payload)
            }
        }
    }

    private fun fetchInstallReferrerCode(callback: (String?) -> Unit) {
        val client = InstallReferrerClient.newBuilder(this).build()
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                when (responseCode) {
                    InstallReferrerClient.InstallReferrerResponse.OK -> {
                        try {
                            val response = client.installReferrer
                            callback(parseReferralFromRawReferrer(response.installReferrer))
                        } catch (_: Exception) {
                            callback(null)
                        } finally {
                            client.endConnection()
                        }
                    }

                    else -> {
                        client.endConnection()
                        callback(null)
                    }
                }
            }

            override fun onInstallReferrerServiceDisconnected() {
                callback(null)
            }
        })
    }

    private fun parseReferralFromIntent(intent: Intent?): String? {
        val data = intent?.data ?: return null
        return parseReferralFromUri(data)
    }

    private fun parseReferralFromRawReferrer(rawReferrer: String?): String? {
        val raw = rawReferrer?.trim()
        if (raw.isNullOrEmpty()) {
            return null
        }

        val uri = Uri.parse("https://play.google.com/store/apps/details?$raw")
        return parseReferralFromUri(uri)
    }

    private fun parseReferralFromUri(uri: Uri): String? {
        val directCode = sanitizeReferralCode(
            uri.getQueryParameter("ref")
                ?: uri.getQueryParameter("referral")
                ?: uri.getQueryParameter("code")
                ?: uri.getQueryParameter("referralPhone")
        )
        if (directCode != null) {
            return directCode
        }

        if (uri.scheme == "shwakil" && uri.host == "invite") {
            return sanitizeReferralCode(
                uri.getQueryParameter("ref")
                    ?: uri.getQueryParameter("referral")
                    ?: uri.getQueryParameter("code")
            )
        }

        return null
    }

    private fun sanitizeReferralCode(value: String?): String? {
        val normalized = value?.trim() ?: return null
        if (normalized.isEmpty() || normalized.length > 64) {
            return null
        }

        return if (Regex("[\\s/?#&]").containsMatchIn(normalized)) {
            null
        } else {
            normalized
        }
    }
}
