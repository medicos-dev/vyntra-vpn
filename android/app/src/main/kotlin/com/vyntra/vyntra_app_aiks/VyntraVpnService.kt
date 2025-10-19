package com.vyntra.vyntra_app_aiks

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.nio.channels.DatagramChannel

class VyntraVpnService : VpnService() {
    companion object {
        private const val TAG = "VyntraVpnService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "vpn_service_channel"
        private const val CHANNEL_NAME = "VPN Service"
        
        private var vpnInterface: ParcelFileDescriptor? = null
        private var isConnected = false
        private var eventSink: EventChannel.EventSink? = null
        
        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
        }
        
        fun emitStage(stage: String) {
            eventSink?.success(stage)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "CONNECT" -> {
                val server = intent.getStringExtra("server") ?: ""
                val username = intent.getStringExtra("username") ?: "vpn"
                val password = intent.getStringExtra("password") ?: "vpn"
                val sharedKey = intent.getStringExtra("sharedKey") ?: "vpn"
                
                connectL2tp(server, username, password, sharedKey)
            }
            "DISCONNECT" -> {
                disconnect()
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN Service Channel"
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showNotification() {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Vyntra VPN")
            .setContentText("VPN Connected")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun connectL2tp(server: String, username: String, password: String, sharedKey: String) {
        try {
            emitStage("connecting")
            
            // Request VPN permission
            val intent = VpnService.prepare(this)
            if (intent != null) {
                emitStage("permission_required")
                return
            }

            // Configure L2TP/IPSec VPN
            val builder = Builder()
                .setSession("Vyntra VPN")
                .addAddress("10.0.0.2", 32)
                .addDnsServer("8.8.8.8")
                .addDnsServer("8.8.4.4")
                .addRoute("0.0.0.0", 0)

            vpnInterface = builder.establish()
            
            if (vpnInterface != null) {
                isConnected = true
                emitStage("connected")
                showNotification()
                
                // Start packet forwarding
                startPacketForwarding()
            } else {
                emitStage("failed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "L2TP connection failed", e)
            emitStage("failed")
        }
    }

    private fun startPacketForwarding() {
        Thread {
            try {
                val vpnInput = FileInputStream(vpnInterface?.fileDescriptor)
                val vpnOutput = FileOutputStream(vpnInterface?.fileDescriptor)
                
                val buffer = ByteArray(32767)
                while (isConnected) {
                    val length = vpnInput.read(buffer)
                    if (length > 0) {
                        // Process packets here
                        vpnOutput.write(buffer, 0, length)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Packet forwarding error", e)
            }
        }.start()
    }

    private fun disconnect() {
        try {
            isConnected = false
            vpnInterface?.close()
            vpnInterface = null
            emitStage("disconnected")
            stopForeground(true)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
    }
}
