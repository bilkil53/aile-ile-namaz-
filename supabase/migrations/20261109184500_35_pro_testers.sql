-- Pro test işlemleri yalnızca test listesindeki hesaplara açık.
-- Önceden giriş yapan herkes test fonksiyonlarıyla kendine deneme / Pro verebiliyordu ve Pro kodu ("1")
-- herkeste çalışıyordu. Artık:
--   * test_restart_trial, test_remove_pro, expire_pro_test, redeem_pro_code yalnızca listedekilere
--     çalışır; diğerleri 'not_tester' (42501, yetki yok) hatası alır.
--   * Listedekiler kod girmeden Pro'ya geçer (kod parametresi eski sürümler için kalır, bakılmaz).
-- Liste (kullanıcı kimlikleri) bu dosyada değil, veritabanında tutulur: kimlikler herkese açık depoya
-- yazılmaz. Play'e / ücretli Pro'ya geçmeden önce bu fonksiyonlar tamamen kaldırılacak.

create table if not exists private.pro_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table private.pro_testers enable row level security;
revoke all on private.pro_testers from public, anon, authenticated;

create or replace function private.is_pro_tester(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_uid is not null and exists (select 1 from private.pro_testers t where t.user_id = p_uid)
$$;
revoke all on function private.is_pro_tester(uuid) from public, anon, authenticated;

-- Uygulama test panelini yalnızca listedekilere gösterir (yetki sunucuda ayrıca denetlenir).
create or replace function public.am_i_pro_tester() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_pro_tester(auth.uid())
$$;
revoke all on function public.am_i_pro_tester() from public, anon;
grant execute on function public.am_i_pro_tester() to authenticated;

create or replace function public.test_restart_trial() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not private.is_pro_tester(auth.uid()) then raise exception 'not_tester' using errcode = '42501'; end if;
  update public.profiles set pro_until = now() + interval '7 days', pro_trial_started_at = now(), pro_paid_until = null
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.test_remove_pro() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not private.is_pro_tester(auth.uid()) then raise exception 'not_tester' using errcode = '42501'; end if;
  update public.profiles set pro_paid_until = null where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.expire_pro_test() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not private.is_pro_tester(auth.uid()) then raise exception 'not_tester' using errcode = '42501'; end if;
  update public.profiles set pro_until = least(pro_until, now() - interval '1 second'), pro_paid_until = null
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.redeem_pro_code(p_code text) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if not private.is_pro_tester(auth.uid()) then raise exception 'not_tester' using errcode = '42501'; end if;
  if private.is_non_reis_member(auth.uid()) then raise exception 'only_reis'; end if;
  update public.profiles
     set pro_paid_until = greatest(coalesce(pro_paid_until, now()), now()) + interval '365 days'
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

revoke all on function public.test_restart_trial() from public, anon;
revoke all on function public.test_remove_pro() from public, anon;
revoke all on function public.expire_pro_test() from public, anon;
revoke all on function public.redeem_pro_code(text) from public, anon;
grant execute on function public.test_restart_trial() to authenticated;
grant execute on function public.test_remove_pro() to authenticated;
grant execute on function public.expire_pro_test() to authenticated;
grant execute on function public.redeem_pro_code(text) to authenticated;
