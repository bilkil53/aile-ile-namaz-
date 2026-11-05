-- 1) Davet kodu: EMB + 6 rakam (gösterim EMB-123456)
create or replace function private.gen_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  b bytea := extensions.gen_random_bytes(4);
  n bigint := (get_byte(b,0)::bigint << 24) + (get_byte(b,1) << 16) + (get_byte(b,2) << 8) + get_byte(b,3);
begin
  return 'EMB' || lpad((n % 1000000)::text, 6, '0');
end;
$$;

-- 2) Herkes başta "Aile Ferdi" (Bireysel Mod); reis unvanı katılım onayında belirlenir
create or replace function public.ensure_my_pool() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_pool uuid;
  v_code text;
  v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select pool_id into v_pool from public.pool_members where user_id = v_uid limit 1;
  if v_pool is not null then return v_pool; end if;
  select coalesce(nullif(split_part(display_name, ' ', 1), ''), 'Benim') into v_name from public.profiles where id = v_uid;
  loop
    v_code := private.gen_invite_code();
    exit when not exists (select 1 from public.pools where invite_code = v_code);
  end loop;
  insert into public.pools (name, owner_id, invite_code)
  values (left(coalesce(v_name, 'Benim') || ' Ailesi', 60), v_uid, v_code) returning id into v_pool;
  insert into public.pool_members (pool_id, user_id, role_title, icon) values (v_pool, v_uid, 'Aile Ferdi', '👤');
  return v_pool;
end;
$$;

-- 3) Katılma isteği: aynı anda tek istek, 5 dakika geçerli; kod yalnız rakamla da yazılabilir
create or replace function public.request_join(p_code text, p_role_title text default 'Aile Ferdi', p_icon text default '👥')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_pool uuid;
  v_req uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_code ~ '^[0-9]{6}$' then v_code := 'EMB' || v_code; end if;
  -- Süresi dolan istekleri düşür
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
  insert into public.join_requests (pool_id, user_id, role_title, icon)
  values (v_pool, v_uid, 'Aile Ferdi', '👥')
  returning id into v_req;
  return v_req;
end;
$$;

create or replace function public.my_outgoing_requests()
returns table (id uuid, pool_name text, owner_name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.id, p.name, pr.display_name, r.created_at
    from public.join_requests r
    join public.pools p on p.id = r.pool_id
    join public.profiles pr on pr.id = p.owner_id
   where r.user_id = (select auth.uid())
     and r.status = 'pending'
     and r.created_at > now() - interval '5 minutes'
   order by r.created_at desc;
$$;

-- 4) Onay: 5 dakika; reis kendi unvanını (Aile Reisi / Baba / Anne) ve katılanınkini belirler
create or replace function public.approve_join_with_roles(
  p_request uuid, p_member_role text, p_member_icon text,
  p_owner_role text default null, p_owner_icon text default null
) returns void
language plpgsql security definer set search_path = '' as $$
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
    update public.join_requests set status = 'rejected', decided_at = now() where id = r.id;
    raise exception 'request_expired' using errcode = 'P0001';
  end if;
  v_role := left(trim(coalesce(nullif(p_member_role, ''), 'Aile Ferdi')), 30);
  insert into public.pool_members (pool_id, user_id, role_title, icon)
  values (r.pool_id, r.user_id, v_role, left(coalesce(nullif(p_member_icon, ''), '👥'), 16))
  on conflict (pool_id, user_id) do update set role_title = excluded.role_title, icon = excluded.icon;
  if p_owner_role in ('Aile Reisi', 'Baba', 'Anne') then
    update public.pool_members
       set role_title = p_owner_role,
           icon = left(coalesce(nullif(p_owner_icon, ''), case p_owner_role when 'Anne' then '🧕' when 'Baba' then '🧔' else '👑' end), 16)
     where pool_id = r.pool_id and user_id = v_uid;
  end if;
  update public.join_requests set status = 'approved', decided_at = now() where id = r.id;
  delete from public.pools p
   where p.owner_id = r.user_id and p.id <> r.pool_id
     and not exists (select 1 from public.pool_members m where m.pool_id = p.id and m.user_id <> r.user_id);
  insert into public.pool_events (pool_id, sender_id, event_type, message) values (r.pool_id, r.user_id, 'MEMBER_JOINED', v_role);
end;
$$;

-- 5) Reis kendi unvanını sadece Aile Reisi / Baba / Anne yapabilir; diğerlerine reise göre unvan verir
create or replace function public.set_member_role(p_pool uuid, p_user uuid, p_role text, p_icon text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select owner_id into v_owner from public.pools where id = p_pool;
  if v_owner is null or v_owner <> auth.uid() then raise exception 'not_pool_owner' using errcode = '42501'; end if;
  if p_user = v_owner then
    update public.pool_members
       set role_title = case when p_role in ('Aile Reisi','Baba','Anne') then p_role else role_title end,
           icon = left(p_icon, 16)
     where pool_id = p_pool and user_id = p_user;
  else
    update public.pool_members set role_title = left(trim(p_role), 30), icon = left(p_icon, 16)
     where pool_id = p_pool and user_id = p_user;
  end if;
end;
$$;

-- 6) Hesabımı ve verilerimi sil
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  p record;
  v_next uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  for p in select id from public.pools where owner_id = v_uid loop
    select user_id into v_next from public.pool_members
     where pool_id = p.id and user_id <> v_uid order by joined_at limit 1;
    if v_next is null then
      delete from public.pools where id = p.id;
    else
      update public.pools set owner_id = v_next where id = p.id;
      update public.pool_members set role_title = 'Aile Reisi', icon = '👑' where pool_id = p.id and user_id = v_next;
    end if;
  end loop;
  delete from auth.users where id = v_uid; -- profil ve tüm kayıtlar zincirleme silinir
end;
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
