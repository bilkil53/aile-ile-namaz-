-- Cinsiyet (Muaf seçeneği için) ünvanla birlikte Aile Reisi tarafından verilir
alter table public.pool_members add column if not exists gender text check (gender in ('m', 'f'));

drop function if exists public.approve_join_with_roles(uuid, text, text, text, text);
create function public.approve_join_with_roles(
  p_request uuid, p_member_role text, p_member_icon text,
  p_owner_role text default null, p_owner_icon text default null,
  p_member_gender text default null, p_owner_gender text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
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
  delete from public.pools p
   where p.owner_id = r.user_id and p.id <> r.pool_id
     and not exists (select 1 from public.pool_members m where m.pool_id = p.id and m.user_id <> r.user_id);
  insert into public.pool_events (pool_id, sender_id, event_type, message) values (r.pool_id, r.user_id, 'MEMBER_JOINED', v_role);
end;
$function$;

drop function if exists public.set_member_role(uuid, uuid, text, text);
create function public.set_member_role(p_pool uuid, p_user uuid, p_role text, p_icon text, p_gender text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select owner_id into v_owner from public.pools where id = p_pool;
  if v_owner is null or v_owner <> auth.uid() then raise exception 'not_pool_owner' using errcode = '42501'; end if;
  if p_user = v_owner then
    update public.pool_members
       set role_title = case when p_role in ('Aile Reisi','Baba','Anne') then p_role else role_title end,
           icon = left(p_icon, 16),
           gender = case when p_gender in ('m','f') then p_gender else gender end
     where pool_id = p_pool and user_id = p_user;
  else
    update public.pool_members
       set role_title = left(trim(p_role), 30), icon = left(p_icon, 16),
           gender = case when p_gender in ('m','f') then p_gender else gender end
     where pool_id = p_pool and user_id = p_user;
  end if;
end;
$function$;

revoke all on function public.approve_join_with_roles(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function public.approve_join_with_roles(uuid, text, text, text, text, text, text) to authenticated;
revoke all on function public.set_member_role(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.set_member_role(uuid, uuid, text, text, text) to authenticated;

update public.pool_members set gender = 'm' where gender is null and role_title in ('Aile Reisi','Baba','Oğlu','Babası','Dedesi','Damadı');
update public.pool_members set gender = 'f' where gender is null and role_title in ('Anne','Kızı','Annesi','Ninesi','Gelini');
