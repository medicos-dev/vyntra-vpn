package com.vyntra.vyntra_app_aiks

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class VpnBackgroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private val notificationId = 1001
    private val channelId = "vpn_background_service"

    override fun onCreate() {
        super.onCreate()
        Log.d("VpnBackgroundService", "Service created")
        
        // Create notification channel
        createNotificationChannel()
        
        // Acquire wake lock to keep the service running
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "VyntraVPN::VpnBackgroundService"
        )
        wakeLock?.acquire(10*60*1000L /*10 minutes*/)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("VpnBackgroundService", "Service started")
        
        // Start as foreground service
        val notification = createNotification()
        startForeground(notificationId, notification)
        
        return START_STICKY // Restart if killed
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("VpnBackgroundService", "Service destroyed")
        wakeLock?.release()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "VPN Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps VPN connection active in background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Vyntra VPN")
            .setContentText("VPN connection active")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Use default Android icon
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
}
