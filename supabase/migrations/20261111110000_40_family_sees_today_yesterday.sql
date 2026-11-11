-- Aile üyeleri birbirinin namaz kaydını yalnızca bugün ve dün için görür (uygulamanın Aile ekranıyla aynı).
-- Saat dilimi farkları için İstanbul gününe göre 2 gün geri, 1 gün ileri pay bırakılır. Kişi kendi geçmişinin tamamını görür.
drop policy if exists daily_prayers_select on public.daily_prayers;
create policy daily_prayers_select on public.daily_prayers for select to authenticated
  using (user_id = (select auth.uid())
         or (prayer_date between (now() at time zone 'Europe/Istanbul')::date - 2
                             and (now() at time zone 'Europe/Istanbul')::date + 1
             and private.shares_pool_with(user_id)));
