-- Reis, gelen Pro isteğini reddedebilir; isteyene bilgi gider.
alter table public.pool_events drop constraint pool_events_event_type_check;
alter table public.pool_events add constraint pool_events_event_type_check
  check (event_type = any (array['PRAYED','MISSED','KAZA','DUA','MEMBER_JOINED','MEMBER_LEFT','PRO_REQUEST','PRO_DECLINED']));

create or replace function public.decline_pro_request(p_member uuid) returns void
language plpgsql security definer set search_path to '' as $$
declare v_uid uuid := auth.uid(); v_pool uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select p.id into v_pool from public.pools p
    join public.pool_members m on m.pool_id = p.id and m.user_id = p_member
   where p.owner_id = v_uid limit 1;
  if v_pool is null then raise exception 'not_pool_owner' using errcode = '42501'; end if;
  insert into public.pool_events (pool_id, sender_id, event_type, target_id)
  values (v_pool, v_uid, 'PRO_DECLINED', p_member);
end $$;
grant execute on function public.decline_pro_request(uuid) to authenticated;
