-- Pro / Demo altyapısı: pro_until (Pro bitiş tarihi). Doğrudan yazılamaz; RPC'lerle yönetilir.
alter table public.profiles add column if not exists pro_until timestamptz;

-- 7 günlük deneme: ilk çağrıda pro_until boşsa bugün + 7 gün yapılır.
create or replace function public.ensure_pro_trial()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = now() + interval '7 days'
    where id = auth.uid() and pro_until is null
    returning pro_until into v;
  if v is null then select pro_until into v from public.profiles where id = auth.uid(); end if;
  return v;
end $$;

-- Pro kodu: doğru kod girilince 1 yıl Pro. Kod sunucuda saklanır (APK'da değil).
create or replace function public.redeem_pro_code(p_code text)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v timestamptz;
begin
  if upper(btrim(p_code)) <> 'AILE-PRO-2026' then
    raise exception 'gecersiz_kod';
  end if;
  update public.profiles set pro_until = greatest(coalesce(pro_until, now()), now()) + interval '365 days'
    where id = auth.uid() returning pro_until into v;
  return v;
end $$;

-- Test tuşu: demo süresini hemen bitirir (geçici, test için).
create or replace function public.expire_pro_test()
returns timestamptz language plpgsql security definer set search_path = public as $$
declare v timestamptz;
begin
  update public.profiles set pro_until = now() - interval '1 day'
    where id = auth.uid() returning pro_until into v;
  return v;
end $$;

revoke all on function public.ensure_pro_trial() from public, anon;
revoke all on function public.redeem_pro_code(text) from public, anon;
revoke all on function public.expire_pro_test() from public, anon;
grant execute on function public.ensure_pro_trial() to authenticated;
grant execute on function public.redeem_pro_code(text) to authenticated;
grant execute on function public.expire_pro_test() to authenticated;
