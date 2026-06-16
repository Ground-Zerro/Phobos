/*
 * Copyright © 2017-2025 WireGuard LLC. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android.fragment

import android.app.Dialog
import android.os.Bundle
import android.view.WindowManager
import androidx.fragment.app.DialogFragment
import androidx.lifecycle.lifecycleScope
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.wireguard.android.Application
import com.wireguard.android.R
import com.wireguard.android.backend.obfuscator.ObfuscatorConfigParser
import com.wireguard.android.backend.obfuscator.ObfuscatorConfigStore
import com.wireguard.android.databinding.ConfigNamingDialogFragmentBinding
import com.wireguard.config.BadConfigException
import com.wireguard.config.Config
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.charset.StandardCharsets

class ConfigNamingDialogFragment : DialogFragment() {
    private var binding: ConfigNamingDialogFragmentBinding? = null
    private var config: Config? = null

    private fun createTunnelAndDismiss() {
        val binding = binding ?: return
        val activity = activity ?: return
        val name = binding.tunnelNameText.text.toString()
        val cfg = config
        val rawConfig = requireArguments().getString(KEY_CONFIG_TEXT).orEmpty()
        activity.lifecycleScope.launch {
            try {
                val tunnel = Application.getTunnelManager().create(name, cfg)
                if (cfg != null) {
                    val obfuscator = withContext(Dispatchers.IO) {
                        ObfuscatorConfigParser.peerSettingsFrom(rawConfig, cfg)
                    }
                    if (obfuscator.isNotEmpty()) withContext(Dispatchers.IO) {
                        ObfuscatorConfigStore(activity.applicationContext).save(tunnel.name, obfuscator)
                    }
                }
                dismiss()
            } catch (e: Throwable) {
                binding.tunnelNameTextLayout.error = e.message
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val configText = requireArguments().getString(KEY_CONFIG_TEXT)
        val configBytes = ObfuscatorConfigParser.stripInstanceSections(configText!!).toByteArray(StandardCharsets.UTF_8)
        config = try {
            Config.parse(ByteArrayInputStream(configBytes))
        } catch (e: Throwable) {
            when (e) {
                is BadConfigException, is IOException -> throw IllegalArgumentException("Invalid config passed to ${javaClass.simpleName}", e)
                else -> throw e
            }
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val activity = requireActivity()
        val alertDialogBuilder = MaterialAlertDialogBuilder(activity)
        alertDialogBuilder.setTitle(R.string.import_from_qr_code)
        binding = ConfigNamingDialogFragmentBinding.inflate(activity.layoutInflater, null, false)
        binding?.apply {
            executePendingBindings()
            val nameHint = arguments?.getString(KEY_NAME_HINT)
            if (!nameHint.isNullOrBlank()) tunnelNameText.setText(nameHint)
            alertDialogBuilder.setView(root)
        }
        alertDialogBuilder.setPositiveButton(R.string.create_tunnel) { _, _ -> createTunnelAndDismiss() }
        alertDialogBuilder.setNegativeButton(R.string.cancel) { _, _ -> dismiss() }
        val dialog = alertDialogBuilder.create()
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        return dialog
    }

    companion object {
        private const val KEY_CONFIG_TEXT = "config_text"
        private const val KEY_NAME_HINT = "name_hint"

        fun newInstance(configText: String?, nameHint: String? = null): ConfigNamingDialogFragment {
            val extras = Bundle()
            extras.putString(KEY_CONFIG_TEXT, configText)
            if (nameHint != null) extras.putString(KEY_NAME_HINT, nameHint)
            val fragment = ConfigNamingDialogFragment()
            fragment.arguments = extras
            return fragment
        }
    }
}
