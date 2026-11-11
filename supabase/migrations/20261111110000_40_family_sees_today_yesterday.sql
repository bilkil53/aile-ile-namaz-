-- Namaz kayıtlarında zaman penceresi (İstanbul gününe göre 2 gün geri, 1 gün ileri; saat dilimi ve kısa
-- çevrimdışı süre payı). Uygulama yalnızca bugün ve dünü gösterir/yazar.
--  * Aile üyeleri birbirinin kaydını yalnızca bu pencerede görür; kişi kendi geçmişinin tamamını görür.
--  * Kişi kendi kaydını yalnızca bu pencerede ekler/değiştirir/siler; geçmiş kayıtlar değiştirilemez.
--  * Hesap silme (security definer) ve sunucu tetikleyicileri bu kurallardan etkilenmez.
drop policy if exists daily_prayers_select on public.daily_prayers;
create policy daily_prayers_select on public.daily_prayers for select to authenticated
  using (user_id = (select auth.uid())
         or (prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                             and (now() at time zone 'Europe/Istanbul')::date + 1
             and private.shares_pool_with(user_id)));
drop policy if exists daily_prayers_insert_own on public.daily_prayers;
create policy daily_prayers_insert_own on public.daily_prayers for insert to authenticated
  with check (user_id = (select auth.uid())
              and prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                                  and (now() at time zone 'Europe/Istanbul')::date + 1);
drop policy if exists daily_prayers_update_own on public.daily_prayers;
create policy daily_prayers_update_own on public.daily_prayers for update to authenticated
  using (user_id = (select auth.uid())
         and prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                             and (now() at time zone 'Europe/Istanbul')::date + 1)
  with check (user_id = (select auth.uid())
              and prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                                  and (now() at time zone 'Europe/Istanbul')::date + 1);
drop policy if exists daily_prayers_delete_own on public.daily_prayers;
create policy daily_prayers_delete_own on public.daily_prayers for delete to authenticated
  using (user_id = (select auth.uid())
         and prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                             and (now() at time zone 'Europe/Istanbul')::date + 1);
