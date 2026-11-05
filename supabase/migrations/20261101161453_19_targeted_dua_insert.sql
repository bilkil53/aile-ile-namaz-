alter policy pool_events_insert on public.pool_events
  with check (sender_id = (select auth.uid())
    and event_type = any (array['PRAYED','MISSED','KAZA','DUA'])
    and private.is_pool_member(pool_id)
    and (target_id is null or (event_type = 'DUA' and target_id <> sender_id
         and exists (select 1 from public.pool_members pm where pm.pool_id = pool_events.pool_id and pm.user_id = pool_events.target_id))));
