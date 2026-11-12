-- Açık rıza kaydı, kullanıcının GÖRDÜĞÜ metin sürümüyle yazılır.
-- Sorun: rıza internet yokken verilir, telefon bekletir; bu arada sunucuda metin yeni sürüme geçerse
-- eski kayıt (eski metin okunmuşken) yeni sürüm diye yazılıyordu.
-- Çözüm: uygulama okuttuğu metnin sürümünü gönderir; güncel sürümden eskiyse kayıt yazılmaz (null
-- döner) ve uygulama pencereyi yeni metinle yeniden açar.

create or replace function public.record_acik_riza(p_version integer) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_version is null or p_version < private.riza_version() then return null; end if;
  update public.profiles set acik_riza_at = now(), acik_riza_version = private.riza_version()
   where id = auth.uid() returning acik_riza_at into v;
  return v;
end $$;
revoke all on function public.record_acik_riza(integer) from public, anon;
grant execute on function public.record_acik_riza(integer) to authenticated;

-- Eski uygulamalar sürüm göndermez; onlar 1. sürüm metni gösterir. Kayıt o sürümle yazılır
-- (metin ileride 2'ye geçerse eski uygulamadaki rıza geçerli sayılmaz, yeniden sorulur).
create or replace function public.record_acik_riza() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare v timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  update public.profiles set acik_riza_at = now(), acik_riza_version = 1
   where id = auth.uid() returning acik_riza_at into v;
  return v;
end $$;
revoke all on function public.record_acik_riza() from public, anon;
grant execute on function public.record_acik_riza() to authenticated;
