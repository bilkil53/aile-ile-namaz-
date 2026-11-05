-- Katılım sadece reis davet koduyla; e-posta ile katılma kaldırıldı.
drop function if exists public.request_join_by_email(text, text, text);
