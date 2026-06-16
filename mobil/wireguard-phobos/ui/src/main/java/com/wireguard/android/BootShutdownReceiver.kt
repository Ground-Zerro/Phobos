/*
 * Copyright © 2017-2025 WireGuard LLC. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
package com.wireguard.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.wireguard.android.backend.WgQuickBackend
import com.wireguard.android.model.PhobosMonitorService
import com.wireguard.android.util.UserKnobs
import com.wireguard.android.util.applicationScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class BootShutdownReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        applicationScope.launch {
            if (action == Intent.ACTION_BOOT_COMPLETED) {
                val disableOnWifi = UserKnobs.disableTunnelsOnWifi.first()
                val autoSwitch = UserKnobs.tunnelAutoSwitch.first()
                if (disableOnWifi || autoSwitch) {
                    PhobosMonitorService.start(context)
                }
            }
            if (Application.getBackend() !is WgQuickBackend) return@launch
            val tunnelManager = Application.getTunnelManager()
            if (action == Intent.ACTION_BOOT_COMPLETED) {
                Log.i(TAG, "Broadcast receiver restoring state (boot)")
                tunnelManager.restoreState(false)
            } else if (action == Intent.ACTION_SHUTDOWN) {
                Log.i(TAG, "Broadcast receiver saving state (shutdown)")
                tunnelManager.saveState()
            }
        }
    }

    companion object {
        private const val TAG = "WireGuard/BootShutdownReceiver"
    }
}
