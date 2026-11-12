-- my_consent_status: profil satırı var mı ve rıza tarihleri de döner.
-- (Rıza sütunlarına doğrudan okuma izni yok; "Verilerimi indir" tarihleri buradan alır.)
create or replace function public.my_consent_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p record; found_row boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  select kvkk_consent_at, acik_riza_at, acik_riza_version into p from public.profiles where id = auth.uid();
  found_row := found;
  return jsonb_build_object(
    'profil', found_row,
    'beyan', p.kvkk_consent_at is not null,
    'riza', p.acik_riza_at is not null and coalesce(p.acik_riza_version, 0) >= private.riza_version(),
    'riza_version', coalesce(p.acik_riza_version, 0),
    'gerekli_version', private.riza_version(),
    'beyan_at', p.kvkk_consent_at,
    'riza_at', p.acik_riza_at);
end $$;
revoke all on function public.my_consent_status() from public, anon;
grant execute on function public.my_consent_status() to authenticated;
