package com.vyntra.vyntra_app_aiks

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.vyntra.vyntra_app_aiks/vpn_control"
    private val eventChannelName = "com.vyntra.vyntra_app_aiks/vpn_stage"

    @Volatile
    private var stageSink: EventChannel.EventSink? = null

    @Volatile
    private var lastStage: String = "disconnected"

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
                    "initialize" -> {
                        Log.d("VPNControl", "Initializing VPN service")
                        result.success(true)
                    }
                    "connect" -> {
                        val server = call.argument<String>("server") ?: ""
                        val username = call.argument<String>("username") ?: "vpn"
                        val password = call.argument<String>("password") ?: "vpn"
                        val sharedKey = call.argument<String>("sharedKey") ?: "vpn"
                        val country = call.argument<String>("country") ?: ""

                        Log.d("VPNControl", "Connecting to L2TP server: $server")
                        
                        // Start VPN service
                        val intent = Intent(this, VyntraVpnService::class.java).apply {
                            action = "CONNECT"
                            putExtra("server", server)
                            putExtra("username", username)
                            putExtra("password", password)
                            putExtra("sharedKey", sharedKey)
                            putExtra("country", country)
                        }
                        startService(intent)
                        
                        emitStage("connecting")
                        result.success(true)
                    }
                    "disconnect" -> {
                        Log.d("VPNControl", "Disconnecting VPN")
                        val intent = Intent(this, VyntraVpnService::class.java).apply {
                            action = "DISCONNECT"
                        }
                        startService(intent)
                        emitStage("disconnected")
                        result.success(true)
                    }
                    "connectProxy" -> {
                        // Fallback to HTTP proxy
                        val server = call.argument<String>("server") ?: "127.0.0.1"
                        val port = call.argument<Int>("port") ?: 8080
                        Log.d("VPNControl", "Connecting to proxy: $server:$port")
                        
                        // Implement proxy connection here
                        emitStage("connecting")
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
    }

    private fun emitStage(stage: String) {
        lastStage = stage
        try {
            stageSink?.success(stage)
        } catch (_: Exception) {
            // ignore sink errors
        }
    }
}
