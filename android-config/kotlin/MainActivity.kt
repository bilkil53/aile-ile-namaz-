package com.bilkil53.aile_ile_namaz

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Android 11+ uygulamanın son kapanma sebebini (bellek, çökme, donma…) kaydeder;
/// çökme kod satırlarını (App.kt'nin yazdığı dosya) okur.
/// Uygulama bir sonraki açılışta bunları okuyup raporlar.
class MainActivity : FlutterActivity() {
    private fun crashFile() = File(filesDir, "last_crash.txt")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aile/exit").setMethodCallHandler { call, result ->
            if (call.method != "lastExit") { result.notImplemented(); return@setMethodCallHandler }
            var trace = ""
            try {
                val f = crashFile()
                if (f.exists()) { trace = f.readText(); f.delete() }
            } catch (_: Throwable) {}
            if (Build.VERSION.SDK_INT < 30) {
                result.success(if (trace.isEmpty()) null else mapOf("reason" to 4, "time" to 0L, "desc" to "", "rssKb" to 0L, "importance" to 1000, "trace" to trace))
                return@setMethodCallHandler
            }
            try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val list = am.getHistoricalProcessExitReasons(packageName, 0, 1)
                if (list.isEmpty()) result.success(null) else {
                    val e = list[0]
                    result.success(mapOf(
                        "reason" to e.reason,
                        "time" to e.timestamp,
                        "desc" to (e.description ?: ""),
                        "rssKb" to e.rss,
                        "importance" to e.importance,
                        "trace" to trace,
                    ))
                }
            } catch (t: Throwable) { result.success(null) }
        }
    }
}
