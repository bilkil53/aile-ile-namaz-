package com.bilkil53.aile_ile_namaz

import android.app.Application
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/// Uygulama süreci başlar başlamaz (ekran açılmadan, ör. bildirim zamanı gelince de)
/// çökme kaydediciyi kurar: çökmenin kod satırlarını last_crash.txt dosyasına yazar.
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        val file = File(filesDir, "last_crash.txt")
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
}
