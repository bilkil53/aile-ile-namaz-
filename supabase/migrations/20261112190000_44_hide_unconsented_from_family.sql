-- Açık rızası (güncel metin sürümüyle) olmayan kişinin kayıtları aileye görünmez ve aileye bildirim üretmez.
-- Kişi kendi kayıtlarını görmeye devam eder; rıza verince her şey kendiliğinden görünür olur.
-- Yalnızca kişinin kendisi ya da aynı havuzdaki biri sorgulayabilir (başkasının rıza durumu öğrenilemez).
create or replace function private.has_acik_riza(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select (p_user = (select auth.uid()) or auth.uid() is null or private.shares_pool_with(p_user))
     and exists (select 1 from public.profiles pr
                  where pr.id = p_user and pr.acik_riza_at is not null
                    and coalesce(pr.acik_riza_version, 0) >= private.riza_version());
$$;
revoke all on function private.has_acik_riza(uuid) from public, anon;
grant execute on function private.has_acik_riza(uuid) to authenticated;

drop policy if exists daily_prayers_select on public.daily_prayers;
create policy daily_prayers_select on public.daily_prayers for select to authenticated using (
  user_id = (select auth.uid())
  or (prayer_date >= ((now() at time zone 'Europe/Istanbul')::date - 2)
      and prayer_date <= ((now() at time zone 'Europe/Istanbul')::date + 1)
      and private.shares_pool_with(user_id)
      and private.has_acik_riza(user_id)));

drop policy if exists kaza_summary_select on public.kaza_summary;
create policy kaza_summary_select on public.kaza_summary for select to authenticated using (
  user_id = (select auth.uid())
  or (private.shares_pool_with(user_id) and private.has_acik_riza(user_id)));

-- Daha önce eklenmiş olaylar da (mesajlı dualar dahil) rıza yokken aileye görünmez
drop policy if exists pool_events_select on public.pool_events;
create policy pool_events_select on public.pool_events for select to authenticated using (
  private.is_pool_member(pool_id)
  and (target_id is null or target_id = (select auth.uid()) or sender_id = (select auth.uid()))
  and (sender_id = (select auth.uid())
       or event_type not in ('PRAYED', 'MISSED', 'KAZA', 'DUA', 'ALL_PRAYED')
       or private.has_acik_riza(sender_id)));

-- Aile olayı (kıldı / kılamadı / kaza / dua / 5 vakit): rıza yoksa hata vermeden düşürülür
-- (eski sürümler de takılmaz, kuyrukta beklemez; aileye bildirim gitmez). Ad "0" ile başlar:
-- aynı türdeki tetikleyiciler ad sırasıyla çalışır, hız sınırından önce çalışsın.
create or replace function private.pool_events_require_riza() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.event_type in ('PRAYED', 'MISSED', 'KAZA', 'DUA', 'ALL_PRAYED') and not exists (
       select 1 from public.profiles pr
        where pr.id = new.sender_id and pr.acik_riza_at is not null
          and coalesce(pr.acik_riza_version, 0) >= private.riza_version()) then
    return null;
  end if;
  return new;
end $$;
revoke all on function private.pool_events_require_riza() from public, anon, authenticated;
drop trigger if exists pool_events_require_riza on public.pool_events;
drop trigger if exists pool_events_0_require_riza on public.pool_events;
create trigger pool_events_0_require_riza before insert on public.pool_events
  for each row execute function private.pool_events_require_riza();
