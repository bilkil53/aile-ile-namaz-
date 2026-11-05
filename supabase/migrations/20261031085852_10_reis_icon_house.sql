do $$
declare r record; d text;
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname in ('public','private') and p.prokind='f'
             and p.proname in ('create_pool','transfer_ownership','approve_join_with_roles','delete_my_account') loop
    d := pg_get_functiondef(r.oid);
    if position('👑' in d) > 0 then
      execute replace(d, '👑', '🏡');
    end if;
  end loop;
end $$;
update public.pool_members set icon = '🏡' where icon = '👑';
update public.join_requests set icon = '🏡' where icon = '👑';
