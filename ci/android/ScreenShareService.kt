// ============================================================
// ci/android/ScreenShareService.kt
// Şablon dosyası. Workflow bunu okuyup package satırını
// gettic.by.darking053 olarak değiştirir ve
// android/app/src/main/kotlin/gettic/by/darking053/ altına yazar.
//
// Ekran paylaşımı sırasında Android'in istediği foreground service.
// Android 10+ (API 29) mediaProjection türünü, Android 14 de bunun
// çalışırken başlatılmasını zorunlu kılar.
// ============================================================
package gettic.by.darking053

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ScreenShareService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Ekran paylaşımı", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Gettic Meet")
            .setContentText("Ekranınız paylaşılıyor")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        @Suppress("DEPRECATION")
        stopForeground(true)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "gettic_screen_share"
        private const val NOTIFICATION_ID = 4711
    }
}
