import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'prayer_times.dart';
import 'settings.dart';

/// Konum GPS ile otomatik bulunur.
/// Konum sadece cihazda tutulur, sunucuya gönderilmez.
class LocationHelper {
  /// Konum değişince artar; ekranlar dinleyip vakitleri yeniler.
  static final version = ValueNotifier<int>(0);

  static bool _running = false;

  /// Açılışta çağrılır. Son güncellemeden bu yana [maxAge] geçtiyse sessizce yeniler.
  /// Uygulama her açıldığında konumu otomatik alır. Alınamazsa 10 saniye sonra tekrar dener
  /// (en fazla 3 deneme). İzin verilmemişse ya da konum servisi kapalıysa tekrar denemez.
  static Future<void> autoUpdate({Duration maxAge = Duration.zero}) async {
    final last = AppSettings.prefs.getInt('locationUpdatedAt') ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    if (maxAge > Duration.zero && AppSettings.locationFromGps && age < maxAge.inMilliseconds) return;
    for (var attempt = 1; attempt <= 3; attempt++) {
      final (ok, msg) = await updateFromGps();
      if (ok || permissionDenied || msg.contains('servisi kapalı')) return;
      if (attempt < 3) await Future<void>.delayed(const Duration(seconds: 10));
    }
  }

  /// (başarılı mı, konum adı veya hata mesajı)
  static Future<(bool, String)> updateFromGps() async {
    if (_running) return (false, 'Konum zaten alınıyor…');
    _running = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (false, 'Telefonun konum servisi kapalı.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        await AppSettings.prefs.setBool('locationDenied', true);
        return (false, 'Konum izni verilmedi.');
      }
      await AppSettings.prefs.setBool('locationDenied', false);

      // Önce son bilinen konum (anında), sonra güncel konum
      Position? pos = await Geolocator.getLastKnownPosition();
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        if (pos == null) rethrow;
      }

      final p = pos;
      final name = await _placeName(p.latitude, p.longitude);
      await AppSettings.setLocation(name, p.latitude, p.longitude, gps: true);
      await AppSettings.prefs.setInt('locationUpdatedAt', DateTime.now().millisecondsSinceEpoch);
      version.value++;
      return (true, name);
    } catch (_) {
      return (false, 'Konum alınamadı.');
    } finally {
      _running = false;
    }
  }

  static bool get permissionDenied => AppSettings.prefs.getBool('locationDenied') ?? false;

  static Future<void> openSettings() => Geolocator.openAppSettings();

  /// "İlçe, İl" (telefonun adres servisi); olmazsa en yakın il.
  static Future<String> _placeName(double lat, double lng) async {
    try {
      await setLocaleIdentifier('tr_TR');
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isNotEmpty) {
        final m = marks.first;
        final ilce = (m.subAdministrativeArea ?? '').trim();
        final il = (m.administrativeArea ?? '').trim();
        if (ilce.isNotEmpty && il.isNotEmpty && ilce != il) return '$ilce, $il';
        if (il.isNotEmpty) return il;
      }
    } catch (_) {}
    return nearestCity(lat, lng).name;
  }
}
