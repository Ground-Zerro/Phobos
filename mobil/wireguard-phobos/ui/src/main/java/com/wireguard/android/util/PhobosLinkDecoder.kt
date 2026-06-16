package com.wireguard.android.util

import android.util.Base64
import java.net.URLDecoder

object PhobosLinkDecoder {
    private const val SCHEME = "phobos://"
    private val VALID_NAME = Regex("[a-zA-Z0-9_=+.\\-]")

    data class Result(val configText: String, val nameHint: String?)

    fun isPhobosLink(text: String) = text.trimStart().startsWith(SCHEME, ignoreCase = true)

    fun decode(link: String): Result {
        val trimmed = link.trim()
        require(isPhobosLink(trimmed)) { "Not a phobos:// link" }

        val withoutScheme = trimmed.substring(SCHEME.length)
        val hashIdx = withoutScheme.indexOf('#')
        val payload = if (hashIdx >= 0) withoutScheme.substring(0, hashIdx) else withoutScheme
        val fragment = if (hashIdx >= 0) withoutScheme.substring(hashIdx + 1) else ""

        val bytes = Base64.decode(payload, Base64.URL_SAFE or Base64.NO_PADDING)
        val confText = bytes.toString(Charsets.UTF_8)

        val cleanedConf = stripNoneValues(confText)

        val nameHint = if (fragment.isNotEmpty() && fragment != "none") {
            sanitizeName(URLDecoder.decode(fragment, "UTF-8"))
        } else null

        return Result(cleanedConf, nameHint)
    }

    private fun stripNoneValues(conf: String): String {
        return conf.lines().filter { line ->
            val eqIdx = line.indexOf('=')
            if (eqIdx < 0) return@filter true
            line.substring(eqIdx + 1).trim() != "none"
        }.joinToString("\n")
    }

    private fun sanitizeName(raw: String): String? {
        val sanitized = raw.map { c -> if (VALID_NAME.matches(c.toString())) c else '_' }
            .joinToString("")
            .take(15)
        return sanitized.ifBlank { null }
    }
}
