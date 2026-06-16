package com.wireguard.android.model

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.wireguard.android.Application
import com.wireguard.android.R
import com.wireguard.android.backend.Tunnel
import com.wireguard.android.util.UserKnobs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class PhobosMonitorService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val connectivityManager by lazy {
        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private val mutex = Mutex()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var switchLoopJob: Job? = null
    private var wifiCleanupJob: Job? = null
    @Volatile
    private var wifiActive = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        registerNetworkCallback()
        scope.launch { applyForCurrentNetwork() }
        if (switchLoopJob?.isActive != true) {
            switchLoopJob = scope.launch { tunnelSwitchLoop() }
        }
        if (wifiCleanupJob?.isActive != true) {
            wifiCleanupJob = scope.launch {
                UserKnobs.disableTunnelsOnWifi.collect { enabled -> if (!enabled) restoreTunnelsAfterWifi() }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        unregisterNetworkCallback()
        scope.coroutineContext[Job]?.cancel()
        super.onDestroy()
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                wifiActive = true
                scope.launch { disableTunnelsForWifi() }
            }
            override fun onLost(network: Network) {
                wifiActive = false
                scope.launch {
                    delay(WIFI_LOST_DEBOUNCE_MS)
                    if (!isWifiNetworkAvailable()) restoreTunnelsAfterWifi()
                }
            }
        }
        try {
            connectivityManager.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (e: Throwable) {
            Log.e(TAG, Log.getStackTraceString(e))
        }
    }

    private fun unregisterNetworkCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            connectivityManager.unregisterNetworkCallback(cb)
        } catch (e: Throwable) {
            Log.e(TAG, Log.getStackTraceString(e))
        }
    }

    @Suppress("DEPRECATION")
    private fun isWifiNetworkAvailable(): Boolean =
        connectivityManager.allNetworks.any { network ->
            connectivityManager.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }

    private suspend fun disableTunnelsForWifi() {
        if (!UserKnobs.disableTunnelsOnWifi.first()) return
        mutex.withLock {
            val tunnels = Application.getTunnelManager().getTunnels()
            if (UserKnobs.tunnelsDownedByWifi.first().isNotEmpty()) {
                // Already in WiFi-disable mode — also down any tunnel brought up by the switch loop
                tunnels.filter { it.state == Tunnel.State.UP }
                    .forEach { runCatching { it.setStateAsync(Tunnel.State.DOWN) } }
                return@withLock
            }
            val running = tunnels.filter { it.state == Tunnel.State.UP }
            if (running.isEmpty()) return@withLock
            UserKnobs.setTunnelsDownedByWifi(running.map { it.name }.toSet())
            running.forEach { runCatching { it.setStateAsync(Tunnel.State.DOWN) } }
        }
    }

    private suspend fun restoreTunnelsAfterWifi() {
        mutex.withLock {
            val names = UserKnobs.tunnelsDownedByWifi.first()
            if (names.isEmpty()) return@withLock
            val tunnels = Application.getTunnelManager().getTunnels()
            names.forEach { name -> tunnels[name]?.let { runCatching { it.setStateAsync(Tunnel.State.UP) } } }
            UserKnobs.setTunnelsDownedByWifi(emptySet())
        }
    }

    private suspend fun applyForCurrentNetwork() {
        if (isWifiNetworkAvailable()) {
            wifiActive = true
            disableTunnelsForWifi()
        } else {
            restoreTunnelsAfterWifi()
        }
    }

    private suspend fun tunnelSwitchLoop() {
        var cycleCount = 0
        var lastActiveName = ""

        while (true) {
            val intervalMs = UserKnobs.tunnelSwitchCheckInterval.first() * 1000L
            delay(intervalMs)

            if (wifiActive && UserKnobs.disableTunnelsOnWifi.first()) continue
            if (!UserKnobs.tunnelAutoSwitch.first()) continue

            val switchOrder = UserKnobs.tunnelSwitchOrder.first()
            if (switchOrder.isEmpty()) continue

            val tunnels = Application.getTunnelManager().getTunnels()
            val activeTunnel = tunnels.firstOrNull {
                it.state == Tunnel.State.UP && switchOrder.contains(it.name)
            } ?: run { lastActiveName = ""; cycleCount = 0; continue }

            if (activeTunnel.name != lastActiveName) {
                lastActiveName = activeTunnel.name
                cycleCount = 0
                continue
            }

            val tryCount = readLatestHandshakeTry(activeTunnel.name)
            Log.d(TAG, "Handshake try=$tryCount tunnel=${activeTunnel.name}")
            if (tryCount < MIN_HANDSHAKE_TRY) continue

            val currentIdx = switchOrder.indexOf(activeTunnel.name)
            val nextIdx = (currentIdx + 1) % switchOrder.size
            if (nextIdx == 0) cycleCount++

            val maxCycles = UserKnobs.tunnelSwitchMaxCycles.first()
            if (maxCycles > 0 && cycleCount >= maxCycles) {
                Log.d(TAG, "Max cycles reached, stopping all tunnels")
                switchOrder.forEach { name ->
                    tunnels[name]?.let { runCatching { it.setStateAsync(Tunnel.State.DOWN) } }
                }
                cycleCount = 0
                lastActiveName = ""
                continue
            }

            val nextTunnel = tunnels[switchOrder[nextIdx]] ?: continue
            Log.d(TAG, "Switching ${activeTunnel.name} -> ${switchOrder[nextIdx]}")
            lastActiveName = ""
            runCatching { activeTunnel.setStateAsync(Tunnel.State.DOWN) }
            delay(TUNNEL_TRANSITION_DELAY_MS)
            runCatching { nextTunnel.setStateAsync(Tunnel.State.UP) }
        }
    }

    private suspend fun readLatestHandshakeTry(tunnelName: String): Int = withContext(Dispatchers.IO) {
        try {
            val proc = ProcessBuilder(
                "logcat", "-d", "-t", "50", "-b", "main", "-v", "brief",
                "WireGuard/GoBackend/$tunnelName:D", "*:S"
            ).redirectErrorStream(true).start()
            val lines = proc.inputStream.bufferedReader().use { it.readLines() }
            proc.waitFor()

            val lastFailIdx = lines.indexOfLast { it.contains("Handshake did not complete after") }
            if (lastFailIdx < 0) return@withContext 0

            val lastSuccessIdx = lines.indexOfLast {
                it.contains("Received handshake response") || it.contains("Receiving keepalive packet")
            }
            if (lastSuccessIdx > lastFailIdx) return@withContext 0

            val tryRegex = Regex("""\(try (\d+)\)""")
            tryRegex.find(lines[lastFailIdx])?.groupValues?.get(1)?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            0
        }
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.monitor_service_channel_name),
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.monitor_service_notification_title))
            .setSmallIcon(R.drawable.ic_monitor)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        private const val TAG = "WireGuard/PhobosMonitor"
        private const val NOTIFICATION_ID = 0x50484F42
        private const val CHANNEL_ID = "phobos_monitor"
        private const val MIN_HANDSHAKE_TRY = 2
        private const val TUNNEL_TRANSITION_DELAY_MS = 2_000L
        private const val WIFI_LOST_DEBOUNCE_MS = 2_000L

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, PhobosMonitorService::class.java)
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PhobosMonitorService::class.java))
        }
    }
}
