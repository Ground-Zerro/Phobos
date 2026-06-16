/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.util.Log
import java.net.InetAddress
import java.security.SecureRandom

class MaskerMedia(
    private val mediaPayloadType: Int,
    private val mediaSsrc: Long,
    private val mediaTsStep: Int
) : Masker {
    companion object {
        private const val TAG = "WireGuard/Obfuscator"
        private const val RTP_HEADER_SIZE = 12
        private const val BUFFER_SIZE = 65535

        private val PRESET_PT = intArrayOf(
            96, 96, 96, 96, 96, 97, 97, 97, 97, 97,
            98, 98, 98, 98, 98, 99, 99, 100, 100, 100,
            102, 102, 102, 104, 104, 106, 106, 108, 108, 110,
            112, 112, 114, 114, 116, 118, 119, 120, 122, 123,
            124, 125, 125, 126, 127, 127, 127, 96, 96, 97
        )
        private val PRESET_TS_STEP = intArrayOf(
            3000, 3600, 3750, 1500, 6000, 3000, 3600, 4500, 9000, 18000,
            3000, 3600, 3750, 1500, 6000, 3000, 3600, 3000, 1500, 3750,
            3000, 1500, 3600, 3000, 1500, 3000, 3750, 3000, 1500, 3000,
            3000, 3600, 3000, 1500, 3000, 3000, 3000, 3000, 3000, 3000,
            3000, 3000, 1500, 3000, 3000, 1500, 3750, 1502, 3003, 3753
        )
    }

    override val timerIntervalMillis: Long = 5_000L

    private val rng = SecureRandom()

    private var initialized = false
    private var seq = 0
    private var timestamp = 0
    private var ssrc = 0
    private var tsStep = 0
    private var payloadType = 0

    private fun ensureInitialized() {
        if (initialized) return
        seq = rng.nextInt() and 0xFFFF
        timestamp = rng.nextInt()
        ssrc = if (mediaSsrc != 0L) {
            mediaSsrc.toInt()
        } else {
            val r = rng.nextInt()
            if (r != 0) r else 1
        }
        val preset = rng.nextInt(PRESET_PT.size)
        payloadType = if (mediaPayloadType != 0) mediaPayloadType else PRESET_PT[preset]
        tsStep = if (mediaTsStep != 0) mediaTsStep else PRESET_TS_STEP[preset]
        initialized = true
    }

    private fun buildFrame(header: ByteArray) {
        ensureInitialized()
        header[0] = 0x80.toByte()
        header[1] = (0x80 or (payloadType and 0x7F)).toByte()
        header[2] = ((seq ushr 8) and 0xFF).toByte()
        header[3] = (seq and 0xFF).toByte()
        header[4] = ((timestamp ushr 24) and 0xFF).toByte()
        header[5] = ((timestamp ushr 16) and 0xFF).toByte()
        header[6] = ((timestamp ushr 8) and 0xFF).toByte()
        header[7] = (timestamp and 0xFF).toByte()
        header[8] = ((ssrc ushr 24) and 0xFF).toByte()
        header[9] = ((ssrc ushr 16) and 0xFF).toByte()
        header[10] = ((ssrc ushr 8) and 0xFF).toByte()
        header[11] = (ssrc and 0xFF).toByte()

        seq = (seq + 1) and 0xFFFF
        timestamp += tsStep
    }

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
        if (Stun.checkMagic(data, length))
            return Stun.handleIncoming(data, length, srcAddr, srcPort, sendBack)

        if (length < RTP_HEADER_SIZE + 4) return -1
        if ((data[0].toInt() and 0xC0) != 0x80) return -1
        if (mediaPayloadType != 0 && (data[1].toInt() and 0x7F) != mediaPayloadType) return -1
        if (mediaSsrc != 0L) {
            val pktSsrc = ((data[8].toInt() and 0xFF) shl 24) or
                    ((data[9].toInt() and 0xFF) shl 16) or
                    ((data[10].toInt() and 0xFF) shl 8) or
                    (data[11].toInt() and 0xFF)
            if (pktSsrc != mediaSsrc.toInt()) return -1
        }

        val dataLen = length - RTP_HEADER_SIZE
        System.arraycopy(data, RTP_HEADER_SIZE, data, 0, dataLen)
        return dataLen
    }

    override fun onDataWrap(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int {
        if (length + RTP_HEADER_SIZE > minOf(data.size, BUFFER_SIZE)) {
            Log.w(TAG, "Can't wrap data in RTP, data too large ($length bytes)")
            return -12
        }
        System.arraycopy(data, 0, data, RTP_HEADER_SIZE, length)
        buildFrame(data)
        return length + RTP_HEADER_SIZE
    }

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
