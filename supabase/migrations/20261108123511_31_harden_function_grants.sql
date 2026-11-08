-- Güvenlik sıkılaştırma: varsayılan PUBLIC execute yetkisi kalan fonksiyonlar anon'dan alınır,
-- security definer fonksiyonların search_path'i boşaltılır (tüm adlar zaten şemayla yazılı).
revoke all on function public.my_pro_status() from public, anon;
revoke all on function public.request_pro_from_reis() from public, anon;
revoke all on function public.decline_pro_request(uuid) from public, anon;
revoke all on function public.test_restart_trial() from public, anon;
revoke all on function public.test_remove_pro() from public, anon;
grant execute on function public.my_pro_status() to authenticated;
grant execute on function public.request_pro_from_reis() to authenticated;
grant execute on function public.decline_pro_request(uuid) to authenticated;
grant execute on function public.test_restart_trial() to authenticated;
grant execute on function public.test_remove_pro() to authenticated;

-- İç fonksiyonlar: API rolleri çağıramaz (cron ve tetikleyici sahibi olarak çalışır)
revoke all on function private.retry_push_events() from public, anon, authenticated;
revoke all on function private.block_male_excused() from public, anon, authenticated;

alter function public.ensure_pro_trial() set search_path = '';
alter function public.redeem_pro_code(text) set search_path = '';
alter function public.expire_pro_test() set search_path = '';
alter function public.test_restart_trial() set search_path = '';
alter function public.test_remove_pro() set search_path = '';

-- pool_events: uygulama yalnızca bu 6 sütunu yazar. id, created_at ve push_* sütunları istemciden
-- yazılamaz (tarih geriye atılarak hız sınırı/temizlik atlatılamasın, kuyruk durumu oynanamasın).
-- UPDATE/DELETE politikası zaten yok; yetki de geri alınır.
revoke insert, update, delete on public.pool_events from anon, authenticated;
grant insert (pool_id, sender_id, event_type, message, prayer, target_id) on public.pool_events to authenticated;
