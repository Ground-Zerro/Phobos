/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

object Masking {
    const val NONE = "none"
    const val STUN = "stun"
    const val MEDIA = "media"
    const val TLS = "tls"

    val ids: List<String> = listOf(NONE, STUN, MEDIA)

    fun normalize(id: String?): String {
        val value = id?.trim()?.lowercase() ?: return NONE
        return if (ids.contains(value)) value else NONE
    }

    fun normalizeSocks5(id: String?): String = when (id?.trim()?.lowercase()) {
        STUN -> STUN
        MEDIA -> MEDIA
        TLS -> TLS
        else -> NONE
    }

    fun socks5MaskId(id: String?): Int = when (normalizeSocks5(id)) {
        STUN -> 1
        MEDIA -> 2
        TLS -> 3
        else -> 0
    }

    fun createMasker(id: String, mediaPayloadType: Int, mediaSsrc: Long, mediaTsStep: Int): Masker? =
        when (normalize(id)) {
            STUN -> MaskerStun()
            MEDIA -> MaskerMedia(mediaPayloadType, mediaSsrc, mediaTsStep)
            else -> null
        }
}
