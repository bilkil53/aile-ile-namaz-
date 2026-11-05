-- Kişinin hangi aile bildirimlerini alacağı ve kilit ekranında içerik görünürlüğü (cihaz başına)
alter table public.devices
  add column if not exists notify_prayer boolean not null default true,
  add column if not exists notify_kaza boolean not null default true,
  add column if not exists notify_dua boolean not null default true,
  add column if not exists lock_screen boolean not null default true;
