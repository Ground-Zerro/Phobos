/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import com.wireguard.config.Config
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import com.wireguard.crypto.KeyPair

/**
 * Handles the Phobos `[instance]` section that may accompany a WireGuard config
 * in a QR code or a `.conf` file. The `[instance]` section is not part of the
 * WireGuard format, so it is split off before [Config] parsing and turned into
 * per-peer [ObfuscatorPeerSettings].
 */
object ObfuscatorConfigParser {
    private const val INSTANCE = "instance"
    private const val SOCKS5 = "socks5"
    private val SOCKS5_MODE_RE = Regex("(?im)^\\s*mode\\s*=\\s*socks5\\s*$")

    private const val SYNTHETIC_ADDRESSES = "10.42.0.2/32, fdcc:ad94:bacf:61a3::2/128"
    private const val SYNTHETIC_DNS = "1.1.1.1"
    private const val SYNTHETIC_MTU = 1500

    /** True if [raw] is a SOCKS5-mode config (an `[instance]` with `mode = socks5`). */
    fun hasSocks5Mode(raw: String): Boolean = SOCKS5_MODE_RE.containsMatchIn(raw)

    /**
     * Builds the synthetic WireGuard [Config] shell used to represent a SOCKS5
     * tunnel in the app's tunnel model. It carries only a local tun address, DNS
     * and MTU (plus, later, the user's per-app include/exclude); it never runs
     * wireguard-go — [com.wireguard.android.backend.GoBackend] routes SOCKS5
     * tunnels through tun2socks instead. The keypair is a throwaway required by
     * the WireGuard config format and is never used on the wire.
     */
    fun syntheticSocks5Config(): Config {
        val iface = Interface.Builder()
            .setKeyPair(KeyPair())
            .parseAddresses(SYNTHETIC_ADDRESSES)
            .parseDnsServers(SYNTHETIC_DNS)
            .setMtu(SYNTHETIC_MTU)
            .build()
        return Config.Builder().setInterface(iface).build()
    }

    /**
     * Parses a SOCKS5-mode config into [Socks5Settings] from its `[instance]`
     * (obfuscator) and `[socks5]` (credentials) sections. Returns null if [raw]
     * is not a valid SOCKS5 config.
     */
    fun parseSocks5(raw: String): Socks5Settings? {
        val sections = parseNamedSections(raw)
        val instance = sections[INSTANCE] ?: return null
        if (!instance["mode"].equals(SOCKS5, ignoreCase = true)) return null
        val target = instance["target"].orEmpty().trim()
        val key = instance["key"].orEmpty().trim()
        if (target.isEmpty() || key.isEmpty()) return null
        val socks5 = sections[SOCKS5] ?: emptyMap()
        return Socks5Settings(
            target = target,
            key = key,
            maskingType = Masking.normalizeSocks5(instance["masking"]),
            mediaSsrc = parseUnsigned32(instance["media-ssrc"]),
            login = socks5["login"].orEmpty().trim(),
            password = socks5["password"].orEmpty().trim(),
            listenPort = instance["source-lport"]?.toIntOrNull()
                ?: Socks5Settings.DEFAULT_LISTEN_PORT
        )
    }

    /** Returns [raw] with every `[instance]` section removed (a plain WireGuard config). */
    fun stripInstanceSections(raw: String): String {
        val sb = StringBuilder()
        var inInstance = false
        for (line in raw.lineSequence()) {
            val trimmed = line.trim()
            if (trimmed.startsWith("["))
                inInstance = isInstanceHeader(trimmed)
            if (!inInstance)
                sb.append(line).append('\n')
        }
        return sb.toString()
    }

    /**
     * Parses `[instance]` sections from [raw] and matches each to a peer of [config].
     * The result maps a peer's public key to its obfuscator settings (enabled).
     */
    fun peerSettingsFrom(raw: String, config: Config): Map<String, ObfuscatorPeerSettings> {
        val instances = parseInstances(raw)
        if (instances.isEmpty()) return emptyMap()
        val peers = config.peers
        if (peers.isEmpty()) return emptyMap()
        val result = HashMap<String, ObfuscatorPeerSettings>()
        for (instance in instances) {
            val peer = matchPeer(peers, instance) ?: continue
            result[peer.publicKey.toBase64()] = instance.toSettings()
        }
        return result
    }

    /**
     * Appends an `[instance]` section for every obfuscated peer to a wg-quick string,
     * so an exported/shared config carries the obfuscator settings.
     */
    fun appendInstanceSections(
        wgQuick: String,
        config: Config,
        settings: Map<String, ObfuscatorPeerSettings>
    ): String {
        if (settings.isEmpty()) return wgQuick
        val sb = StringBuilder(wgQuick)
        for (peer in config.peers) {
            val s = settings[peer.publicKey.toBase64()] ?: continue
            if (!s.enabled || s.serverEndpoint.isEmpty()) continue
            if (sb.isNotEmpty() && sb.last() != '\n') sb.append('\n')
            sb.append("\n[instance]\n")
            sb.append("source-if = 127.0.0.1\n")
            peer.endpoint.ifPresent { sb.append("source-lport = ").append(it.port).append('\n') }
            sb.append("target = ").append(s.serverEndpoint).append('\n')
            sb.append("key = ").append(s.key).append('\n')
            sb.append("masking = ").append(maskingLabel(s.maskingType)).append('\n')
            if (s.maskingType == Masking.MEDIA) {
                sb.append("obfuscate-bytes = ").append(s.obfuscateBytes).append('\n')
                if (s.mediaPayloadType != 0) sb.append("media-pt = ").append(s.mediaPayloadType).append('\n')
                if (s.mediaSsrc != 0L) sb.append("media-ssrc = ").append(s.mediaSsrc).append('\n')
                if (s.mediaClock != 0) sb.append("media-clock = ").append(s.mediaClock).append('\n')
            } else {
                sb.append("max-dummy = ").append(s.maxDummy).append('\n')
            }
        }
        return sb.toString()
    }

    private fun maskingLabel(maskingType: String): String = when (maskingType) {
        Masking.STUN -> "STUN"
        Masking.MEDIA -> "MEDIA"
        else -> "none"
    }

    private fun isInstanceHeader(headerLine: String): Boolean =
        sectionName(headerLine).equals(INSTANCE, ignoreCase = true)

    private fun sectionName(headerLine: String): String {
        val inner = headerLine.drop(1).substringBefore(']').trim()
        return inner.substringBefore(' ').substringBefore('"').trim()
    }

    private fun parseNamedSections(raw: String): Map<String, Map<String, String>> {
        val result = HashMap<String, MutableMap<String, String>>()
        var current: MutableMap<String, String>? = null
        for (rawLine in raw.lineSequence()) {
            var line = rawLine
            val hash = line.indexOf('#')
            if (hash != -1) line = line.substring(0, hash)
            line = line.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("[")) {
                current = result.getOrPut(sectionName(line).lowercase()) { HashMap() }
                continue
            }
            val fields = current ?: continue
            val eq = line.indexOf('=')
            if (eq > 0) {
                val key = line.substring(0, eq).trim().lowercase()
                fields[key] = line.substring(eq + 1).trim()
            }
        }
        return result
    }

    private fun parseUnsigned32(raw: String?): Long {
        val value = raw?.trim()?.ifEmpty { null } ?: return 0
        val parsed = if (value.startsWith("0x", ignoreCase = true))
            value.substring(2).toLongOrNull(16)
        else
            value.toLongOrNull()
        return (parsed ?: 0) and 0xFFFFFFFFL
    }

    private fun parseInstances(raw: String): List<InstanceBlock> {
        val blocks = ArrayList<InstanceBlock>()
        var current: MutableMap<String, String>? = null
        for (rawLine in raw.lineSequence()) {
            var line = rawLine
            val hash = line.indexOf('#')
            if (hash != -1) line = line.substring(0, hash)
            line = line.trim()
            if (line.isEmpty()) continue
            if (line.startsWith("[")) {
                current?.let { blocks.add(InstanceBlock(it)) }
                current = if (isInstanceHeader(line)) HashMap() else null
                continue
            }
            val fields = current ?: continue
            val eq = line.indexOf('=')
            if (eq > 0) {
                val key = line.substring(0, eq).trim().lowercase()
                val value = line.substring(eq + 1).trim()
                fields[key] = value
            }
        }
        current?.let { blocks.add(InstanceBlock(it)) }
        return blocks
    }

    private fun matchPeer(peers: List<Peer>, instance: InstanceBlock): Peer? {
        if (peers.size == 1) return peers[0]
        val listenPort = instance.sourceLport ?: return null
        return peers.firstOrNull { it.endpoint.map { ep -> ep.port }.orElse(-1) == listenPort }
    }

    private class InstanceBlock(private val fields: Map<String, String>) {
        val sourceLport: Int? get() = fields["source-lport"]?.toIntOrNull()

        fun toSettings(): ObfuscatorPeerSettings {
            val maskingType = Masking.normalize(fields["masking"])
            val obfuscateBytes = fields["obfuscate-bytes"]?.toIntOrNull()
                ?: if (maskingType == Masking.MEDIA) ObfuscatorPeerSettings.MEDIA_OBFUSCATE_BYTES_DEFAULT else 0
            return ObfuscatorPeerSettings(
                enabled = true,
                serverEndpoint = fields["target"].orEmpty().trim(),
                key = fields["key"].orEmpty().trim(),
                maskingType = maskingType,
                maxDummy = fields["max-dummy"]?.toIntOrNull() ?: ObfuscatorPeerSettings.DEFAULT_MAX_DUMMY,
                obfuscateBytes = obfuscateBytes,
                mediaPayloadType = fields["media-pt"]?.toIntOrNull() ?: 0,
                mediaSsrc = parseUnsigned32(fields["media-ssrc"]),
                mediaClock = fields["media-clock"]?.toIntOrNull() ?: 0
            )
        }
    }
}
