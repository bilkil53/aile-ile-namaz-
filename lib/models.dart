import 'lang.dart';

enum PrayerStatus { none, prayed, missed, excused }

extension PrayerStatusX on PrayerStatus {
  String get code => switch (this) {
        PrayerStatus.none => 'NONE',
        PrayerStatus.prayed => 'PRAYED',
        PrayerStatus.missed => 'MISSED',
        PrayerStatus.excused => 'EXCUSED',
      };

  String get label => switch (this) {
        PrayerStatus.none => t('Belirtilmedi', 'Not marked'),
        PrayerStatus.prayed => t('Kıldı', 'Prayed'),
        PrayerStatus.missed => t('Kılmadı', 'Missed'),
        PrayerStatus.excused => t('Muaf', 'Excused'),
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

/// Vakit adları seçilen dilde (Türkçe / İngilizce).
Map<String, String> get prayerLabels => Lang.isEn ? _prayerLabelsEn : _prayerLabelsTr;

const _prayerLabelsEn = {
  'fajr': 'Fajr',
  'dhuhr': 'Dhuhr',
  'asr': 'Asr',
  'maghrib': 'Maghrib',
  'isha': 'Isha',
  'witr': 'Witr',
};

const _prayerLabelsTr = {
  'fajr': 'Sabah',
  'dhuhr': 'Öğle',
  'asr': 'İkindi',
  'maghrib': 'Akşam',
  'isha': 'Yatsı',
  'witr': 'Vitir',
};

/// Reisin kendi unvanı (katılım onayında seçer).
const ownerTitles = {'Aile Reisi': '🏡', 'Baba': '🧔', 'Anne': '🧕'};

/// Unvanlar Aile Reisine göredir (reisin eşi, oğlu, kızı…). Reisin unvanı sabit: "Aile Reisi".
const reisTitles = {
  'Eşi': '🧕',
  'Oğlu': '👦',
  'Kızı': '🧕🎀',
  'Annesi': '🧕',
  'Babası': '🧔',
  'Kardeşi': '🧒',
  'Torunu': '🧒',
  'Gelini': '🧕',
  'Damadı': '👨',
  'Dedesi': '👴',
  'Ninesi': '👵',
  'Aile Ferdi': '👥',
};

/// Erkek ünvan/simgeler: bu kişilerde "Muaf" seçeneği gösterilmez (Aile Reisi erkek kabul edilir).
const femaleTitles = {'Anne', 'Kızı', 'Annesi', 'Ninesi', 'Gelini'};
const maleTitles = {'Aile Reisi', 'Baba', 'Oğlu', 'Babası', 'Dedesi', 'Damadı'};
const maleIcons = {'🧔', '👨', '👴', '👱‍♂️', '👦', '🏡'};

/// Başörtülü kız çocuğu: 🧕 + 🎀 (anneden ayırmak için küçük fiyonk rozetiyle çizilir).
const girlScarf = '🧕🎀';

/// Başörtüsüz kız çocuğu: 👧 + 🎀.
const girlPlain = '👧🎀';
const femaleIcons = {'🧕', '🧕🏻', '🧕🏼', '🧕🏽', '🧕🏾', '🧕🏿', '👩', '👵', '👱‍♀️', '👧', girlScarf, girlPlain};

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
String titleFor(String role, {required bool viewerIsReis}) =>
    roleText(viewerIsReis ? (_possessive[role] ?? role) : role);

/// Ünvan ve akrabalık sözcüklerinin İngilizcesi. Veritabanında ünvanlar hep Türkçe saklanır;
/// yalnızca ekranda gösterilirken çevrilir. Kullanıcının yazdığı özel ad olduğu gibi kalır.
const _kinEn = {
  // Reise göre ünvanlar (3. kişi)
  'Aile Reisi': 'Head of Family', 'Baba': 'Father', 'Anne': 'Mother', 'Aile Ferdi': 'Family Member',
  'Eşi': 'Spouse', 'Oğlu': 'Son', 'Kızı': 'Daughter', 'Annesi': 'Mother', 'Babası': 'Father',
  'Kardeşi': 'Sibling', 'Torunu': 'Grandchild', 'Gelini': 'Daughter-in-law', 'Damadı': 'Son-in-law',
  'Dedesi': 'Grandfather', 'Ninesi': 'Grandmother',
  // Bakan kişiye göre hitaplar (2. kişi)
  'Eşin': 'Your spouse', 'Oğlun': 'Your son', 'Kızın': 'Your daughter', 'Annen': 'Your mother',
  'Baban': 'Your father', 'Kardeşin': 'Your sibling', 'Torunun': 'Your grandchild',
  'Gelinin': 'Your daughter-in-law', 'Damadın': 'Your son-in-law', 'Deden': 'Your grandfather',
  'Ninen': 'Your grandmother', 'Ebeveynin': 'Your parent', 'Çocuğun': 'Your child',
  'Büyüğün': 'Your grandparent', 'Kayınpederin': 'Your father-in-law', 'Kayınvaliden': 'Your mother-in-law',
  'Kayınbüyüğün': 'Your parent-in-law', 'Amcan': 'Your uncle', 'Halan': 'Your aunt', 'Dayın': 'Your uncle',
  'Teyzen': 'Your aunt', 'Amcan / Halan': 'Your uncle / aunt', 'Dayın / Teyzen': 'Your uncle / aunt',
  'Yengen': 'Your sister-in-law', 'Enişten': 'Your brother-in-law', 'Yeğenin': 'Your niece / nephew',
};

/// Ünvanı / hitabı seçilen dilde verir (bilinmeyen ad olduğu gibi döner).
String roleText(String tr) => Lang.isEn ? (_kinEn[tr] ?? tr) : tr;

/// Reisin seçebileceği simge grupları.
const iconGroups = <String, List<String>>{
  'Kadın / Anne / Eş': ['🧕', '👩', '👵', '👱‍♀️'],
  'Erkek / Baba / Eş': ['🧔', '👨', '👴', '👱‍♂️'],
  'Erkek / Kız / Çocuk': ['👦', girlScarf, girlPlain, '🧒'],
  'Diğer': ['🏡', '👤', '👥', '🌟', '🕌'],
};

/// Simge grubu başlığı seçilen dilde.
String iconGroupText(String tr) => Lang.isEn
    ? const {
          'Kadın / Anne / Eş': 'Woman / Mother / Wife',
          'Erkek / Baba / Eş': 'Man / Father / Husband',
          'Erkek / Kız / Çocuk': 'Boy / Girl / Child',
          'Diğer': 'Other',
        }[tr] ??
        tr
    : tr;

/// Simgeden cinsiyet: kadın/kız simgesi → 'f' (Muaf açılır), erkek simgesi → 'm', diğerleri → null.
String? genderOfIcon(String icon) =>
    femaleIcons.contains(icon) ? 'f' : (maleIcons.contains(icon) ? 'm' : null);

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
  /// Ekranda görünen havuz adı. Otomatik verilen "<Reis adı> Ailesi" yerine "Ailemiz";
  /// Aile Reisi kendi ad verdiyse o ad görünür.
  String get displayName => name.trim().isEmpty || name.trim().endsWith(' Ailesi') ? 'Ailemiz' : name.trim();

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

  /// Kişinin ilk adı (bildirimde aynı ünvanlı iki kişiyi ayırmak için: "Kızın Ayşe").
  String get firstName {
    final n = name.trim().split(RegExp(r'\s+')).first;
    if (n.isEmpty || n == 'Misafir') return '';
    // Hepsi büyük ya da hepsi küçük yazılmışsa Türkçe kurallarıyla düzelt (ERDİNÇ → Erdinç)
    if (n != n.toUpperCase() && n != n.toLowerCase()) return n;
    String up(String c) => c == 'i' ? 'İ' : (c == 'ı' ? 'I' : c.toUpperCase());
    String low(String t) => t.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    return up(low(n[0])) + low(n.substring(1));
  }

  /// Bakan kişiye göre ad (reis için "Kızın", diğerleri için "Kızı").
  String labelFor({required bool viewerIsReis}) => titleFor(shownName, viewerIsReis: viewerIsReis);
}

class JoinRequest {
  final String id;
  final String userId;
  final String name;
  final String roleTitle;
  final String icon;
  final DateTime? createdAt;

  JoinRequest({
    this.createdAt,
    required this.id,
    required this.userId,
    required this.name,
    required this.roleTitle,
    required this.icon,
  });

  factory JoinRequest.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return JoinRequest(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      name: profile is Map ? (profile['display_name'] as String? ?? '') : '',
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

  /// Kişiye özel dua: yalnızca bu kişiye gider (ve sadece gönderen ile alan görür).
  final String? targetId;

  PoolEvent({
    this.targetId,
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
        targetId: m['target_id'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Akrabalık hitapları: ünvanlar Aile Reisine göre saklanır ("Kızı", "Eşi").
// Her kullanıcı diğerlerini KENDİSİNE göre görür:
//   Reis → "Kızın", "Eşin"; Eşi → "Eşin (Aile Reisi)", "Kızın"; Kızı → "Baban (Aile Reisi)", "Annen".
// ---------------------------------------------------------------------------

String? genderOf(Member m) =>
    m.gender ?? (femaleTitles.contains(m.roleTitle) ? 'f' : (maleTitles.contains(m.roleTitle) ? 'm' : null));

/// [viewer] ekranında [target] kişisinin hitabı. [reis] havuzun Aile Reisi.
String kinLabel({required Member viewer, required Member target, required Member? reis}) {
  if (viewer.userId == target.userId) return roleText(target.shownName);
  if (reis != null && viewer.userId == reis.userId) return titleFor(target.shownName, viewerIsReis: true);
  final reisG = reis == null ? null : genderOf(reis);
  var tg = genderOf(target);
  // Reisin eşi: cinsiyeti verilmemişse reisin karşı cinsi kabul edilir
  if (tg == null && target.roleTitle == 'Eşi' && reisG != null) tg = reisG == 'm' ? 'f' : 'm';
  String pick(String m, String f, String n) => tg == 'f' ? f : (tg == 'm' ? m : n);
  final v = viewer.roleTitle;

  if (reis != null && target.userId == reis.userId) {
    final rel = switch (v) {
      'Eşi' => 'Eşin',
      'Oğlu' || 'Kızı' => pick('Baban', 'Annen', 'Ebeveynin'),
      'Annesi' || 'Babası' => pick('Oğlun', 'Kızın', 'Çocuğun'),
      'Kardeşi' => 'Kardeşin',
      'Torunu' => pick('Deden', 'Ninen', 'Büyüğün'),
      'Gelini' || 'Damadı' => pick('Kayınpederin', 'Kayınvaliden', 'Kayınbüyüğün'),
      'Dedesi' || 'Ninesi' => 'Torunun',
      _ => null,
    };
    return rel == null ? roleText(target.shownName) : '${roleText(rel)} (${roleText(target.shownName)})';
  }

  final role = target.roleTitle;
  final reisMale = reisG == 'm';
  final String? rel = switch (v) {
    'Eşi' => switch (role) {
        'Oğlu' => 'Oğlun',
        'Kızı' => 'Kızın',
        'Torunu' => 'Torunun',
        'Gelini' => 'Gelinin',
        'Damadı' => 'Damadın',
        'Annesi' => 'Kayınvaliden',
        'Babası' => 'Kayınpederin',
        _ => null,
      },
    'Oğlu' || 'Kızı' => switch (role) {
        'Eşi' => pick('Baban', 'Annen', 'Ebeveynin'),
        'Oğlu' || 'Kızı' => 'Kardeşin',
        'Annesi' => 'Ninen',
        'Babası' => 'Deden',
        'Kardeşi' => reisMale ? pick('Amcan', 'Halan', 'Amcan / Halan') : pick('Dayın', 'Teyzen', 'Dayın / Teyzen'),
        'Gelini' => 'Yengen',
        'Damadı' => 'Enişten',
        _ => null,
      },
    'Annesi' || 'Babası' => switch (role) {
        'Annesi' || 'Babası' => 'Eşin',
        'Eşi' => pick('Damadın', 'Gelinin', 'Gelinin'),
        'Oğlu' || 'Kızı' || 'Torunu' => 'Torunun',
        'Kardeşi' => pick('Oğlun', 'Kızın', 'Çocuğun'),
        _ => null,
      },
    'Kardeşi' => switch (role) {
        'Annesi' => 'Annen',
        'Babası' => 'Baban',
        'Kardeşi' => 'Kardeşin',
        'Oğlu' || 'Kızı' => 'Yeğenin',
        'Eşi' => pick('Enişten', 'Yengen', 'Yengen'),
        _ => null,
      },
    'Gelini' || 'Damadı' => switch (role) {
        'Eşi' => pick('Kayınpederin', 'Kayınvaliden', 'Kayınbüyüğün'),
        'Torunu' => pick('Oğlun', 'Kızın', 'Çocuğun'),
        _ => null,
      },
    'Torunu' => switch (role) {
        'Eşi' => pick('Deden', 'Ninen', 'Büyüğün'),
        _ => null,
      },
    _ => null,
  };
  if (rel != null) return roleText(rel);
  // İlişki çıkarılamıyorsa reise göre yaz: "Aile Reisinin Kızı"
  if (reisTitles.containsKey(role) && role != 'Aile Ferdi') {
    return Lang.isEn ? "Head of family's ${roleText(role).toLowerCase()}" : 'Aile Reisinin $role';
  }
  return roleText(target.shownName);
}

/// Hitaba ilk adı ekler: "Kızın" → "Kızın Ayşe", "Baban (Aile Reisi)" → "Baban Erdinç (Aile Reisi)".
String withFirstName(String label, String first) {
  if (first.isEmpty || label.contains(first)) return label;
  final i = label.indexOf(' (');
  return i < 0 ? '$label $first' : '${label.substring(0, i)} $first${label.substring(i)}';
}
