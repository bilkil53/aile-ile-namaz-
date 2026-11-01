package com.bilkil53.aile_ile_namaz

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/// Android 11+ uygulamanın son kapanma sebebini (bellek, çökme, donma…) kaydeder;
/// ayrıca Java/Kotlin tarafındaki çökmenin kod satırlarını dosyaya yazar.
/// Uygulama bir sonraki açılışta bunları okuyup raporlar.
class MainActivity : FlutterActivity() {
    companion object {
        @Volatile private var installed = false
    }

    private fun crashFile() = File(filesDir, "last_crash.txt")

    private fun installCrashWriter() {
        if (installed) return
        installed = true
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        val file = crashFile()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                val txt = "thread=${t.name}\n$sw"
                file.writeText(if (txt.length > 7000) txt.substring(0, 7000) else txt)
            } catch (_: Throwable) {}
            prev?.uncaughtException(t, e)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        installCrashWriter()
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
