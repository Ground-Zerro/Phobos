/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

object Masking {
    const val NONE = "none"
    const val STUN = "stun"
    const val MEDIA = "media"

    val ids: List<String> = listOf(NONE, STUN, MEDIA)

    fun normalize(id: String?): String {
        val value = id?.trim()?.lowercase() ?: return NONE
        return if (ids.contains(value)) value else NONE
    }

    fun createMasker(id: String, mediaPayloadType: Int, mediaSsrc: Long, mediaTsStep: Int): Masker? =
        when (normalize(id)) {
            STUN -> MaskerStun()
            MEDIA -> MaskerMedia(mediaPayloadType, mediaSsrc, mediaTsStep)
            else -> null
        }
}
