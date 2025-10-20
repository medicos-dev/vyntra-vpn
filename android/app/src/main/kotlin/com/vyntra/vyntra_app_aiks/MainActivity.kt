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
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin

class MainActivity : FlutterActivity() {
    private val methodChannelName = "vpnControl"
    private val eventChannelName = "vpnStage"
    private val notificationActionChannelName = "vyntra.vpn.actions"

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
                        emitStage("disconnected")
                        result.success(true)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Handle VPN permission result
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }
}
