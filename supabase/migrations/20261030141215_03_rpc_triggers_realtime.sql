-- Yeni kullanıcı -> profil
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    left(coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(coalesce(new.email, ''), '@', 1)), 60)
  );
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- Kaza özeti otomatik güncelleme
create function private.refresh_kaza_summary() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := coalesce(new.user_id, old.user_id);
begin
  insert into public.kaza_summary (user_id, owed, completed, updated_at)
  select v_user, coalesce(sum(owed_count), 0), coalesce(sum(completed_count), 0), now()
  from public.kaza_prayers where user_id = v_user
  on conflict (user_id) do update
    set owed = excluded.owed, completed = excluded.completed, updated_at = now();
  return null;
end;
$$;
create trigger kaza_prayers_summary after insert or update or delete on public.kaza_prayers
  for each row execute function private.refresh_kaza_summary();

-- Davet kodu üretici (8 karakter, karışabilecek harfler yok)
create function private.gen_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(8);
  result text := '';
  i int;
begin
  for i in 0..7 loop
    result := result || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return result;
end;
$$;

-- Havuz oluştur (oluşturan = yönetici)
create function public.create_pool(p_name text, p_role_title text default 'Aile Reisi', p_icon text default '👑')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_pool uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if (select count(*) from public.pools where owner_id = v_uid) >= 3 then
    raise exception 'pool_limit_reached' using errcode = 'P0001';
  end if;
  loop
    v_code := private.gen_invite_code();
    exit when not exists (select 1 from public.pools where invite_code = v_code);
  end loop;
  insert into public.pools (name, owner_id, invite_code)
  values (trim(p_name), v_uid, v_code) returning id into v_pool;
  insert into public.pool_members (pool_id, user_id, role_title, icon)
  values (v_pool, v_uid, left(trim(p_role_title), 30), left(p_icon, 16));
  return v_pool;
end;
$$;

-- Kodla katılma isteği (geçersiz kodda null döner; saatte en fazla 20 deneme)
create function public.request_join(p_code text, p_role_title text default 'Aile Ferdi', p_icon text default '👥')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_pool uuid;
  v_req uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
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
  values (v_pool, v_uid, left(trim(p_role_title), 30), left(p_icon, 16))
  on conflict (pool_id, user_id) where status = 'pending'
  do update set role_title = excluded.role_title, icon = excluded.icon
  returning id into v_req;
  return v_req;
end;
$$;

create function public.approve_join(p_request uuid) returns void
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
  insert into public.pool_members (pool_id, user_id, role_title, icon)
  values (r.pool_id, r.user_id, r.role_title, r.icon)
  on conflict (pool_id, user_id) do nothing;
  update public.join_requests set status = 'approved', decided_at = now() where id = r.id;
  insert into public.pool_events (pool_id, sender_id, event_type, message)
  values (r.pool_id, r.user_id, 'MEMBER_JOINED', r.role_title);
end;
$$;

create function public.reject_join(p_request uuid) returns void
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
  update public.join_requests set status = 'rejected', decided_at = now() where id = r.id;
end;
$$;

create function public.leave_pool(p_pool uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if exists (select 1 from public.pools where id = p_pool and owner_id = v_uid) then
    raise exception 'owner_cannot_leave' using errcode = 'P0001';
  end if;
  delete from public.pool_members where pool_id = p_pool and user_id = v_uid returning role_title into v_role;
  if not found then raise exception 'not_a_member' using errcode = 'P0001'; end if;
  insert into public.pool_events (pool_id, sender_id, event_type, message)
  values (p_pool, v_uid, 'MEMBER_LEFT', v_role);
end;
$$;

create function public.remove_member(p_pool uuid, p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from public.pools where id = p_pool and owner_id = v_uid) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  if p_user = v_uid then raise exception 'owner_cannot_leave' using errcode = 'P0001'; end if;
  delete from public.pool_members where pool_id = p_pool and user_id = p_user;
end;
$$;

create function public.transfer_ownership(p_pool uuid, p_new_owner uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from public.pools where id = p_pool and owner_id = v_uid) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  if not exists (select 1 from public.pool_members where pool_id = p_pool and user_id = p_new_owner) then
    raise exception 'new_owner_not_member' using errcode = 'P0001';
  end if;
  update public.pools set owner_id = p_new_owner where id = p_pool;
end;
$$;

create function public.regenerate_invite_code(p_pool uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from public.pools where id = p_pool and owner_id = v_uid) then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  loop
    v_code := private.gen_invite_code();
    exit when not exists (select 1 from public.pools where invite_code = v_code);
  end loop;
  update public.pools set invite_code = v_code where id = p_pool;
  return v_code;
end;
$$;

-- RPC'leri sadece giriş yapmış kullanıcılar çağırabilir
revoke execute on function public.create_pool(text, text, text) from public, anon;
revoke execute on function public.request_join(text, text, text) from public, anon;
revoke execute on function public.approve_join(uuid) from public, anon;
revoke execute on function public.reject_join(uuid) from public, anon;
revoke execute on function public.leave_pool(uuid) from public, anon;
revoke execute on function public.remove_member(uuid, uuid) from public, anon;
revoke execute on function public.transfer_ownership(uuid, uuid) from public, anon;
revoke execute on function public.regenerate_invite_code(uuid) from public, anon;
grant execute on function public.create_pool(text, text, text) to authenticated;
grant execute on function public.request_join(text, text, text) to authenticated;
grant execute on function public.approve_join(uuid) to authenticated;
grant execute on function public.reject_join(uuid) to authenticated;
grant execute on function public.leave_pool(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.transfer_ownership(uuid, uuid) to authenticated;
grant execute on function public.regenerate_invite_code(uuid) to authenticated;

-- Canlı güncellemeler (uygulama açıkken anlık bildirim)
alter publication supabase_realtime add table
  public.pool_events, public.daily_prayers, public.join_requests, public.pool_members, public.kaza_summary;
