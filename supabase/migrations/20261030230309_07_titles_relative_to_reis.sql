-- Unvanlar Aile Reisine göredir; reisin unvanı sabit "Aile Reisi".
create or replace function public.set_member_role(p_pool uuid, p_user uuid, p_role text, p_icon text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select owner_id into v_owner from public.pools where id = p_pool;
  if v_owner is null or v_owner <> auth.uid() then
    raise exception 'not_pool_owner' using errcode = '42501';
  end if;
  if p_user = v_owner then
    -- Reisin unvanı değişmez; sadece simgesi
    update public.pool_members set icon = left(p_icon, 16) where pool_id = p_pool and user_id = p_user;
  else
    update public.pool_members
       set role_title = left(trim(p_role), 30), icon = left(p_icon, 16)
     where pool_id = p_pool and user_id = p_user;
  end if;
end;
$$;

-- Reislik devrinde unvanlar da devredilir; yeni reis eski reisin unvanını sonra belirler.
create or replace function public.transfer_ownership(p_pool uuid, p_new_owner uuid) returns void
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
  update public.pool_members set role_title = 'Aile Reisi', icon = '👑' where pool_id = p_pool and user_id = p_new_owner;
  update public.pool_members set role_title = 'Aile Ferdi', icon = '👥' where pool_id = p_pool and user_id = v_uid;
end;
$$;

-- Mevcut reislerin unvanını sabitle
update public.pool_members m set role_title = 'Aile Reisi'
  from public.pools p where p.id = m.pool_id and p.owner_id = m.user_id and m.role_title <> 'Aile Reisi';
