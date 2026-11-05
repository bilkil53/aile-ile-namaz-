-- Deneme başlangıcı ayrıca tutulur (TEST "demo süresini bitir" bitişi değiştirse de başlangıç bozulmaz)
alter table public.profiles add column if not exists pro_trial_started_at timestamptz;

-- Mevcutlar: deneme özelliği 04.11.2026 16:57 (İstanbul) yayınlandı; ondan önce başlamış olamaz
update public.profiles
   set pro_trial_started_at = case
         when pro_until - interval '7 days' >= timestamptz '2026-11-04 13:57:00+00' then pro_until - interval '7 days'
         else greatest(created_at, timestamptz '2026-11-04 13:57:00+00') end
 where pro_until is not null and pro_trial_started_at is null;

create or replace function public.ensure_pro_trial() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = now() + interval '7 days', pro_trial_started_at = now()
   where id = auth.uid() and pro_until is null;
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;

create or replace function public.my_pro_status() returns json
language plpgsql stable security definer set search_path to '' as $$
declare r record; v_start timestamptz;
begin
  if auth.uid() is null then return null; end if;
  select * into r from private.pro_status(auth.uid());
  select pro_trial_started_at into v_start from public.profiles where id = auth.uid();
  return json_build_object('until', r.eff_until, 'source', r.source, 'trial_started', v_start,
                           'trial_until', r.trial_until, 'paid_until', r.paid_until, 'family_until', r.family_until);
end $$;
