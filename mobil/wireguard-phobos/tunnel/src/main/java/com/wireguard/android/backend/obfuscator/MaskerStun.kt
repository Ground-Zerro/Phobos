/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.util.Log
import java.net.InetAddress

class MaskerStun : Masker {
    companion object {
        private const val TAG = "WireGuard/Obfuscator"
    }

    override val timerIntervalMillis: Long = 10_000L

    override fun onHandshakeRequest(
        direction: PacketDirection,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int {
        val buffer = ByteArray(128)
        val len = Stun.buildBindingRequest(buffer)
        val sent = sendForward(buffer, len)
        if (sent != len) {
            Log.w(TAG, "Partial send of STUN binding request to $dstAddr:$dstPort ($sent/$len)")
        }
        return 0
    }

    override fun onDataUnwrap(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int {
        if (!Stun.checkMagic(data, length)) return -1
        return Stun.handleIncoming(data, length, srcAddr, srcPort, sendBack)
    }

    override fun onDataWrap(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int = Stun.wrapDataIndication(data, length)

    override fun onTimer(
        clientAddr: InetAddress, clientPort: Int, serverAddr: InetAddress, serverPort: Int,
        sendToClient: SendCallback, sendToServer: SendCallback
    ) {
        val buffer = ByteArray(128)
        val len = Stun.buildBindingRequest(buffer)
        if (len < 0) return
        sendToServer(buffer, len)
    }
}
