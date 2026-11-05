-- Reis onaylarken iki tarafın rolünü birden belirler (v1.16). 24 saati geçen istek geçersiz (v1.18).
create function public.approve_join_with_roles(
  p_request uuid,
  p_member_role text,
  p_member_icon text,
  p_owner_role text default null,
  p_owner_icon text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  r public.join_requests%rowtype;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into r from public.join_requests where id = p_request and status = 'pending' for update;
  if not found then raise exception 'request_not_found' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.pools where id = r.pool_id and owner_id = v_uid) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  if r.created_at < now() - interval '24 hours' then
    update public.join_requests set status = 'rejected', decided_at = now() where id = r.id;
    raise exception 'request_expired' using errcode = 'P0001';
  end if;
  insert into public.pool_members (pool_id, user_id, role_title, icon)
  values (r.pool_id, r.user_id, left(trim(coalesce(nullif(p_member_role, ''), r.role_title)), 30),
          left(coalesce(nullif(p_member_icon, ''), r.icon), 16))
  on conflict (pool_id, user_id) do update set role_title = excluded.role_title, icon = excluded.icon;
  if nullif(trim(coalesce(p_owner_role, '')), '') is not null then
    update public.pool_members
       set role_title = left(trim(p_owner_role), 30), icon = left(coalesce(nullif(p_owner_icon, ''), icon), 16)
     where pool_id = r.pool_id and user_id = v_uid;
  end if;
  update public.join_requests set status = 'approved', decided_at = now() where id = r.id;
  insert into public.pool_events (pool_id, sender_id, event_type, message)
  values (r.pool_id, r.user_id, 'MEMBER_JOINED', left(trim(coalesce(nullif(p_member_role, ''), r.role_title)), 30));
end;
$$;

-- Reisin Gmail adresiyle katılma isteği (v1.18). Bulunamazsa null (hesap varlığı sızmaz).
create function public.request_join_by_email(p_email text, p_role_title text default 'Aile Ferdi', p_icon text default '👥')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_pool uuid;
  v_req uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  insert into public.join_attempts (user_id) values (v_uid);
  if (select count(*) from public.join_attempts
      where user_id = v_uid and attempted_at > now() - interval '1 hour') > 20 then
    raise exception 'too_many_attempts' using errcode = 'P0001';
  end if;
  select p.id into v_pool
    from public.pools p join public.profiles pr on pr.id = p.owner_id
   where lower(pr.email) = lower(trim(p_email))
   order by p.created_at
   limit 1;
  if v_pool is null then return null; end if;
  if exists (select 1 from public.pool_members where pool_id = v_pool and user_id = v_uid) then
    raise exception 'already_member' using errcode = 'P0001';
  end if;
  insert into public.join_requests (pool_id, user_id, role_title, icon)
  values (v_pool, v_uid, left(trim(p_role_title), 30), left(p_icon, 16))
  on conflict (pool_id, user_id) where status = 'pending'
  do update set role_title = excluded.role_title, icon = excluded.icon, created_at = now()
  returning id into v_req;
  return v_req;
end;
$$;

-- İsteği gönderen iptal edebilir (v1.17).
create function public.cancel_join_request(p_request uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  delete from public.join_requests
   where id = p_request and user_id = auth.uid() and status = 'pending';
end;
$$;

-- Gönderdiğim bekleyen istekler (havuz adı ve reis adıyla; havuz verisine erişim vermeden).
create function public.my_outgoing_requests()
returns table (id uuid, pool_name text, owner_name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.id, p.name, pr.display_name, r.created_at
    from public.join_requests r
    join public.pools p on p.id = r.pool_id
    join public.profiles pr on pr.id = p.owner_id
   where r.user_id = (select auth.uid())
     and r.status = 'pending'
     and r.created_at > now() - interval '24 hours'
   order by r.created_at desc;
$$;

-- Rol ve simge atama yetkisi Aile Reisinde.
create function public.set_member_role(p_pool uuid, p_user uuid, p_role text, p_icon text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from public.pools where id = p_pool and owner_id = auth.uid()) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  update public.pool_members
     set role_title = left(trim(p_role), 30), icon = left(p_icon, 16)
   where pool_id = p_pool and user_id = p_user;
end;
$$;

-- Yalnızca reis rol değiştirebilsin: üyelerin kendi satırını güncelleme yetkisini kaldır.
drop policy if exists pool_members_update_own on public.pool_members;
revoke update on public.pool_members from authenticated;

revoke execute on function public.approve_join_with_roles(uuid, text, text, text, text) from public, anon;
revoke execute on function public.request_join_by_email(text, text, text) from public, anon;
revoke execute on function public.cancel_join_request(uuid) from public, anon;
revoke execute on function public.my_outgoing_requests() from public, anon;
revoke execute on function public.set_member_role(uuid, uuid, text, text) from public, anon;
grant execute on function public.approve_join_with_roles(uuid, text, text, text, text) to authenticated;
grant execute on function public.request_join_by_email(text, text, text) to authenticated;
grant execute on function public.cancel_join_request(uuid) to authenticated;
grant execute on function public.my_outgoing_requests() to authenticated;
grant execute on function public.set_member_role(uuid, uuid, text, text) to authenticated;
