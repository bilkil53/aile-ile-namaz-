import 'package:geolocator/geolocator.dart';

import 'prayer_times.dart';
import 'settings.dart';

/// GPS ile konumu bulur ve en yakın ili kaydeder. Konum sadece cihazda tutulur.
class LocationHelper {
  /// Başarılıysa bulunan il adını, değilse hata mesajını döner.
  static Future<(bool, String)> updateFromGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return (false, 'Telefonun konum servisi kapalı.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return (false, 'Konum izni verilmedi. İli listeden seçebilirsin.');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    final city = nearestCity(pos.latitude, pos.longitude);
    await AppSettings.setLocation(city.name, pos.latitude, pos.longitude, gps: true);
    return (true, city.name);
  }
}
