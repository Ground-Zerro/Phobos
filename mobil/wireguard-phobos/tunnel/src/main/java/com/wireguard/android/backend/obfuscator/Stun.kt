/*
 * Copyright © 2025 Phobos. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.backend.obfuscator

import android.util.Log
import java.net.InetAddress
import java.security.SecureRandom

object Stun {
    private const val TAG = "WireGuard/Obfuscator"

    private val COOKIE_BE = byteArrayOf(0x21, 0x12, 0xA4.toByte(), 0x42)

    const val BINDING_REQ = 0x0001
    const val BINDING_RESP = 0x0101
    const val TYPE_DATA_IND = 0x0115

    private const val ATTR_XORMAPPED = 0x0020
    private const val ATTR_FINGERPR = 0x8028
    private const val ATTR_DATA = 0x0013

    private const val BUFFER_SIZE = 65535

    private val rng = SecureRandom()

    private fun randBytes(p: ByteArray, n: Int) {
        require(n <= p.size)
        val tmp = ByteArray(n)
        rng.nextBytes(tmp)
        System.arraycopy(tmp, 0, p, 0, n)
    }

    private fun u16be(value: Int, dst: ByteArray, off: Int) {
        dst[off] = ((value ushr 8) and 0xFF).toByte()
        dst[off + 1] = (value and 0xFF).toByte()
    }

    private fun ru16be(src: ByteArray, off: Int): Int {
        val b0 = src[off].toInt() and 0xFF
        val b1 = src[off + 1].toInt() and 0xFF
        return (b0 shl 8) or b1
    }

    private fun u32be(value: Int, dst: ByteArray, off: Int) {
        dst[off] = ((value ushr 24) and 0xFF).toByte()
        dst[off + 1] = ((value ushr 16) and 0xFF).toByte()
        dst[off + 2] = ((value ushr 8) and 0xFF).toByte()
        dst[off + 3] = (value and 0xFF).toByte()
    }

    fun checkMagic(buf: ByteArray?, len: Int): Boolean {
        if (buf == null || len < 8) return false
        return buf[4] == COOKIE_BE[0] &&
                buf[5] == COOKIE_BE[1] &&
                buf[6] == COOKIE_BE[2] &&
                buf[7] == COOKIE_BE[3]
    }

    fun peekType(buf: ByteArray): Int = ru16be(buf, 0)

    private fun writeHeader(b: ByteArray, type: Int, mlen: Int, txid: ByteArray): Int {
        require(txid.size >= 12)
        u16be(type, b, 0)
        u16be(mlen, b, 2)
        System.arraycopy(COOKIE_BE, 0, b, 4, 4)
        System.arraycopy(txid, 0, b, 8, 12)
        return 20
    }

    private fun attrXorMappedAddr(b: ByteArray, off: Int, address: InetAddress, port: Int): Int {
        u16be(ATTR_XORMAPPED, b, off + 0)
        u16be(8, b, off + 2)
        b[off + 4] = 0
        b[off + 5] = 0x01

        val p0 = (port ushr 8) and 0xFF
        val p1 = port and 0xFF
        b[off + 6] = (p0 xor (COOKIE_BE[0].toInt() and 0xFF)).toByte()
        b[off + 7] = (p1 xor (COOKIE_BE[1].toInt() and 0xFF)).toByte()

        val ip = address.address
        require(ip.size == 4) { "IPv4 address required for STUN XOR-MAPPED-ADDRESS" }
        b[off + 8] = (ip[0].toInt() xor (COOKIE_BE[0].toInt() and 0xFF)).toByte()
        b[off + 9] = (ip[1].toInt() xor (COOKIE_BE[1].toInt() and 0xFF)).toByte()
        b[off + 10] = (ip[2].toInt() xor (COOKIE_BE[2].toInt() and 0xFF)).toByte()
        b[off + 11] = (ip[3].toInt() xor (COOKIE_BE[3].toInt() and 0xFF)).toByte()

        return 12
    }

    private fun crc32(p: ByteArray, n: Int): Int {
        var crc = -1
        for (i in 0 until n) {
            crc = crc xor (p[i].toInt() and 0xFF)
            repeat(8) {
                val mask = -(crc and 1)
                crc = (crc ushr 1) xor (0xEDB88320.toInt() and mask)
            }
        }
        return crc.inv()
    }

    private fun attrFingerprint(pkt: ByteArray, curLen: Int): Int {
        val bOff = curLen
        u16be(ATTR_FINGERPR, pkt, bOff + 0)
        u16be(4, pkt, bOff + 2)
        val fp = crc32(pkt, curLen) xor 0x5354554E
        u32be(fp, pkt, bOff + 4)
        return 8
    }

    fun buildBindingRequest(out: ByteArray): Int {
        val txid = ByteArray(12)
        randBytes(txid, 12)
        writeHeader(out, BINDING_REQ, 0, txid)
        var mlen = 0
        mlen += attrFingerprint(out, 20 + mlen)
        u16be(mlen, out, 2)
        return 20 + mlen
    }

    private fun buildBindingSuccess(out: ByteArray, txid: ByteArray, address: InetAddress, port: Int): Int {
        if (out.size < 40) return -1
        writeHeader(out, BINDING_RESP, 0, txid)
        var mlen = 0
        mlen += attrXorMappedAddr(out, 20 + mlen, address, port)
        mlen += attrFingerprint(out, 20 + mlen)
        u16be(mlen, out, 2)
        return 20 + mlen
    }

    fun wrapDataIndication(buf: ByteArray, dataLen: Int): Int {
        val headerSize = 20
        val attrHeader = 4
        val totalAdd = headerSize + attrHeader
        if (dataLen + totalAdd > minOf(buf.size, BUFFER_SIZE)) {
            return -12
        }
        System.arraycopy(buf, 0, buf, totalAdd, dataLen)
        val txid = ByteArray(12)
        randBytes(txid, 12)
        writeHeader(buf, TYPE_DATA_IND, 0, txid)
        val mlen = headerSize
        u16be(ATTR_DATA, buf, mlen + 0)
        u16be(dataLen, buf, mlen + 2)
        return headerSize + attrHeader + dataLen
    }

    private fun unwrapDataIndication(buf: ByteArray, len: Int): Int {
        if (len < 24) return -1
        val msgType = ru16be(buf, 0)
        if (msgType != TYPE_DATA_IND) return -1
        val msgLen = ru16be(buf, 2)
        if (msgLen + 20 > len) return -1
        val attrType = ru16be(buf, 20)
        if (attrType != ATTR_DATA) return -1
        val dataLen = ru16be(buf, 22)
        if (dataLen + 24 > len) return -1
        System.arraycopy(buf, 24, buf, 0, dataLen)
        return dataLen
    }

    fun handleIncoming(
        data: ByteArray, length: Int,
        srcAddr: InetAddress, srcPort: Int,
        sendBack: SendCallback
    ): Int {
        when (peekType(data)) {
            BINDING_REQ -> {
                if (data.size < 20 || length < 20) {
                    Log.e(TAG, "STUN packet too small to contain txid")
                    return -1
                }
                val txid = ByteArray(12)
                System.arraycopy(data, 8, txid, 0, 12)
                val respLen = buildBindingSuccess(data, txid, srcAddr, srcPort)
                if (respLen > 0) {
                    try {
                        sendBack(data, respLen)
                    } catch (e: Exception) {
                        Log.e(TAG, "STUN sendBack callback threw", e)
                        return -1
                    }
                } else {
                    Log.e(TAG, "Failed to build STUN binding success response")
                }
                return 0
            }

            BINDING_RESP -> return 0

            TYPE_DATA_IND -> {
                val unwrappedLen = unwrapDataIndication(data, length)
                if (unwrappedLen < 0) {
                    Log.d(TAG, "Failed to unwrap STUN data indication from $srcAddr:$srcPort")
                }
                return unwrappedLen
            }

            else -> return 0
        }
    }
}
