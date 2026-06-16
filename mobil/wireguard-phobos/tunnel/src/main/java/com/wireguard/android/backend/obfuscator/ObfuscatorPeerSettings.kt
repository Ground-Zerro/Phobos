/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

data class ObfuscatorPeerSettings(
    val enabled: Boolean = false,
    val serverEndpoint: String = "",
    val key: String = "",
    val maskingType: String = Masking.NONE,
    val maxDummy: Int = DEFAULT_MAX_DUMMY,
    val obfuscateBytes: Int = 0,
    val mediaPayloadType: Int = 0,
    val mediaSsrc: Long = 0,
    val mediaClock: Int = 0
) {
    val isMeaningful: Boolean
        get() = enabled || serverEndpoint.isNotEmpty() || key.isNotEmpty() || maskingType != Masking.NONE

    val mediaTsStep: Int
        get() = if (mediaClock > 0) 90000 / mediaClock else 0

    companion object {
        const val DEFAULT_MAX_DUMMY = 4
        const val MEDIA_OBFUSCATE_BYTES_DEFAULT = 16
    }
}
