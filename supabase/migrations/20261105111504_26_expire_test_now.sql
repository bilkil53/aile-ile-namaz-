-- TEST düğmesi bitişi "dün" yapıyordu; gerçek basılma anı görünsün diye "şimdi" yapar.
update public.profiles set pro_until = pro_until + interval '1 day'
 where pro_until is not null and pro_trial_started_at is not null and pro_until < pro_trial_started_at;

create or replace function public.expire_pro_test() returns timestamptz
language plpgsql security definer set search_path to 'public' as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = least(pro_until, now() - interval '1 second'), pro_paid_until = null
   where id = auth.uid();
  select eff_until into v from private.pro_status(auth.uid());
  return v;
end $$;
