import 'package:flutter/material.dart';

import 'models.dart';

/// Üye simgesi. Başörtülü kız çocuğu (🧕🎀) annenin simgesinden ayrılsın diye
/// biraz küçük çizilir ve köşesine pembe fiyonk rozeti konur.
class MemberIcon extends StatelessWidget {
  final String icon;
  final double size;
  const MemberIcon(this.icon, {super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (icon != girlScarf) return Text(icon, style: TextStyle(fontSize: size));
    return SizedBox(
      width: size * 1.35,
      height: size * 1.35,
      child: Stack(clipBehavior: Clip.none, children: [
        Align(alignment: Alignment.center, child: Text('🧕', style: TextStyle(fontSize: size * 0.82))),
        Positioned(right: 0, bottom: 0, child: Text('🎀', style: TextStyle(fontSize: size * 0.48))),
      ]),
    );
  }
}
