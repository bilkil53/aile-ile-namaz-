enum PrayerStatus { none, prayed, missed, excused }

extension PrayerStatusX on PrayerStatus {
  String get code => switch (this) {
        PrayerStatus.none => 'NONE',
        PrayerStatus.prayed => 'PRAYED',
        PrayerStatus.missed => 'MISSED',
        PrayerStatus.excused => 'EXCUSED',
      };

  String get label => switch (this) {
        PrayerStatus.none => 'Belirtilmedi',
        PrayerStatus.prayed => 'Kıldı',
        PrayerStatus.missed => 'Kılmadı',
        PrayerStatus.excused => 'Muaf',
      };

  String get emoji => switch (this) {
        PrayerStatus.none => '⏳',
        PrayerStatus.prayed => '✅',
        PrayerStatus.missed => '❌',
        PrayerStatus.excused => '➖',
      };

  static PrayerStatus parse(String? s) => switch (s) {
        'PRAYED' => PrayerStatus.prayed,
        'MISSED' => PrayerStatus.missed,
        'EXCUSED' => PrayerStatus.excused,
        _ => PrayerStatus.none,
      };
}

/// Veritabanındaki sütun adları (daily_prayers).
const prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

const prayerLabels = {
  'fajr': 'Sabah',
  'dhuhr': 'Öğle',
  'asr': 'İkindi',
  'maghrib': 'Akşam',
  'isha': 'Yatsı',
  'witr': 'Vitir',
};

/// Vakit emojileri (sadece bildirim metinlerinde; ekranda widgets/prayer_icon.dart kullanılır).
const prayerEmoji = {
  'fajr': '🌅',
  'dhuhr': '☀️',
  'asr': '⛅',
  'maghrib': '🌇',
  'isha': '🌌',
};

/// Vakit açıklamaları (eski Karne ekranından).
const prayerSubtitles = {
  'fajr': 'Güneş doğmadan önceki vaktin bereketi',
  'dhuhr': 'Günün ortasındaki manevi mola',
  'asr': 'Günün en kıymetli secde vakti',
  'maghrib': 'Günün batışıyla ifa edilen şükür',
  'isha': 'Günün son huzur secdesi',
};

/// Reisin kendi unvanı (katılım onayında seçer).
const ownerTitles = {'Aile Reisi': '🏡', 'Baba': '🧔', 'Anne': '🧕'};

/// Unvanlar Aile Reisine göredir (reisin eşi, oğlu, kızı…). Reisin unvanı sabit: "Aile Reisi".
const reisTitles = {
  'Eşi': '🧕',
  'Oğlu': '👦',
  'Kızı': '🧕🏻',
  'Annesi': '🧕🏽',
  'Babası': '🧔',
  'Kardeşi': '🧒',
  'Torunu': '👶',
  'Gelini': '🧕🏼',
  'Damadı': '👨',
  'Dedesi': '👴',
  'Ninesi': '🧕🏾',
  'Aile Ferdi': '👥',
};

/// Erkek ünvan/simgeler: bu kişilerde "Muaf" seçeneği gösterilmez (Aile Reisi erkek kabul edilir).
const femaleTitles = {'Anne', 'Kızı', 'Annesi', 'Ninesi', 'Gelini'};
const maleTitles = {'Aile Reisi', 'Baba', 'Oğlu', 'Babası', 'Dedesi', 'Damadı'};
const maleIcons = {'🧔', '👨', '👴', '👱‍♂️', '👦', '🏡'};
const femaleIcons = {'🧕', '🧕🏻', '🧕🏼', '🧕🏽', '🧕🏾', '🧕🏿', '👩', '👵', '👱‍♀️', '👧'};

/// Muaf seçeneği bu kişi için geçerli mi? Bilinmiyorsa (bireysel mod) gösterilir.
bool canBeExcused(String role, String icon, [String? gender]) {
  if (gender != null) return gender == 'f';
  if (femaleIcons.contains(icon) || role == 'Anne') return true;
  if (maleTitles.contains(role) || maleIcons.contains(icon)) return false;
  return true;
}

/// Reisin gözünden sahiplik eki: "Kızı" → "Kızın", "Eşi" → "Eşin" …
const _possessive = {
  'Eşi': 'Eşin',
  'Oğlu': 'Oğlun',
  'Kızı': 'Kızın',
  'Annesi': 'Annen',
  'Babası': 'Baban',
  'Kardeşi': 'Kardeşin',
  'Torunu': 'Torunun',
  'Gelini': 'Gelinin',
  'Damadı': 'Damadın',
  'Dedesi': 'Deden',
  'Ninesi': 'Ninen',
};

/// Aile Reisi bakıyorsa ünvan "senin …" biçiminde (Kızın, Oğlun) gösterilir;
/// diğer üyeler ünvanı reise göre (Kızı, Oğlu) görür. Veritabanında hep reise göre saklanır.
String titleFor(String role, {required bool viewerIsReis}) => viewerIsReis ? (_possessive[role] ?? role) : role;

/// Reisin seçebileceği simgeler (eski uygulamadaki gruplar).
const iconGroups = <String, List<String>>{
  'Başörtülü': ['🧕', '🧕🏻', '🧕🏼', '🧕🏽', '🧕🏾', '🧕🏿'],
  'Kadın / Anne / Eş': ['👩', '👵', '👱‍♀️', '👧'],
  'Erkek / Baba / Eş': ['🧔', '👨', '👴', '👱‍♂️'],
  'Çocuk & Bebek': ['👦', '👧', '🧒', '👶'],
  'Diğer': ['🏡', '👤', '👥', '🌟', '🕌'],
};

class Pool {
  final String id;
  final String name;
  final String ownerId;
  final String inviteCode;

  Pool({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.inviteCode,
  });

  factory Pool.fromMap(Map<String, dynamic> m) => Pool(
        id: m['id'] as String,
        name: m['name'] as String,
        ownerId: m['owner_id'] as String,
        inviteCode: m['invite_code'] as String,
      );

  /// EMB-123456 biçiminde gösterim.
  String get displayCode => inviteCode.startsWith('EMB') && inviteCode.length > 3
      ? 'EMB-${inviteCode.substring(3)}'
      : inviteCode;
}

class Member {
  final String userId;
  final String name;
  final String roleTitle;
  final String icon;

  /// 'm' / 'f' / null — Aile Reisi verir; "Muaf" seçeneği için.
  final String? gender;

  Member({
    required this.userId,
    required this.name,
    required this.roleTitle,
    required this.icon,
    this.gender,
  });

  factory Member.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    final name = profile is Map ? (profile['display_name'] as String? ?? '') : '';
    return Member(
      userId: m['user_id'] as String,
      name: name,
      roleTitle: m['role_title'] as String? ?? 'Aile Ferdi',
      icon: m['icon'] as String? ?? '👥',
      gender: m['gender'] as String?,
    );
  }

  /// Ekranda gösterilecek ad: önce rol, yoksa profil adı.
  String get shownName => roleTitle.isNotEmpty ? roleTitle : name;

  /// Bakan kişiye göre ad (reis için "Kızın", diğerleri için "Kızı").
  String labelFor({required bool viewerIsReis}) => titleFor(shownName, viewerIsReis: viewerIsReis);
}

class JoinRequest {
  final String id;
  final String userId;
  final String name;
  final String email;
  final String roleTitle;
  final String icon;
  final DateTime? createdAt;

  JoinRequest({
    this.createdAt,
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    required this.roleTitle,
    required this.icon,
  });

  factory JoinRequest.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return JoinRequest(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      name: profile is Map ? (profile['display_name'] as String? ?? '') : '',
      email: profile is Map ? (profile['email'] as String? ?? '') : '',
      roleTitle: m['role_title'] as String? ?? 'Aile Ferdi',
      icon: m['icon'] as String? ?? '👥',
      createdAt: m['created_at'] == null ? null : DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }
}

class PoolEvent {
  final int id;
  final String senderId;
  final String type;
  final String? prayer;
  final String message;
  final DateTime createdAt;

  PoolEvent({
    required this.id,
    required this.senderId,
    required this.type,
    required this.prayer,
    required this.message,
    required this.createdAt,
  });

  factory PoolEvent.fromMap(Map<String, dynamic> m) => PoolEvent(
        id: (m['id'] as num).toInt(),
        senderId: m['sender_id'] as String,
        type: m['event_type'] as String,
        prayer: m['prayer'] as String?,
        message: m['message'] as String? ?? '',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
