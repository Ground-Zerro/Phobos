/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.content.Context
import android.net.VpnService
import android.util.Log
import com.wireguard.config.Config
import com.wireguard.config.InetEndpoint
import com.wireguard.config.Peer

/**
 * Coordinates obfuscator engines with the WireGuard tunnel lifecycle. Driven by
 * [com.wireguard.android.backend.GoBackend].
 *
 * For every peer that has the obfuscator enabled a local proxy is started on
 * 127.0.0.1:<localPort> that forwards obfuscated traffic to the real server; the
 * peer endpoint handed to wireguard-go is rewritten to that loopback port.
 *
 * When the obfuscator is disabled the peer is left untouched and no proxy runs,
 * so a tunnel that is not in use costs no extra battery.
 */
object ObfuscatorIntegration {
    private const val TAG = "WireGuard/Obfuscator"

    private val active = ArrayList<ObfuscatorEngine>()

    @JvmStatic
    @Synchronized
    fun bringUp(context: Context, config: Config, tunnelName: String, vpnService: VpnService): Config {
        bringDown()

        val settings = ObfuscatorConfigStore(context).load(tunnelName)
        if (settings.isEmpty())
            return config

        var changed = false
        val newPeers = ArrayList<Peer>()
        try {
            for (peer in config.peers) {
                val publicKey = peer.publicKey.toBase64()
                val peerSettings = settings[publicKey]
                if (peerSettings == null || !peerSettings.enabled) {
                    newPeers.add(peer)
                    continue
                }

                val server = parseEndpoint(peerSettings.serverEndpoint)
                if (server == null) {
                    Log.w(TAG, "Obfuscator enabled for a peer but its server endpoint is invalid; passing through")
                    newPeers.add(peer)
                    continue
                }
                if (peerSettings.key.isEmpty()) {
                    Log.w(TAG, "Obfuscator enabled for a peer with an empty key; passing through")
                    newPeers.add(peer)
                    continue
                }

                NativeObfuscator.ensureLoaded(context)
                val engine = ObfuscatorEngine(
                    server.host,
                    server.port,
                    peerSettings.key.toByteArray(Charsets.UTF_8),
                    peerSettings.maskingType,
                    peerSettings.maxDummy,
                    peerSettings.obfuscateBytes,
                    peerSettings.mediaPayloadType,
                    peerSettings.mediaSsrc,
                    peerSettings.mediaTsStep
                ) { socket -> vpnService.protect(socket) }
                engine.start()
                active.add(engine)
                newPeers.add(rebuildPeer(peer, InetEndpoint.parse("127.0.0.1:${engine.listenPort}")))
                changed = true
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to start obfuscator", e)
            bringDown()
            throw e
        }

        if (!changed)
            return config

        return Config.Builder()
            .setInterface(config.getInterface())
            .addPeers(newPeers)
            .build()
    }

    /** Stops every running obfuscator engine. Safe to call repeatedly. */
    @JvmStatic
    @Synchronized
    fun bringDown() {
        for (engine in active)
            runCatching { engine.stop() }
        active.clear()
    }

    private fun parseEndpoint(value: String): InetEndpoint? {
        if (value.isBlank()) return null
        return try {
            InetEndpoint.parse(value.trim())
        } catch (e: Exception) {
            null
        }
    }

    private fun rebuildPeer(peer: Peer, endpoint: InetEndpoint): Peer {
        val builder = Peer.Builder()
        builder.setPublicKey(peer.publicKey)
        builder.addAllowedIps(peer.allowedIps)
        peer.preSharedKey.ifPresent { builder.setPreSharedKey(it) }
        peer.persistentKeepalive.ifPresent { builder.setPersistentKeepalive(it) }
        builder.setEndpoint(endpoint)
        return builder.build()
    }
}
