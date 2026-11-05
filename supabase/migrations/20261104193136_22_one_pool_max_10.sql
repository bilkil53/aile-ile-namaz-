-- 1 aile = 1 havuz; havuz en fazla 10 kişi
create unique index if not exists pools_one_per_owner on public.pools(owner_id);
create unique index if not exists pool_members_one_pool_per_user on public.pool_members(user_id);

create or replace function private.pool_max_members() returns int language sql immutable as $$ select 10 $$;

create or replace function public.request_join(p_code text, p_role_title text default 'Aile Ferdi'::text, p_icon text default '👥'::text)
 returns uuid language plpgsql security definer set search_path to '' as $function$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_pool uuid;
  v_req uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_code ~ '^[0-9]{6}$' then v_code := 'EMB' || v_code; end if;
  update public.join_requests set status = 'rejected', decided_at = now()
   where user_id = v_uid and status = 'pending' and created_at < now() - interval '5 minutes';
  if exists (select 1 from public.join_requests where user_id = v_uid and status = 'pending') then
    raise exception 'pending_exists' using errcode = 'P0001';
  end if;
  insert into public.join_attempts (user_id) values (v_uid);
  if (select count(*) from public.join_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') > 20 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;
  select id into v_pool from public.pools where invite_code = v_code;
  if v_pool is null then return null; end if;
  if exists (select 1 from public.pool_members where pool_id = v_pool and user_id = v_uid) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  -- Zaten kalabalık bir ailedeyse başka havuza geçemez (önce ayrılmalı)
  if exists (select 1 from public.pool_members m where m.user_id = v_uid
               and exists (select 1 from public.pool_members o where o.pool_id = m.pool_id and o.user_id <> v_uid)) then
    raise exception 'already_in_family' using errcode = 'P0001';
  end if;
  if (select count(*) from public.pool_members where pool_id = v_pool) >= private.pool_max_members() then
    raise exception 'pool_full' using errcode = 'P0001';
  end if;
  insert into public.join_requests (pool_id, user_id, role_title, icon)
  values (v_pool, v_uid, 'Aile Ferdi', '👥')
  returning id into v_req;
  return v_req;
end;
$function$;

create or replace function public.approve_join_with_roles(p_request uuid, p_member_role text, p_member_icon text, p_owner_role text default null::text, p_owner_icon text default null::text, p_member_gender text default null::text, p_owner_gender text default null::text)
 returns void language plpgsql security definer set search_path to '' as $function$
declare
  v_uid uuid := auth.uid();
  r public.join_requests%rowtype;
  v_role text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into r from public.join_requests where id = p_request and status = 'pending' for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.pools where id = r.pool_id and owner_id = v_uid) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  if r.created_at < now() - interval '5 minutes' then
    update public.join_requests set status = 'expired', decided_at = now() where id = r.id;
    raise exception 'request_expired' using errcode = 'P0001';
  end if;
  perform 1 from public.pools where id = r.pool_id for update; -- aynı anda iki onayda sayıyı kilitle
  if (select count(*) from public.pool_members where pool_id = r.pool_id) >= private.pool_max_members() then
    raise exception 'pool_full' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.pool_members m where m.user_id = r.user_id and m.pool_id <> r.pool_id
               and exists (select 1 from public.pool_members o where o.pool_id = m.pool_id and o.user_id <> r.user_id)) then
    raise exception 'already_in_family' using errcode = 'P0001';
  end if;
  -- Katılanın tek kişilik eski havuzunu önce kaldır (kişi aynı anda tek havuzda olur)
  delete from public.pool_members m where m.user_id = r.user_id and m.pool_id <> r.pool_id;
  delete from public.pools p
   where p.owner_id = r.user_id and p.id <> r.pool_id
     and not exists (select 1 from public.pool_members m where m.pool_id = p.id);
  v_role := left(trim(coalesce(nullif(p_member_role, ''), 'Aile Ferdi')), 30);
  insert into public.pool_members (pool_id, user_id, role_title, icon, gender)
  values (r.pool_id, r.user_id, v_role, left(coalesce(nullif(p_member_icon, ''), '👥'), 16),
          case when p_member_gender in ('m', 'f') then p_member_gender end)
  on conflict (pool_id, user_id) do update
    set role_title = excluded.role_title, icon = excluded.icon, gender = excluded.gender;
  if p_owner_role in ('Aile Reisi', 'Baba', 'Anne') then
    update public.pool_members
       set role_title = p_owner_role,
           icon = left(coalesce(nullif(p_owner_icon, ''), case p_owner_role when 'Anne' then '🧕' when 'Baba' then '🧔' else '🏡' end), 16),
           gender = case p_owner_role when 'Anne' then 'f' when 'Baba' then 'm'
                      else case when p_owner_gender in ('m', 'f') then p_owner_gender else gender end end
     where pool_id = r.pool_id and user_id = v_uid;
  end if;
  update public.join_requests set status = 'approved', decided_at = now() where id = r.id;
  insert into public.pool_events (pool_id, sender_id, event_type, message) values (r.pool_id, r.user_id, 'MEMBER_JOINED', v_role);
end;
$function$;
