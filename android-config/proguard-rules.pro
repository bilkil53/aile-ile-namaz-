# Zamanlanmış bildirimler (vakit hatırlatması, 12:00 günün sözü):
# flutter_local_notifications kayıtlı bildirimleri Gson ile okur. R8 kod küçültmesi
# genel tip bilgisini (Signature) silerse bildirim zamanı geldiğinde alıcı çöker
# ("Missing type parameter") ve bildirim hiç görünmez. Bu kurallar bunu önler.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod,InnerClasses
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.** { *; }
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
# Uygulamanın kendi çökme kaydedicisi
-keep class com.bilkil53.aile_ile_namaz.** { *; }
