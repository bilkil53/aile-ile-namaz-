-- TEST işlemleri (yalnızca Namaz Demo test kanalı için; Play'e çıkmadan önce kaldırılacak)
create or replace function public.test_restart_trial() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.profiles set pro_until = now() + interval '7 days', pro_trial_started_at = now(), pro_paid_until = null
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.test_remove_pro() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update public.profiles set pro_paid_until = null where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

grant execute on function public.test_restart_trial() to authenticated;
grant execute on function public.test_remove_pro() to authenticated;
