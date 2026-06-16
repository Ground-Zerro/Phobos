/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.content.Context
import com.wireguard.android.util.SharedLibraryLoader

object NativeObfuscator {
    @Volatile
    private var loaded = false

    @Synchronized
    fun ensureLoaded(context: Context) {
        if (loaded) return
        SharedLibraryLoader.loadSharedLibrary(context, "wg-obfuscator")
        loaded = true
    }

    fun encode(buffer: ByteArray, length: Int, key: ByteArray, maxDummy: Int, obfuscateBytes: Int): Int =
        nativeEncode(buffer, length, key, maxDummy, obfuscateBytes)

    fun decode(buffer: ByteArray, length: Int, key: ByteArray, obfuscateBytes: Int): Int =
        nativeDecode(buffer, length, key, obfuscateBytes)

    private external fun nativeEncode(buffer: ByteArray, length: Int, key: ByteArray, maxDummy: Int, obfuscateBytes: Int): Int

    private external fun nativeDecode(buffer: ByteArray, length: Int, key: ByteArray, obfuscateBytes: Int): Int
}
