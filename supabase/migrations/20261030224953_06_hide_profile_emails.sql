-- E-posta adresleri diğer kullanıcılara hiçbir şekilde dönmesin (sütun düzeyinde yetki).
revoke select on public.profiles from authenticated;
grant select (id, display_name, icon, created_at) on public.profiles to authenticated;
