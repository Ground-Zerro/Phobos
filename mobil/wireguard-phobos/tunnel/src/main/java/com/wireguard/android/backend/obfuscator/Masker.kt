/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import java.net.InetAddress

enum class PacketDirection {
    ClientToServer,
    ServerToClient
}

typealias SendCallback = (ByteArray, Int) -> Int

interface Masker {
    val timerIntervalMillis: Long?

    fun onHandshakeRequest(
        direction: PacketDirection,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int

    fun onDataUnwrap(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int

    fun onDataWrap(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int, dstAddr: InetAddress, dstPort: Int,
        sendBack: SendCallback, sendForward: SendCallback
    ): Int

    fun onTimer(
        clientAddr: InetAddress, clientPort: Int, serverAddr: InetAddress, serverPort: Int,
        sendToClient: SendCallback, sendToServer: SendCallback
    )
}
