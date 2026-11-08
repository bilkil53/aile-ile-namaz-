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
final _rejectedCodes = RegExp(r'^(22|23|42|P0)');

/// 42501 (yetki/RLS) kalıcı sayılmaz: kendi kaydına yazarken bu hata ancak oturum düştüğünde
/// (istek yetkisiz gittiğinde) olur. Kayıt silinmez, oturum düzelince tekrar gönderilir.
const _authCode = '42501';

SyncFailure classifySyncError(Object e) {
  if (e is PostgrestException) {
    final c = e.code ?? '';
    if (c != _authCode && _rejectedCodes.hasMatch(c)) return SyncFailure.rejected;
  }
  return SyncFailure.temporary;
}

/// Misafir kaza sayılarını sunucudaki merge_guest_kaza(p_items) biçimine çevirir:
/// {tür: [borç, kılınan]}. Negatif sayılar gönderilmez (sunucu da reddeder).
Map<String, List<int>> guestMergePayload(Map<String, (int, int)> kaza) => {
      for (final e in kaza.entries)
        if (e.value.$1 >= 0 && e.value.$2 >= 0) e.key: [e.value.$1, e.value.$2],
    };
