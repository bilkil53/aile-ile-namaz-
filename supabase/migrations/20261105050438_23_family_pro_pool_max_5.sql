-- Aile Pro'su: reisin (havuz sahibinin) satın aldığı Pro havuzdaki herkese geçer.
-- Deneme (pro_until, 7 gün) kişiye özel kalır. Satın alınan/kodla açılan Pro: pro_paid_until.
alter table public.profiles add column if not exists pro_paid_until timestamptz;

-- Havuz en fazla 5 kişi
create or replace function private.pool_max_members() returns int language sql immutable as $$ select 5 $$;

-- Etkin Pro: kendi denemesi, kendi satın alması, ya da havuz sahibinin satın alması
create or replace function private.pro_status(p_uid uuid)
returns table (eff_until timestamptz, source text, trial_until timestamptz, paid_until timestamptz, family_until timestamptz)
language sql stable security definer set search_path to '' as $$
  with me as (select pro_until, pro_paid_until from public.profiles where id = p_uid),
  fam as (
    select o.pro_paid_until as u
      from public.pool_members m
      join public.pools p on p.id = m.pool_id and p.owner_id <> p_uid
      join public.profiles o on o.id = p.owner_id
     where m.user_id = p_uid
     limit 1)
  select
    greatest(me.pro_until, me.pro_paid_until, (select u from fam)),
    case
      when coalesce(me.pro_paid_until, '-infinity') > now()
           and me.pro_paid_until >= coalesce((select u from fam), '-infinity') then 'paid'
      when coalesce((select u from fam), '-infinity') > now() then 'family'
      when coalesce(me.pro_until, '-infinity') > now() then 'trial'
      else null end,
    me.pro_until, me.pro_paid_until, (select u from fam)
  from me
$$;

create or replace function public.my_pro_status() returns json
language plpgsql stable security definer set search_path to '' as $$
declare r record;
begin
  if auth.uid() is null then return null; end if;
  select * into r from private.pro_status(auth.uid());
  return json_build_object('until', r.eff_until, 'source', r.source,
                           'trial_until', r.trial_until, 'paid_until', r.paid_until, 'family_until', r.family_until);
end $$;
grant execute on function public.my_pro_status() to authenticated;

create or replace function public.ensure_pro_trial() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = now() + interval '7 days' where id = auth.uid() and pro_until is null;
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.redeem_pro_code(p_code text) returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  -- Test aşaması Pro kodu: "1" (gerçek satışta Google Play ödemesine geçilecek)
  if btrim(coalesce(p_code, '')) <> '1' then raise exception 'gecersiz_kod'; end if;
  update public.profiles
     set pro_paid_until = greatest(coalesce(pro_paid_until, now()), now()) + interval '365 days'
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.expire_pro_test() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = now() - interval '1 day', pro_paid_until = null where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

revoke all on function private.pro_status(uuid) from public;
