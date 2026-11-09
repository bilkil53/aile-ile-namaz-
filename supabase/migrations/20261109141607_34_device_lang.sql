-- Aile bildirimleri alıcının dilinde gitsin: cihaz başına uygulama dili ('tr' / 'en').
-- Eski sürümler bu alanı göndermez → varsayılan Türkçe (geriye uyumlu).
alter table public.devices add column if not exists lang text not null default 'tr';
alter table public.devices drop constraint if exists devices_lang_check;
alter table public.devices add constraint devices_lang_check check (lang in ('tr', 'en'));
