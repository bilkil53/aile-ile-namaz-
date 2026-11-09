import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../lang.dart';
import '../prayer_times.dart';
import '../settings.dart';
import '../theme.dart';

/// Kıble pusulası: ivme + manyetik sensörden telefonun yönünü hesaplar.
/// Sensörler sadece kart açıkken dinlenir (pil dostu).
class QiblaCard extends StatefulWidget {
  const QiblaCard({super.key});

  @override
  State<QiblaCard> createState() => _QiblaCardState();
}

class _QiblaCardState extends State<QiblaCard> {
  bool _open = false;
  double? _heading; // telefonun baktığı yön (derece)
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  List<double> _g = [0, 0, 9.8];
  List<double>? _m;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
      // alçak geçiren filtre
      _g = [_g[0] * 0.8 + e.x * 0.2, _g[1] * 0.8 + e.y * 0.2, _g[2] * 0.8 + e.z * 0.2];
    });
    _magSub = magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
      final m = _m;
      _m = m == null ? [e.x, e.y, e.z] : [m[0] * 0.8 + e.x * 0.2, m[1] * 0.8 + e.y * 0.2, m[2] * 0.8 + e.z * 0.2];
      final h = _azimuth(_g, _m!);
      if (h != null && mounted) setState(() => _heading = h);
    });
  }

  void _stop() {
    _accSub?.cancel();
    _magSub?.cancel();
    _accSub = null;
    _magSub = null;
  }

  /// Android SensorManager.getRotationMatrix + getOrientation ile aynı hesap.
  double? _azimuth(List<double> g, List<double> m) {
    var ax = g[0], ay = g[1], az = g[2];
    final ex = m[0], ey = m[1], ez = m[2];
    var hx = ey * az - ez * ay;
    var hy = ez * ax - ex * az;
    var hz = ex * ay - ey * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return null;
    hx /= normH;
    hy /= normH;
    hz /= normH;
    final invA = 1 / math.sqrt(ax * ax + ay * ay + az * az);
    ax *= invA;
    ay *= invA;
    az *= invA;
    final my = az * hx - ax * hz;
    final deg = math.atan2(hy, my) * 180 / math.pi;
    return (deg + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final qibla = PrayerTimesService.qiblaBearing(AppSettings.lat, AppSettings.lng);
    final heading = _heading;
    final diff = heading == null ? null : ((qibla - heading + 540) % 360) - 180;
    final aligned = diff != null && diff.abs() < 5;

    // Material: ListTile dokunma efekti kartın üstünde görünsün (Container arka planı onu gizliyordu)
    return Material(
      color: AppColors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.explore, color: AppColors.emerald),
            title: Text(t('Kıble Pusulası', 'Qibla Compass'), style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(t('${AppSettings.cityName} için kıble: ${qibla.toStringAsFixed(0)}°', 'Qibla for ${AppSettings.cityName}: ${qibla.toStringAsFixed(0)}°')),
            trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() => _open = !_open);
              _open ? _start() : _stop();
            },
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: heading == null
                        ? Center(child: Text(t('Sensör bekleniyor…', 'Waiting for sensor…')))
                        : Transform.rotate(
                            angle: -heading * math.pi / 180,
                            child: CustomPaint(painter: _CompassPainter(qibla, aligned)),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    heading == null
                        ? t('Telefonu düz tut.', 'Hold the phone flat.')
                        : aligned
                            ? t('Kıbleye dönüksün ✓', 'You are facing the qibla ✓')
                            : (diff! > 0 ? t('Sağa dön (${diff.abs().toStringAsFixed(0)}°)', 'Turn right (${diff.abs().toStringAsFixed(0)}°)') : t('Sola dön (${diff.abs().toStringAsFixed(0)}°)', 'Turn left (${diff.abs().toStringAsFixed(0)}°)')),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: aligned ? AppColors.emerald : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('Telefonu yere paralel tut, metal ve mıknatıslardan uzak dur.', 'Hold the phone parallel to the ground, away from metal and magnets.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double qibla;
  final bool aligned;
  _CompassPainter(this.qibla, this.aligned);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = AppColors.emeraldContainer);
    canvas.drawCircle(
        c, r, Paint()..color = AppColors.emerald..style = PaintingStyle.stroke..strokeWidth = 2);
    // Kuzey işareti
    final tp = TextPainter(
      text: const TextSpan(text: 'K', style: TextStyle(color: AppColors.missed, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - r + 4));
    // Kıble oku
    final a = qibla * math.pi / 180;
    final tip = Offset(c.dx + (r - 18) * math.sin(a), c.dy - (r - 18) * math.cos(a));
    canvas.drawLine(
        c,
        tip,
        Paint()
          ..color = aligned ? AppColors.emerald : AppColors.gold
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    final kaaba = TextPainter(text: const TextSpan(text: '🕋', style: TextStyle(fontSize: 22)), textDirection: TextDirection.ltr)
      ..layout();
    kaaba.paint(canvas, tip - Offset(kaaba.width / 2, kaaba.height / 2));
    canvas.drawCircle(c, 5, Paint()..color = AppColors.emerald);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.qibla != qibla || old.aligned != aligned;
}
