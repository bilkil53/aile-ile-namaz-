alter table public.profiles add column if not exists kvkk_consent_at timestamptz;
grant update (kvkk_consent_at) on public.profiles to authenticated;
