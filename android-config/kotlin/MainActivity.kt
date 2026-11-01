package com.bilkil53.aile_ile_namaz

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Android 11+ uygulamanın son kapanma sebebini (bellek, çökme, donma…) kaydeder;
/// uygulama bir sonraki açılışta bunu okuyup kullanıcıya gösterir.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aile/exit").setMethodCallHandler { call, result ->
            if (call.method != "lastExit") { result.notImplemented(); return@setMethodCallHandler }
            if (Build.VERSION.SDK_INT < 30) { result.success(null); return@setMethodCallHandler }
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
                    ))
                }
            } catch (t: Throwable) { result.success(null) }
        }
    }
}
