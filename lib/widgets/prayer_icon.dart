import 'package:flutter/material.dart';

/// İnce çizgili (outlined) vakit simgeleri.
const prayerIcons = <String, IconData>{
  'fajr': Icons.wb_twilight,
  'dhuhr': Icons.wb_sunny_outlined,
  'asr': Icons.brightness_5_outlined,
  'maghrib': Icons.nights_stay_outlined,
  'isha': Icons.bedtime_outlined,
  'witr': Icons.star_outline_rounded,
};

/// Yumuşak daire içinde vakit simgesi.
class PrayerIcon extends StatelessWidget {
  final String prayer;
  final double size;
  final Color color;
  final Color? background;
  const PrayerIcon(this.prayer, {super.key, this.size = 20, required this.color, this.background});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(prayerIcons[prayer.toLowerCase()] ?? Icons.mosque_outlined, size: size, color: color);
    if (background == null) return icon;
    return Container(
      width: size * 1.9,
      height: size * 1.9,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: icon,
    );
  }
}
