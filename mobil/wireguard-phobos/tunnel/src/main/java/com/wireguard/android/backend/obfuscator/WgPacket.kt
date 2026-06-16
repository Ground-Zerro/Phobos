/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

internal object WgPacket {
    const val TYPE_HANDSHAKE = 0x01
    const val TYPE_HANDSHAKE_RESP = 0x02
    const val TYPE_COOKIE = 0x03
    const val TYPE_DATA = 0x04

    fun type(data: ByteArray): Int =
        (data[0].toInt() and 0xFF) or
                ((data[1].toInt() and 0xFF) shl 8) or
                ((data[2].toInt() and 0xFF) shl 16) or
                ((data[3].toInt() and 0xFF) shl 24)
}
