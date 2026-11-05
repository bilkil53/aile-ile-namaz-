create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;

-- Kullanıcı profilleri (auth.users ile 1-1)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 60),
  email text not null default '',
  icon text not null default '' check (char_length(icon) <= 16),
  created_at timestamptz not null default now()
);

-- Havuzlar (aileler). owner_id = havuzu yöneten tek kişi.
create table public.pools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  owner_id uuid not null references public.profiles(id),
  invite_code text not null unique,
  created_at timestamptz not null default now()
);
create index pools_owner_idx on public.pools(owner_id);

create table public.pool_members (
  pool_id uuid not null references public.pools(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_title text not null default 'Aile Ferdi' check (char_length(role_title) between 1 and 30),
  icon text not null default '👥' check (char_length(icon) <= 16),
  joined_at timestamptz not null default now(),
  primary key (pool_id, user_id)
);
create index pool_members_user_idx on public.pool_members(user_id);

create table public.join_requests (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.pools(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_title text not null default 'Aile Ferdi' check (char_length(role_title) between 1 and 30),
  icon text not null default '👥' check (char_length(icon) <= 16),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create unique index join_requests_one_pending on public.join_requests(pool_id, user_id) where status = 'pending';
create index join_requests_pool_idx on public.join_requests(pool_id);
create index join_requests_user_idx on public.join_requests(user_id);

-- Kod tahmin denemelerini sınırlamak için
create table public.join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_time_idx on public.join_attempts(user_id, attempted_at desc);

-- Günlük namaz durumları (kişiye ait, havuz üyeleri görebilir)
create table public.daily_prayers (
  user_id uuid not null references public.profiles(id) on delete cascade,
  prayer_date date not null,
  fajr text not null default 'NONE' check (fajr in ('NONE','PRAYED','MISSED','EXCUSED')),
  dhuhr text not null default 'NONE' check (dhuhr in ('NONE','PRAYED','MISSED','EXCUSED')),
  asr text not null default 'NONE' check (asr in ('NONE','PRAYED','MISSED','EXCUSED')),
  maghrib text not null default 'NONE' check (maghrib in ('NONE','PRAYED','MISSED','EXCUSED')),
  isha text not null default 'NONE' check (isha in ('NONE','PRAYED','MISSED','EXCUSED')),
  note text not null default '' check (char_length(note) <= 500),
  updated_at timestamptz not null default now(),
  primary key (user_id, prayer_date)
);

-- Kaza detayı: SADECE sahibi görür (hangi vaktin kaza olduğu gizli kalır)
create table public.kaza_prayers (
  user_id uuid not null references public.profiles(id) on delete cascade,
  prayer_type text not null check (prayer_type in ('FAJR','DHUHR','ASR','MAGHRIB','ISHA','WITR')),
  owed_count int not null default 0 check (owed_count >= 0),
  completed_count int not null default 0 check (completed_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, prayer_type)
);

-- Kaza özeti: havuz üyeleri sadece toplamı görür
create table public.kaza_summary (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  owed int not null default 0,
  completed int not null default 0,
  updated_at timestamptz not null default now()
);

-- Havuz olayları ("kıldı", "kaza etti", dua...). Push bildirimi bunlardan üretilecek.
create table public.pool_events (
  id bigint generated always as identity primary key,
  pool_id uuid not null references public.pools(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('PRAYED','MISSED','KAZA','DUA','MEMBER_JOINED','MEMBER_LEFT')),
  prayer text check (prayer is null or prayer in ('FAJR','DHUHR','ASR','MAGHRIB','ISHA','WITR')),
  message text not null default '' check (char_length(message) <= 280),
  created_at timestamptz not null default now()
);
create index pool_events_pool_time_idx on public.pool_events(pool_id, created_at desc);
create index pool_events_sender_idx on public.pool_events(sender_id);

-- Push için cihaz token'ları (sadece sahibi)
create table public.devices (
  user_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null check (char_length(fcm_token) between 20 and 4096),
  platform text not null check (platform in ('android','ios')),
  updated_at timestamptz not null default now(),
  primary key (user_id, fcm_token)
);

alter table public.profiles enable row level security;
alter table public.pools enable row level security;
alter table public.pool_members enable row level security;
alter table public.join_requests enable row level security;
alter table public.join_attempts enable row level security;
alter table public.daily_prayers enable row level security;
alter table public.kaza_prayers enable row level security;
alter table public.kaza_summary enable row level security;
alter table public.pool_events enable row level security;
alter table public.devices enable row level security;
