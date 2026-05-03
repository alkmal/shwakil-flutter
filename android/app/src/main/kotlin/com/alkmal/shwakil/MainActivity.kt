package com.alkmal.shwakil

import android.content.Intent
import android.net.Uri
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
