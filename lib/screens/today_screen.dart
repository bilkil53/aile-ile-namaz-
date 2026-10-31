import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../content/daily_content.dart';
import '../data.dart';
import '../location.dart';
import '../models.dart';
import '../notifications.dart';
import '../prayer_times.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/prayer_icon.dart';
import '../widgets/qibla_card.dart';

/// "Bugün" sekmesi: karşılama, SIRADAKİ VAKİT, günün ayeti, vakit kartları, kıble.
/// Vakte dokundukça Kıldı → Kılmadı → Muaf → Bekliyor sırasıyla ilerler.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Map<String, PrayerStatus> _today = {};
  Map<String, PrayerStatus> _yesterday = {};
  bool _showYesterday = false;
  DayTimes? _times;
  DayTimes? _tomorrow;
  String _name = '';
  bool _loading = true;
  bool _gpsBusy = false;
  Timer? _ticker;

  void _onLocation() => _load();

  @override
  void initState() {
    super.initState();
    LocationHelper.version.addListener(_onLocation);
    _load();
    // Geri sayım için dakikada bir yenile (saniyelik yenileme pil harcar).
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Gün değiştiyse her şeyi yeniden yükle
      if (_times != null && !_isSameDay(_times!.date, DateTime.now())) {
        _load();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    LocationHelper.version.removeListener(_onLocation);
    _ticker?.cancel();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _yesterdayStr() =>
      DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

  Future<void> _load() async {
    final now = DateTime.now();
    // Vakitler (önbellekten anında gelir) ve sunucu verisi paralel
    final timesF = Future.wait([
      PrayerTimesService.forDate(now),
      PrayerTimesService.forDate(now.add(const Duration(days: 1))),
    ]);
    try {
      final results = await Future.wait<dynamic>([
        Repo.dayPrayers([myId], todayStr()),
        Repo.dayPrayers([myId], _yesterdayStr()),
        Repo.myDisplayName(),
      ]);
      _today = (results[0] as Map<String, Map<String, PrayerStatus>>)[myId] ?? {};
      _yesterday = (results[1] as Map<String, Map<String, PrayerStatus>>)[myId] ?? {};
      _name = results[2] as String;
    } catch (_) {
      // Çevrimdışı: vakitler yine gösterilir
    }
    final times = await timesF;
    if (!mounted) return;
    setState(() {
      _times = times[0];
      _tomorrow = times[1];
      _loading = false;
    });
  }

  Future<void> _updateGps() async {
    setState(() => _gpsBusy = true);
    try {
      final (ok, msg) = await LocationHelper.updateFromGps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Konum güncellendi: $msg' : msg)),
      );
      if (ok) {
        await _load();
        unawaited(Notifications.reschedule());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum alınamadı. İli Ayarlar\'dan seçebilirsin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  PrayerStatus _next(PrayerStatus s) => switch (s) {
        PrayerStatus.none => PrayerStatus.prayed,
        PrayerStatus.prayed => PrayerStatus.missed,
        PrayerStatus.missed => PrayerStatus.excused,
        PrayerStatus.excused => PrayerStatus.none,
      };

  Map<String, PrayerStatus> get _current => _showYesterday ? _yesterday : _today;

  Future<void> _toggle(String key) async {
    final map = _current;
    final next = _next(map[key] ?? PrayerStatus.none);
    final before = Map<String, PrayerStatus>.from(map);
    final updated = {...map, key: next};
    setState(() {
      if (_showYesterday) {
        _yesterday = updated;
      } else {
        _today = updated;
      }
    });
    try {
      final synced = await Repo.setPrayer(
        key: key,
        status: next,
        date: _showYesterday ? _yesterdayStr() : null,
      );
      if (!synced && !isGuest && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('📱 Telefona kaydedildi. İnternet gelince otomatik buluta gönderilecek.'),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_showYesterday) {
          _yesterday = before;
        } else {
          _today = before;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi. İnternet bağlantını kontrol et.')),
      );
    }
  }

  /// Cuma günü öğle kartı "Cuma Namazı 🕌" olarak görünür (eski uygulamadaki gibi).
  String _prayerName(String key) =>
      key == 'dhuhr' && !_showYesterday && DateTime.now().weekday == DateTime.friday
          ? 'Cuma Namazı 🕌'
          : prayerLabels[key]!;

  bool _arrived(String key) {
    if (_showYesterday) return true;
    // Vakitler henüz yüklenmediyse işaretlemeye izin verme (gelecek vakit yanlışlıkla işaretlenmesin).
    if (_times == null) return false;
    return !_times!.at(_times!.timeFor(key)).isAfter(DateTime.now());
  }

  int get _prayedCount => prayerKeys.where((k) => _current[k] == PrayerStatus.prayed).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _greeting(),
          if (LocationHelper.permissionDenied) ...[
            const SizedBox(height: 10),
            _locationBanner(),
          ],
          const SizedBox(height: 10),
          _dayToggle(),
          const SizedBox(height: 12),
          if (!_showYesterday) ...[
            _heroCard(),
            const SizedBox(height: 12),
            _quoteCard(),
            const SizedBox(height: 16),
          ] else ...[
            _yesterdayInfo(),
            const SizedBox(height: 12),
          ],
          _trackingHeader(),
          const SizedBox(height: 12),
          for (final k in prayerKeys) ...[
            _prayerCard(k),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          if (!_showYesterday) const QiblaCard(),
        ],
      ),
    );
  }

  Widget _greeting() {
    final date = DateFormat('d MMMM y, EEEE', 'tr').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AİLE İLE NAMAZ',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.emerald, letterSpacing: 0.8),
              ),
              Text(
                _name.isEmpty ? 'Selamün aleyküm' : 'Selamün aleyküm,\n$_name',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary, height: 1.25),
              ),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$date · ${_gpsBusy ? 'GPS güncelleniyor…' : AppSettings.cityName}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ]),
            ],
          ),
        ),
        Material(
          color: AppColors.emeraldContainer,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _gpsBusy ? null : _updateGps,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.my_location, size: 20, color: AppColors.emerald),
            ),
          ),
        ),
      ],
    );
  }

  Widget _locationBanner() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.location_off, size: 18, color: Color(0xFF78350F)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Doğru vakitler için konum izni ver. Şu an İstanbul vakitleri gösteriliyor.',
                style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
          ),
          TextButton(
            onPressed: () async {
              await LocationHelper.openSettings();
            },
            child: const Text('İzin ver'),
          ),
        ]),
      );

  Widget _dayToggle() {
    Widget seg(String label, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.emerald : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.emeraldContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        seg('← Dün', _showYesterday, () => setState(() => _showYesterday = true)),
        seg('Bugün', !_showYesterday, () => setState(() => _showYesterday = false)),
      ]),
    );
  }

  Widget _yesterdayInfo() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.goldContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Dünkü namazlarını görüntülüyorsun. Unuttuğun veya kıldığın vakitleri işaretleyebilirsin.',
          style: TextStyle(fontSize: 12, color: Color(0xFF78350F)),
        ),
      );

  Widget _heroCard() {
    final t = _times!;
    final n = PrayerTimesService.next(t, _tomorrow ?? t);
    final mins = n.remaining.inMinutes;
    final h = mins ~/ 60, m = mins % 60;
    final white85 = Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.emerald,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.notifications, size: 14, color: Colors.white),
            SizedBox(width: 5),
            Text('SIRADAKİ VAKİT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(h > 0 ? '$h sa $m dk sonra' : '$m dk sonra',
                        style: TextStyle(fontSize: 13, color: white85, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Text(n.time, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          // Günün tüm vakitleri
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (name, time) in t.all)
                Column(children: [
                  Text(name, style: TextStyle(fontSize: 10, color: white85)),
                  const SizedBox(height: 2),
                  Text(time,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: name == n.name ? AppColors.prayedMint : Colors.white,
                      )),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 10),
          Text(
            t.fromDiyanet
                ? 'Diyanet İşleri Başkanlığı hesaplama yöntemiyle ${AppSettings.cityName} vakitleri.'
                : 'İnternet yok: vakitler cihazda yaklaşık hesaplandı.',
            style: TextStyle(fontSize: 11, color: white85, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _quoteCard() {
    final q = dailyQuotes()[0];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.category.toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.emerald, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          if (q.arabic != null) ...[
            Text(q.arabic!,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 18, color: AppColors.textPrimary, height: 1.6)),
            const SizedBox(height: 6),
          ],
          Text(q.text, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4)),
          const SizedBox(height: 6),
          Text(q.source, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _trackingHeader() {
    final map = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_showYesterday ? 'Dünün takibi' : 'Bugünün takibi',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('$_prayedCount/5',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.emerald)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text('Niyetinle başla; küçük bir işaret sürdürülebilirliği güçlendirir.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < prayerKeys.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: map[prayerKeys[i]] == PrayerStatus.prayed ? AppColors.emerald : AppColors.segmentInactive,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        const Text('Vakite dokundukça Kıldı → Kılmadı → Muaf → Bekliyor sırasıyla ilerler.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _prayerCard(String key) {
    final status = _current[key] ?? PrayerStatus.none;
    final arrived = _arrived(key);
    final time = _times?.timeFor(key) ?? '';
    final (statusText, statusColor) = !arrived
        ? ('Vakti henüz girmedi', Colors.white.withValues(alpha: 0.65))
        : switch (status) {
            PrayerStatus.prayed => ('✓ Kılındı', AppColors.prayedMint),
            PrayerStatus.missed => ('✕ Kılınmadı', AppColors.missedCoral),
            PrayerStatus.excused => ('— Muaf', const Color(0xFFE5E7EB)),
            PrayerStatus.none => ('Dokunarak işaretle', Colors.white.withValues(alpha: 0.75)),
          };
    return Material(
      color: arrived ? AppColors.emerald : AppColors.emerald.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (arrived) {
            _toggle(key);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${_prayerName(key)} vakti $time\'de girecek.')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: arrived ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: PrayerIcon(key, size: 20, color: Colors.white.withValues(alpha: 0.92)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_prayerName(key),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text(statusText,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: arrived && status != PrayerStatus.none ? FontWeight.bold : FontWeight.normal,
                        )),
                  ],
                ),
              ),
              if (time.isNotEmpty && !_showYesterday) ...[
                Text(time, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 12),
              ],
              arrived ? _statusCircle(status) : _lockCircle(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lockCircle() => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: Icon(Icons.lock, size: 13, color: Colors.white.withValues(alpha: 0.8)),
      );

  Widget _statusCircle(PrayerStatus status) {
    const size = 26.0;
    return switch (status) {
      PrayerStatus.prayed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 16, color: AppColors.emerald),
        ),
      PrayerStatus.missed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.missed, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 15, color: Colors.white),
        ),
      PrayerStatus.excused => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), shape: BoxShape.circle),
          child: const Icon(Icons.remove, size: 15, color: Colors.white),
        ),
      PrayerStatus.none => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.8),
          ),
        ),
    };
  }
}
