alter policy pool_events_select on public.pool_events
  using (private.is_pool_member(pool_id) and (target_id is null or target_id = (select auth.uid()) or sender_id = (select auth.uid())));
