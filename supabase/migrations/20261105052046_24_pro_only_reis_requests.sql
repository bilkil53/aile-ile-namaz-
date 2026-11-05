-- Pro'yu sadece Aile Reisi (havuz sahibi) alır; diğerleri reise "Pro istiyorum" iletir.
alter table public.pool_events drop constraint pool_events_event_type_check;
alter table public.pool_events add constraint pool_events_event_type_check
  check (event_type = any (array['PRAYED','MISSED','KAZA','DUA','MEMBER_JOINED','MEMBER_LEFT','PRO_REQUEST']));

create or replace function private.is_non_reis_member(p_uid uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from public.pool_members m join public.pools p on p.id = m.pool_id
                  where m.user_id = p_uid and p.owner_id <> p_uid)
$$;

create or replace function public.redeem_pro_code(p_code text) returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if private.is_non_reis_member(auth.uid()) then raise exception 'only_reis'; end if;
  -- Test aşaması Pro kodu: "1" (gerçek satışta Google Play ödemesine geçilecek)
  if btrim(coalesce(p_code, '')) <> '1' then raise exception 'gecersiz_kod'; end if;
  update public.profiles
     set pro_paid_until = greatest(coalesce(pro_paid_until, now()), now()) + interval '365 days'
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

-- Reis olmayan üye, reise Pro isteği iletir (günde en fazla 1).
create or replace function public.request_pro_from_reis() returns void
language plpgsql security definer set search_path to '' as $$
declare v_uid uuid := auth.uid(); v_pool uuid; v_owner uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select p.id, p.owner_id into v_pool, v_owner
    from public.pool_members m join public.pools p on p.id = m.pool_id
   where m.user_id = v_uid limit 1;
  if v_pool is null or v_owner = v_uid then raise exception 'is_reis' using errcode = 'P0001'; end if;
  if exists (select 1 from public.pool_events where sender_id = v_uid and event_type = 'PRO_REQUEST'
               and created_at > now() - interval '20 hours') then
    raise exception 'already_requested' using errcode = 'P0001';
  end if;
  insert into public.pool_events (pool_id, sender_id, event_type, target_id)
  values (v_pool, v_uid, 'PRO_REQUEST', v_owner);
end $$;
grant execute on function public.request_pro_from_reis() to authenticated;
revoke all on function private.is_non_reis_member(uuid) from public;
