// Senkron kararları: ağ ya da sunucu bağımlılığı olmayan saf fonksiyonlar (birim testleri için ayrı dosyada).
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Buluta gönderim neden başarısız oldu?
enum SyncFailure {
  /// İnternet yok, zaman aşımı, sunucuya ulaşılamadı ya da geçici sunucu hatası: kayıt bekler, tekrar denenir.
  temporary,

  /// Sunucu kaydı kalıcı olarak reddetti (kural, yetki, geçersiz veri): tekrar denemek işe yaramaz.
  rejected,
}

/// Kalıcı ret sayılan PostgreSQL hata sınıfları: 22 (geçersiz veri), 23 (kısıt ihlali),
/// 42 (tanımsız sütun vb.), P0 (tetikleyicinin bilerek verdiği hata, ör. kural ihlali).
/// Diğer her şey (bağlantı, zaman aşımı, 08/53/57 sınıfları, PGRST kodları) geçici sayılır.
/// Yalnızca 5 karakterli SQLSTATE kabul edilir: cevap JSON değilse kütüphane `code` alanına HTTP
/// durumunu yazar ("429" hız sınırı, "422", "500"); bunlar kalıcı ret sayılmamalı.
final _rejectedCodes = RegExp(r'^(22|23|42|P0)[0-9A-Z]{3}$');

/// 42501 (yetki/RLS) hemen kalıcı sayılmaz: kendi kaydına yazarken bu hata çoğunlukla oturum
/// düştüğünde (istek yetkisiz gittiğinde) olur. Kayıt silinmez; aynı kayıt [maxAuthRetries] kez
/// üst üste bu hatayı alırsa kalıcı ret sayılır (sonsuz deneme ve arkadaki kayıtların beklemesi olmasın).
const authErrorCode = '42501';
const maxAuthRetries = 5;

bool isAuthError(Object e) => e is PostgrestException && e.code == authErrorCode;

SyncFailure classifySyncError(Object e) {
  if (e is PostgrestException) {
    final c = e.code ?? '';
    if (c != authErrorCode && _rejectedCodes.hasMatch(c)) return SyncFailure.rejected;
  }
  return SyncFailure.temporary;
}

/// İki kuyruk kaydı aynı işlem mi? (Deneme sayacı `a` gibi ek alanlar karşılaştırılmaz.)
/// Gönderim sürerken kullanıcı aynı vakti yeniden işaretlerse yeni kayıt eskisinin yerini alır;
/// eskisi gönderilince yalnızca kendisi silinir, yenisi kuyrukta kalır.
bool sameQueueOp(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a['t'] != b['t']) return false;
  return switch (a['t']) {
    'prayer' => a['date'] == b['date'] && a['key'] == b['key'] && a['status'] == b['status'],
    'kaza' => a['type'] == b['type'] && a['o'] == b['o'] && a['c'] == b['c'],
    _ => false,
  };
}

/// Misafir kaza sayılarını sunucudaki merge_guest_kaza(p_items) biçimine çevirir:
/// {tür: [borç, kılınan]}. Negatif sayılar gönderilmez (sunucu da reddeder).
Map<String, List<int>> guestMergePayload(Map<String, (int, int)> kaza) => {
      for (final e in kaza.entries)
        if (e.value.$1 >= 0 && e.value.$2 >= 0) e.key: [e.value.$1, e.value.$2],
    };
