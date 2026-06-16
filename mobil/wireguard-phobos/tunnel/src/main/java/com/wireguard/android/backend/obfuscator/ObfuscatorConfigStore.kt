/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

class ObfuscatorConfigStore(private val context: Context) {

    private fun fileFor(name: String): File = File(context.filesDir, "$name$SUFFIX")

    fun load(tunnelName: String): Map<String, ObfuscatorPeerSettings> {
        val file = fileFor(tunnelName)
        if (!file.isFile) return emptyMap()
        return try {
            val root = JSONObject(file.readText())
            val result = HashMap<String, ObfuscatorPeerSettings>()
            for (peerKey in root.keys()) {
                val o = root.getJSONObject(peerKey)
                result[peerKey] = ObfuscatorPeerSettings(
                    enabled = o.optBoolean("enabled", false),
                    serverEndpoint = o.optString("server", ""),
                    key = o.optString("key", ""),
                    maskingType = Masking.normalize(o.optString("masking", Masking.NONE)),
                    maxDummy = o.optInt("maxDummy", ObfuscatorPeerSettings.DEFAULT_MAX_DUMMY),
                    obfuscateBytes = o.optInt("obfuscateBytes", 0),
                    mediaPayloadType = o.optInt("mediaPt", 0),
                    mediaSsrc = o.optLong("mediaSsrc", 0),
                    mediaClock = o.optInt("mediaClock", 0)
                )
            }
            result
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read obfuscator settings for $tunnelName", e)
            emptyMap()
        }
    }

    fun loadForPeer(tunnelName: String, peerPublicKey: String): ObfuscatorPeerSettings =
        load(tunnelName)[peerPublicKey] ?: ObfuscatorPeerSettings()

    fun save(tunnelName: String, settings: Map<String, ObfuscatorPeerSettings>) {
        val file = fileFor(tunnelName)
        val meaningful = settings.filterValues { it.isMeaningful }
        if (meaningful.isEmpty()) {
            file.delete()
            return
        }
        val root = JSONObject()
        for ((peerKey, s) in meaningful) {
            val o = JSONObject()
            o.put("enabled", s.enabled)
            o.put("server", s.serverEndpoint)
            o.put("key", s.key)
            o.put("masking", s.maskingType)
            o.put("maxDummy", s.maxDummy)
            o.put("obfuscateBytes", s.obfuscateBytes)
            o.put("mediaPt", s.mediaPayloadType)
            o.put("mediaSsrc", s.mediaSsrc)
            o.put("mediaClock", s.mediaClock)
            root.put(peerKey, o)
        }
        file.writeText(root.toString())
    }

    fun delete(tunnelName: String) {
        fileFor(tunnelName).delete()
    }

    fun rename(oldName: String, newName: String) {
        val src = fileFor(oldName)
        if (!src.isFile) return
        val dst = fileFor(newName)
        if (!src.renameTo(dst)) {
            dst.writeText(src.readText())
            src.delete()
        }
    }

    companion object {
        private const val TAG = "WireGuard/Obfuscator"
        private const val SUFFIX = ".obfuscator"
    }
}
