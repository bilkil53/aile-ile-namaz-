-- Herkesin kendi havuzu ve davet kodu otomatik hazır (v1.14: manuel havuz başlatma yok).
create function public.ensure_my_pool() returns uuid
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
  select coalesce(nullif(split_part(display_name, ' ', 1), ''), 'Benim') into v_name
    from public.profiles where id = v_uid;
  loop
    v_code := private.gen_invite_code();
    exit when not exists (select 1 from public.pools where invite_code = v_code);
  end loop;
  insert into public.pools (name, owner_id, invite_code)
  values (left(coalesce(v_name, 'Benim') || ' Ailesi', 60), v_uid, v_code) returning id into v_pool;
  insert into public.pool_members (pool_id, user_id, role_title, icon) values (v_pool, v_uid, 'Aile Reisi', '👑');
  return v_pool;
end;
$$;
revoke execute on function public.ensure_my_pool() from public, anon;
grant execute on function public.ensure_my_pool() to authenticated;

-- Onaylanınca katılanın kendi boş (tek kişilik) havuzu silinir; tek aile görünür.
create or replace function public.approve_join_with_roles(
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
  v_role text;
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
  v_role := left(trim(coalesce(nullif(p_member_role, ''), r.role_title)), 30);
  insert into public.pool_members (pool_id, user_id, role_title, icon)
  values (r.pool_id, r.user_id, v_role, left(coalesce(nullif(p_member_icon, ''), r.icon), 16))
  on conflict (pool_id, user_id) do update set role_title = excluded.role_title, icon = excluded.icon;
  update public.join_requests set status = 'approved', decided_at = now() where id = r.id;
  -- Katılanın içinde kendinden başka kimse olmayan kendi havuzlarını kaldır
  delete from public.pools p
   where p.owner_id = r.user_id
     and p.id <> r.pool_id
     and not exists (select 1 from public.pool_members m where m.pool_id = p.id and m.user_id <> r.user_id);
  insert into public.pool_events (pool_id, sender_id, event_type, message)
  values (r.pool_id, r.user_id, 'MEMBER_JOINED', v_role);
end;
$$;

-- Ayrılan veya çıkarılan kişi tekrar kendi havuzuyla devam etsin diye istemci ensure_my_pool çağırır.
