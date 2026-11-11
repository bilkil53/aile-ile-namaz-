-- Hesap silme hatası (23503 kaza_summary_user_id_fkey): kaza kaydı olan hesap silinirken, zincirleme
-- silinen kaza satırları özet tetikleyicisini çalıştırıyor ve tetikleyici silinmekte olan profil için
-- özeti yeniden yazmaya çalışıyordu. Profil yoksa özet yazılmaz.
-- Ayrıca aynı kişinin eşzamanlı kaza yazımları kişi başına kilitle sırayla toplanır (özet kayması).
create or replace function private.refresh_kaza_summary() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := coalesce(new.user_id, old.user_id);
begin
  if not exists (select 1 from public.profiles where id = v_user) then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended('kaza_summary:' || v_user::text, 0));
  insert into public.kaza_summary (user_id, owed, completed, updated_at)
  select v_user, coalesce(sum(owed_count), 0), coalesce(sum(completed_count), 0), now()
  from public.kaza_prayers where user_id = v_user
  on conflict (user_id) do update
    set owed = excluded.owed, completed = excluded.completed, updated_at = now();
  return null;
end $$;
revoke all on function private.refresh_kaza_summary() from public, anon, authenticated;
