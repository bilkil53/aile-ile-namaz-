-- (A) Bildirim kuyruğu: cihaz başına teslim kaydı. Bir cihaza gidip diğerine geçici hatayla gidemeyen
-- olay artık "gönderildi" sayılmaz; yeniden denemede yalnızca ulaşmamış cihazlara gönderilir (çift bildirim olmaz).
create table if not exists private.push_deliveries (
  event_id bigint not null references public.pool_events(id) on delete cascade,
  fcm_token text not null,
  delivered_at timestamptz not null default now(),
  primary key (event_id, fcm_token)
);
revoke all on private.push_deliveries from public, anon, authenticated;

create or replace function public.push_delivered_tokens(p_id bigint) returns setof text
language sql stable security definer set search_path = '' as $$
  select fcm_token from private.push_deliveries where event_id = p_id;
$$;
create or replace function public.mark_push_delivered(p_id bigint, p_tokens text[]) returns void
language sql security definer set search_path = '' as $$
  insert into private.push_deliveries (event_id, fcm_token)
  select p_id, t from unnest(p_tokens) t on conflict do nothing;
$$;
revoke all on function public.push_delivered_tokens(bigint) from public, anon, authenticated;
revoke all on function public.mark_push_delivered(bigint, text[]) from public, anon, authenticated;
grant execute on function public.push_delivered_tokens(bigint) to service_role;
grant execute on function public.mark_push_delivered(bigint, text[]) to service_role;

-- (B) Açık rıza: hangi metin sürümüne verildiği de kaydedilir; uygulama rıza durumunu sunucudan sorar
-- (kayıt yoksa ya da metin sürümü eskiyse her açılışta yeniden sorulur).
alter table public.profiles add column if not exists acik_riza_version int;
update public.profiles set acik_riza_version = 1 where acik_riza_at is not null and acik_riza_version is null;

-- Geçerli açık rıza metni sürümü. Metne yeni veri/amaç eklenince artırılır: herkese yeniden sorulur.
create or replace function private.riza_version() returns int language sql immutable set search_path = '' as $$ select 1 $$;
revoke all on function private.riza_version() from public, anon, authenticated;

create or replace function public.record_acik_riza() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update public.profiles set acik_riza_at = now(), acik_riza_version = private.riza_version()
   where id = auth.uid() returning acik_riza_at into v;
  return v;
end $$;

create or replace function public.my_consent_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p record;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select kvkk_consent_at, acik_riza_at, acik_riza_version into p from public.profiles where id = auth.uid();
  return jsonb_build_object(
    'beyan', p.kvkk_consent_at is not null,
    'riza', p.acik_riza_at is not null and coalesce(p.acik_riza_version, 0) >= private.riza_version(),
    'riza_version', coalesce(p.acik_riza_version, 0),
    'gerekli_version', private.riza_version());
end $$;
revoke all on function public.my_consent_status() from public, anon;
grant execute on function public.my_consent_status() to authenticated;
