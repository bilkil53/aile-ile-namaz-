import 'package:flutter/material.dart';

import '../theme.dart';

/// Geri alınamayan işlemler (sıfırla, sil, kapat, ayrıl) için kırmızı çerçeveli kutu.
/// Yanlışlıkla dokunulmasın diye tek satır yazı yerine belirgin, ayrı bir alan olarak gösterilir.
class DangerBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const DangerBox({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.delete_forever,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.missed.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Icon(icon, color: AppColors.missed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, color: AppColors.missed, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.missed),
          ]),
        ),
      ),
    );
  }
}
