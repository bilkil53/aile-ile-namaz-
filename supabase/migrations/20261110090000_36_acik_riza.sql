-- Özel nitelikli kişisel veriler (namaz/kaza kayıtları, dua mesajları — din bilgisi, KVKK md. 6) için
-- açık rıza tarihi. Aydınlatma "okudum" beyanından (kvkk_consent_at) ayrı tutulur (Kurul İlke Kararı 2026/347).
-- Tarih istemciden alınmaz: yalnızca sunucu saati yazılır (geriye ya da ileriye tarih atılamaz).
alter table public.profiles add column if not exists acik_riza_at timestamptz;

create or replace function public.record_acik_riza() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update public.profiles set acik_riza_at = now() where id = auth.uid() returning acik_riza_at into v;
  return v;
end $$;
revoke all on function public.record_acik_riza() from public, anon;
grant execute on function public.record_acik_riza() to authenticated;
