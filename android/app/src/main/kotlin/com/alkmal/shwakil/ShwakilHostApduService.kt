package com.alkmal.shwakil

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import java.nio.charset.StandardCharsets

class ShwakilHostApduService : HostApduService() {
    companion object {
        private const val PREFS = "shwakil_hce_payment"
        private const val KEY_PAYLOAD = "payload"
        private const val KEY_EXPIRES_AT = "expires_at"
        private const val SW_SUCCESS = "9000"
        private const val SW_NOT_FOUND = "6A82"
        private const val SW_WRONG_DATA = "6A80"
        private const val SW_INS_NOT_SUPPORTED = "6D00"
        private const val SELECT_PREFIX = "00A40400"
        private const val READ_PREFIX = "80CA"
        private const val AID = "A0000008585348574B01"
        private const val MAX_CHUNK_SIZE = 220
    }

    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        val command = commandApdu ?: return hexToBytes(SW_WRONG_DATA)
        val hex = bytesToHex(command)

        if (hex.startsWith(SELECT_PREFIX)) {
            return if (currentPayloadBytes() == null) {
                hexToBytes(SW_NOT_FOUND)
            } else {
                hexToBytes(SW_SUCCESS)
            }
        }

        if (!hex.startsWith(READ_PREFIX) || command.size < 5) {
            return hexToBytes(SW_INS_NOT_SUPPORTED)
        }

        val payload = currentPayloadBytes() ?: return hexToBytes(SW_NOT_FOUND)
        val offset = ((command[2].toInt() and 0xff) shl 8) or
            (command[3].toInt() and 0xff)
        if (offset > payload.size) {
            return hexToBytes(SW_WRONG_DATA)
        }

        val requestedLength = command[4].toInt() and 0xff
        val chunkLength = minOf(
            if (requestedLength == 0) MAX_CHUNK_SIZE else requestedLength,
            MAX_CHUNK_SIZE,
            payload.size - offset
        )
        val chunk = payload.copyOfRange(offset, offset + chunkLength)
        return chunk + hexToBytes(SW_SUCCESS)
    }

    override fun onDeactivated(reason: Int) = Unit

    private fun currentPayloadBytes(): ByteArray? {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val expiresAt = prefs.getLong(KEY_EXPIRES_AT, 0L)
        val payload = prefs.getString(KEY_PAYLOAD, null)?.trim()
        if (payload.isNullOrEmpty() || expiresAt <= System.currentTimeMillis()) {
            prefs.edit().remove(KEY_PAYLOAD).remove(KEY_EXPIRES_AT).apply()
            return null
        }
        return payload.toByteArray(StandardCharsets.UTF_8)
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02X".format(it) }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.replace("\\s".toRegex(), "")
        return ByteArray(clean.length / 2) { index ->
            clean.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }
}
