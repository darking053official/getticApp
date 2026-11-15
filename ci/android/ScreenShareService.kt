// ============================================================
// android/app/src/main/kotlin/<paket>/MainActivity.kt
// (.txt olarak verildi. Mevcut MainActivity'niz varsa bu sınıfı
//  onunla birleştirin: configureFlutterEngine içindeki kanal kaydı yeterli.)
// ============================================================
package com.gettic.gettic

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val screenShareChannel = "gettic/screen_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenShareChannel)
            .setMethodCallHandler { call, result ->
                val intent = Intent(this, ScreenShareService::class.java)
                when (call.method) {
                    "start" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
