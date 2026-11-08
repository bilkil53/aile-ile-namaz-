-- Gezinti (misafir) modu artık yalnızca görüntüleme: kayıt tutulmaz, giriş sonrası aktarım yok (r78).
-- Misafir kaza aktarımı fonksiyonu ve tekrar koruma tablosu kullanılmıyor; kaldırılır.
drop function if exists public.merge_guest_kaza(text, jsonb);
drop table if exists public.guest_merges;
