package com.vyntra.vyntra_app_aiks

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin

class MainActivity : FlutterActivity() {
    private val methodChannelName = "vpnControl"
    private val eventChannelName = "vpnStage"
    private val notificationActionChannelName = "vyntra.vpn.actions"
    private val batteryOptimizationChannelName = "vyntra.battery.optimization"
    private val vpnStatusChannelName = "vyntra.vpn.status"

    @Volatile
    private var stageSink: EventChannel.EventSink? = null

    @Volatile
    private var lastStage: String = "disconnected"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Disable OpenVPN's built-in notification channel
        disableOpenVpnNotification()
    }

    private fun disableOpenVpnNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Try to disable OpenVPN's notification channel
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channelId = "openvpn_channel" // Common OpenVPN channel ID
                val channel = notificationManager.getNotificationChannel(channelId)
                if (channel != null) {
                    channel.setShowBadge(false)
                    channel.enableLights(false)
                    channel.enableVibration(false)
                    channel.setSound(null, null)
                    Log.d("MainActivity", "Disabled OpenVPN notification channel")
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to disable OpenVPN notification", e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Event channel to emit VPN stages
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    stageSink = events
                    // Emit the last known stage immediately
                    emitStage(lastStage)
                }

                override fun onCancel(arguments: Any?) {
                    stageSink = null
                }
            })

        // Method channel to handle control actions
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config") ?: ""
                        val username = call.argument<String>("username") ?: "vpn"
                        val password = call.argument<String>("password") ?: "vpn"
                        val country = call.argument<String>("country") ?: ""

                        Log.d("VPNControl", "Starting VPN with username=$username, country=$country")
                        
                        // Store the config for the plugin to use
                        // The plugin will handle the actual connection
                        emitStage("connecting")
                        result.success(true)
                    }
                    "stop" -> {
                        Log.d("VPNControl", "Stopping VPN")
                        emitStage("disconnected")
                        result.success(true)
                    }
                    "refresh" -> {
                        // Re-emit latest known stage
                        emitStage(lastStage)
                        result.success(null)
                    }
                    "kill_switch" -> {
                        try {
                            // Open Android VPN settings where Always-on/Block without VPN can be enabled
                            val intent = Intent("android.settings.VPN_SETTINGS").apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent("android.settings.SETTINGS").apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (e2: Exception) {
                                result.error("UNAVAILABLE", "Unable to open settings", e2.message)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Notification action channel to handle disconnect from notification
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationActionChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "disconnect" -> {
                        Log.d("VPNControl", "Disconnect requested from notification")
                        // Emit disconnected stage - the Flutter side will handle the actual disconnect
                        emitStage("disconnected")
                        result.success(true)
                    }
                    "bringToForeground" -> {
                        Log.d("VPNControl", "Bringing app to foreground")
                        bringAppToForeground()
                        result.success(true)
                    }
                    "startBackgroundService" -> {
                        startBackgroundService()
                        result.success(true)
                    }
                    "stopBackgroundService" -> {
                        stopBackgroundService()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Battery optimization channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, batteryOptimizationChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "requestBatteryOptimization" -> {
                        requestBatteryOptimizationExemption()
                        result.success(true)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        val isIgnored = isBatteryOptimizationIgnored()
                        result.success(isIgnored)
                    }
                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // VPN status channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, vpnStatusChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "isVpnConnected" -> {
                        val isConnected = isVpnConnected()
                        result.success(isConnected)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun emitStage(stage: String) {
        lastStage = stage
        try {
            stageSink?.success(stage)
        } catch (_: Exception) {
            // ignore sink errors
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true // For older versions, assume it's ignored
        }
    }

    private fun openBatteryOptimizationSettings() {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                Log.e("MainActivity", "Failed to open battery optimization settings", e2)
            }
        }
    }

    private fun startBackgroundService() {
        val intent = Intent(this, VpnBackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopBackgroundService() {
        val intent = Intent(this, VpnBackgroundService::class.java)
        stopService(intent)
    }

    private fun bringAppToForeground() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                // Add extra to indicate this was triggered from notification
                putExtra("from_notification", true)
            }
            startActivity(intent)
            Log.d("MainActivity", "App brought to foreground with cached state")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to bring app to foreground", e)
        }
    }

    private fun isVpnConnected(): Boolean {
        return try {
            Log.d("MainActivity", "Checking VPN connection status...")
            
            // Method 1: Check if VPN service is prepared (more reliable)
            val vpnService = android.net.VpnService.prepare(this)
            if (vpnService != null) {
                Log.d("MainActivity", "VPN service not prepared - not connected")
                return false
            }
            
            // Method 2: Check active network capabilities
            val connectivityManager = getSystemService(CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
            val activeNetwork = connectivityManager.activeNetwork
            val networkCapabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
            
            val hasVpnTransport = networkCapabilities?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) == true
            Log.d("MainActivity", "VPN transport detected: $hasVpnTransport")
            
            // Method 3: Check if there are any VPN interfaces
            val hasVpnInterface = try {
                val interfaces = java.net.NetworkInterface.getNetworkInterfaces()
                interfaces.asSequence().any { it.name.startsWith("tun") || it.name.startsWith("tap") }
            } catch (e: Exception) {
                false
            }
            Log.d("MainActivity", "VPN interface detected: $hasVpnInterface")
            
            val isConnected = hasVpnTransport || hasVpnInterface
            Log.d("MainActivity", "Final VPN status: $isConnected")
            return isConnected
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error checking VPN status", e)
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Handle VPN permission result
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }
}
