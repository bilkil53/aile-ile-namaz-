-- Yardımcı fonksiyonlar: API'ye açık olmayan 'private' şemasında
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create function private.is_pool_member(p_pool uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pool_members m
    where m.pool_id = p_pool and m.user_id = (select auth.uid())
  );
$$;

create function private.is_pool_owner(p_pool uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pools p
    where p.id = p_pool and p.owner_id = (select auth.uid())
  );
$$;

create function private.shares_pool_with(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.pool_members a
    join public.pool_members b on a.pool_id = b.pool_id
    where a.user_id = (select auth.uid()) and b.user_id = p_user
  );
$$;

create function private.has_pending_request_to_me(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.join_requests r
    join public.pools p on p.id = r.pool_id
    where r.user_id = p_user and r.status = 'pending' and p.owner_id = (select auth.uid())
  );
$$;

revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Tablo yetkileri: anon hiçbir şey göremez; authenticated sadece gereken sütunlar
revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, icon) on public.profiles to authenticated;

revoke insert, update, delete on public.pools from authenticated;
grant update (name) on public.pools to authenticated;
grant delete on public.pools to authenticated;

revoke insert, update, delete on public.pool_members from authenticated;
grant update (role_title, icon) on public.pool_members to authenticated;

revoke insert, update, delete on public.join_requests from authenticated;
revoke all on public.join_attempts from authenticated;
revoke insert, update, delete on public.kaza_summary from authenticated;

-- RLS politikaları
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_pool_with(id) or private.has_pending_request_to_me(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy pools_select_members on public.pools for select to authenticated
  using (private.is_pool_member(id));
create policy pools_update_owner on public.pools for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy pools_delete_owner on public.pools for delete to authenticated
  using (owner_id = (select auth.uid()));

create policy pool_members_select on public.pool_members for select to authenticated
  using (private.is_pool_member(pool_id));
create policy pool_members_update_own on public.pool_members for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy join_requests_select on public.join_requests for select to authenticated
  using (user_id = (select auth.uid()) or private.is_pool_owner(pool_id));

create policy daily_prayers_select on public.daily_prayers for select to authenticated
  using (user_id = (select auth.uid()) or private.shares_pool_with(user_id));
create policy daily_prayers_insert_own on public.daily_prayers for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy daily_prayers_update_own on public.daily_prayers for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy daily_prayers_delete_own on public.daily_prayers for delete to authenticated
  using (user_id = (select auth.uid()));

create policy kaza_prayers_all_own on public.kaza_prayers for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy kaza_summary_select on public.kaza_summary for select to authenticated
  using (user_id = (select auth.uid()) or private.shares_pool_with(user_id));

create policy pool_events_select on public.pool_events for select to authenticated
  using (private.is_pool_member(pool_id));
create policy pool_events_insert on public.pool_events for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and event_type in ('PRAYED','MISSED','KAZA','DUA')
    and private.is_pool_member(pool_id)
  );

create policy devices_all_own on public.devices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
