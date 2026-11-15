// ============================================================
// ci/android/MainActivity.kt
// Şablon dosyası. Workflow bunu okuyup package satırını
// gettic.by.darking053 olarak değiştirir ve
// android/app/src/main/kotlin/gettic/by/darking053/ altına yazar.
//
// Flutter tarafından "gettic/screen_share" kanalı üzerinden
// "start" / "stop" komutlarını alır ve ScreenShareService'i
// başlatır / durdurur.
// ============================================================
package gettic.by.darking053

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
