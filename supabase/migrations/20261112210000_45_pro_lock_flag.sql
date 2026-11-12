-- Sunucuda Pro kilidi (anahtarlı). Anahtar kapalıyken hiçbir şey değişmez (kararlı sürüm etkilenmez).
-- Açıkken: Pro'su (deneme / ödeme / aile) olmayan kişinin aile olayları (kıldı, kaza, dua, 5 vakit)
-- hata vermeden düşer ve ücretsiz kişiye aile bildirimi gönderilmez.
create table if not exists private.flags (key text primary key, value boolean not null default false);
alter table private.flags enable row level security;
revoke all on private.flags from public, anon, authenticated;
insert into private.flags(key, value) values ('pro_enforced', false) on conflict (key) do nothing;

create or replace function private.pro_enforced() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select value from private.flags where key = 'pro_enforced'), false);
$$;
revoke all on function private.pro_enforced() from public, anon, authenticated;

create or replace function private.is_pro(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select eff_until > now() from private.pro_status(p_uid)), false);
$$;
revoke all on function private.is_pro(uuid) from public, anon, authenticated;

-- Aile olayı: rıza yoksa (44) ya da kilit açıkken Pro yoksa sessizce düşer
create or replace function private.pool_events_require_riza() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.event_type in ('PRAYED', 'MISSED', 'KAZA', 'DUA', 'ALL_PRAYED') then
    if not exists (
         select 1 from public.profiles pr
          where pr.id = new.sender_id and pr.acik_riza_at is not null
            and coalesce(pr.acik_riza_version, 0) >= private.riza_version()) then
      return null;
    end if;
    if private.pro_enforced() and not private.is_pro(new.sender_id) then
      return null;
    end if;
  end if;
  return new;
end $$;

-- Bildirim işlevi için: alıcılardan hangilerine aile bildirimi gidebilir (kilit kapalıyken hepsi)
create or replace function public.push_allowed_recipients(p_ids uuid[]) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(x), '{}')
    from unnest(p_ids) x
   where not private.pro_enforced() or private.is_pro(x);
$$;
revoke all on function public.push_allowed_recipients(uuid[]) from public, anon, authenticated;
grant execute on function public.push_allowed_recipients(uuid[]) to service_role;
