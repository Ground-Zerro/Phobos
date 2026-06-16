/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketException

/**
 * In-process UDP proxy that obfuscates WireGuard traffic. It listens on a loopback
 * port for the local wireguard-go instance and forwards obfuscated packets to the
 * real server. The upstream socket must be protected from the VPN tunnel via the
 * [protect] callback to avoid a routing loop.
 */
class ObfuscatorEngine(
    private val remoteHost: String,
    private val remotePort: Int,
    private val key: ByteArray,
    maskingTypeId: String,
    private val maxDummy: Int,
    private val obfuscateBytes: Int,
    mediaPayloadType: Int,
    mediaSsrc: Long,
    mediaTsStep: Int,
    private val protect: (DatagramSocket) -> Boolean
) {
    enum class Phase { STARTING, WAITING_HANDSHAKE, HANDSHAKE_SENT, CONNECTED, STOPPED, ERROR }

    private val masker: Masker? = Masking.createMasker(maskingTypeId, mediaPayloadType, mediaSsrc, mediaTsStep)

    @Volatile
    var listenPort: Int = 0
        private set

    @Volatile
    var phase: Phase = Phase.STOPPED
        private set

    @Volatile
    var tx: Long = 0
        private set

    @Volatile
    var rx: Long = 0
        private set

    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    private var running = false
    private var listenSocket: DatagramSocket? = null
    private var remoteSocket: DatagramSocket? = null
    private lateinit var remoteAddress: InetAddress
    private val threads = ArrayList<Thread>()

    @Volatile
    private var clientAddress: InetAddress? = null

    @Volatile
    private var clientPort: Int = 0

    @Volatile
    private var handshakeSent = false

    @Volatile
    private var handshakeResponded = false

    fun start() {
        check(key.isNotEmpty()) { "Obfuscation key is empty" }
        phase = Phase.STARTING
        remoteAddress = InetAddress.getByName(remoteHost)

        val ls = DatagramSocket(InetSocketAddress(LOOPBACK, 0))
        listenSocket = ls
        listenPort = ls.localPort

        val rs = DatagramSocket()
        remoteSocket = rs
        if (!protect(rs)) {
            ls.close()
            rs.close()
            throw IllegalStateException("Failed to protect obfuscator upstream socket")
        }

        running = true
        phase = Phase.WAITING_HANDSHAKE
        startThread("wg-obfuscator-client") { clientLoop(ls, rs) }
        startThread("wg-obfuscator-server") { serverLoop(ls, rs) }
        val m = masker
        val interval = m?.timerIntervalMillis
        if (m != null && interval != null) {
            startThread("wg-obfuscator-timer") { timerLoop(ls, rs, m, interval) }
        }
        Log.i(TAG, "Obfuscator started: 127.0.0.1:$listenPort -> $remoteHost:$remotePort")
    }

    fun stop() {
        running = false
        listenSocket?.close()
        remoteSocket?.close()
        for (t in threads) t.interrupt()
        for (t in threads) runCatching { t.join(500) }
        threads.clear()
        listenSocket = null
        remoteSocket = null
        phase = Phase.STOPPED
        Log.i(TAG, "Obfuscator stopped (tx=$tx rx=$rx, last error: ${lastError ?: "none"})")
    }

    private fun startThread(name: String, body: () -> Unit) {
        val t = Thread(body, name)
        t.isDaemon = true
        threads.add(t)
        t.start()
    }

    private fun makeSendToServer(rs: DatagramSocket): SendCallback {
        val pkt = DatagramPacket(EMPTY, 0, remoteAddress, remotePort)
        return { data, length ->
            pkt.setData(data, 0, length)
            rs.send(pkt)
            length
        }
    }

    private fun makeSendToClient(ls: DatagramSocket): SendCallback {
        val pkt = DatagramPacket(EMPTY, 0)
        return { data, length ->
            val ca = clientAddress
            if (ca == null) {
                0
            } else {
                pkt.setData(data, 0, length)
                pkt.address = ca
                pkt.port = clientPort
                ls.send(pkt)
                length
            }
        }
    }

    private fun clientLoop(ls: DatagramSocket, rs: DatagramSocket) {
        val buffer = ByteArray(BUFFER_SIZE)
        val packet = DatagramPacket(buffer, buffer.size)
        val sendToClient = makeSendToClient(ls)
        val sendToServer = makeSendToServer(rs)
        while (running) {
            try {
                packet.setData(buffer, 0, buffer.size)
                ls.receive(packet)
                if (packet.length < 4) continue
                val packetType = WgPacket.type(buffer)
                if (packetType < WgPacket.TYPE_HANDSHAKE || packetType > WgPacket.TYPE_DATA) {
                    Log.w(TAG, "Unknown packet from client, type=$packetType")
                    continue
                }
                var length = NativeObfuscator.encode(buffer, packet.length, key, maxDummy, obfuscateBytes)
                if (length < 0) {
                    Log.w(TAG, "Failed to encode packet")
                    continue
                }
                if (clientAddress != packet.address || clientPort != packet.port) {
                    clientAddress = packet.address
                    clientPort = packet.port
                    handshakeSent = false
                    handshakeResponded = false
                }
                val m = masker
                if (m != null) {
                    val ca = clientAddress!!
                    if (packetType == WgPacket.TYPE_HANDSHAKE) {
                        m.onHandshakeRequest(
                            PacketDirection.ClientToServer,
                            ca, clientPort, remoteAddress, remotePort,
                            sendToClient, sendToServer
                        )
                    }
                    length = m.onDataWrap(
                        buffer, length, ca, clientPort, remoteAddress, remotePort,
                        sendToClient, sendToServer
                    )
                    if (length <= 0) continue
                }
                tx += sendToServer(buffer, length)
                if (packetType == WgPacket.TYPE_HANDSHAKE && !handshakeSent) {
                    handshakeSent = true
                    if (phase == Phase.WAITING_HANDSHAKE) phase = Phase.HANDSHAKE_SENT
                }
            } catch (e: SocketException) {
                if (!running) break
                fail(e)
                break
            } catch (e: Exception) {
                fail(e)
                break
            }
        }
    }

    private fun serverLoop(ls: DatagramSocket, rs: DatagramSocket) {
        val buffer = ByteArray(BUFFER_SIZE)
        val packet = DatagramPacket(buffer, buffer.size)
        val sendToClient = makeSendToClient(ls)
        val sendToServer = makeSendToServer(rs)
        while (running) {
            try {
                packet.setData(buffer, 0, buffer.size)
                rs.receive(packet)
                if (packet.address != remoteAddress || packet.port != remotePort) {
                    Log.w(TAG, "Unexpected packet from ${packet.address}:${packet.port}")
                    continue
                }
                val ca = clientAddress ?: continue
                rx += packet.length
                var length = packet.length
                val m = masker
                if (m != null) {
                    length = m.onDataUnwrap(
                        buffer, length, remoteAddress, remotePort, ca, clientPort,
                        sendToServer, sendToClient
                    )
                    if (length <= 0) continue
                }
                if (length < 4) continue
                val decoded = NativeObfuscator.decode(buffer, length, key, obfuscateBytes)
                if (decoded < 4) {
                    Log.w(TAG, "Failed to decode packet from server")
                    continue
                }
                val packetType = WgPacket.type(buffer)
                if (packetType < WgPacket.TYPE_HANDSHAKE || packetType > WgPacket.TYPE_DATA) {
                    Log.w(TAG, "Decoded unknown packet, type=$packetType")
                    continue
                }
                if (packetType == WgPacket.TYPE_HANDSHAKE_RESP && !handshakeResponded && handshakeSent) {
                    handshakeResponded = true
                    phase = Phase.CONNECTED
                }
                sendToClient(buffer, decoded)
            } catch (e: SocketException) {
                if (!running) break
                fail(e)
                break
            } catch (e: Exception) {
                fail(e)
                break
            }
        }
    }

    private fun timerLoop(ls: DatagramSocket, rs: DatagramSocket, m: Masker, interval: Long) {
        val sendToClient = makeSendToClient(ls)
        val sendToServer = makeSendToServer(rs)
        while (running) {
            try {
                Thread.sleep(interval)
                val ca = clientAddress ?: continue
                m.onTimer(ca, clientPort, remoteAddress, remotePort, sendToClient, sendToServer)
            } catch (e: InterruptedException) {
                break
            } catch (e: Exception) {
                Log.e(TAG, "Masking timer error", e)
            }
        }
    }

    private fun fail(e: Exception) {
        if (!running) return
        lastError = e.message ?: e.javaClass.simpleName
        phase = Phase.ERROR
        Log.e(TAG, "Obfuscator error", e)
        running = false
        listenSocket?.close()
        remoteSocket?.close()
    }

    companion object {
        private const val TAG = "WireGuard/Obfuscator"
        private const val BUFFER_SIZE = 65535
        private val EMPTY = ByteArray(0)
        private val LOOPBACK: InetAddress = InetAddress.getByName("127.0.0.1")
    }
}
