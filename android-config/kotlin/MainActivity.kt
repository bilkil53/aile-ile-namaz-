package com.bilkil53.aile_ile_namaz

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/// Android 11+ uygulamanın son kapanma sebebini (bellek, çökme, donma…) kaydeder;
/// çökme kod satırlarını (App.kt'nin yazdığı dosya) okur.
/// Uygulama bir sonraki açılışta bunları okuyup raporlar.
class MainActivity : FlutterActivity() {
    private fun crashFile() = File(filesDir, "last_crash.txt")

    /// Uygulamayı imzalayan sertifikaların SHA-256 parmak izleri (küçük harf, iki nokta yok, virgülle).
    /// keytool'un verdiği SHA256 ile aynıdır. İmza geçmişindeki (anahtar yenileme) bütün sertifikalar
    /// döner: anahtar ileride yenilenirse kontrol herkesi kilitlemesin. Yeniden imzalanmış bir kopyanın
    /// geçmişinde bizim anahtarımız olmaz.
    private fun signatureSha256(): String? {
        return try {
            val pm = packageManager
            val certs = if (Build.VERSION.SDK_INT >= 28) {
                val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                val s = info.signingInfo ?: return null
                if (s.hasMultipleSigners()) s.apkContentsSigners else s.signingCertificateHistory
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
            } ?: return null
            if (certs.isEmpty()) return null
            certs.joinToString(",") { c ->
                MessageDigest.getInstance("SHA-256").digest(c.toByteArray()).joinToString("") { "%02x".format(it) }
            }
        } catch (t: Throwable) { null }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aile/exit").setMethodCallHandler { call, result ->
            if (call.method == "signatureSha256") { result.success(signatureSha256()); return@setMethodCallHandler }
            // Pil tasarrufu muafiyeti: Android uygulamayı uyutmuyor mu?
            if (call.method == "batteryIgnored") {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName)); return@setMethodCallHandler
            }
            // Pil optimizasyonu listesi (izin istemeden ayar sayfası; Play kuralına uygun)
            if (call.method == "openBatterySettings") {
                try {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: Throwable) {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Throwable) {}
                }
                result.success(true); return@setMethodCallHandler
            }
            if (call.method == "openNotificationSettings") {
                try {
                    startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: Throwable) {}
                result.success(true); return@setMethodCallHandler
            }
            if (call.method == "installApk") {
                // Güncelleme: kurulum ekranı ayrı görevde açılır, uygulamanın eski penceresi
                // son kullanılanlardan kaldırılır. Böylece kurulum sonrası "Aç" denince tek kopya kalır.
                try {
                    val f = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(this, "$packageName.aileupdate", f)
                    val i = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(i)
                    result.success(true)
                    Handler(Looper.getMainLooper()).postDelayed({ finishAndRemoveTask() }, 700)
                } catch (t: Throwable) { result.success(false) }
                return@setMethodCallHandler
            }
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
