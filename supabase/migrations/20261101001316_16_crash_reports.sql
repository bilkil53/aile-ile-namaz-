create table if not exists public.crash_reports (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid(),
  app_version text check (char_length(app_version) <= 20),
  build int,
  os text check (char_length(os) <= 200),
  ram_mb int,
  fatal boolean not null default false,
  error text check (char_length(error) <= 2000),
  stack text check (char_length(stack) <= 8000)
);
alter table public.crash_reports enable row level security;
create policy crash_reports_insert on public.crash_reports for insert to anon, authenticated
  with check (user_id is null or user_id = (select auth.uid()));
grant insert on public.crash_reports to anon, authenticated;
grant usage, select on sequence public.crash_reports_id_seq to anon, authenticated;
create index if not exists crash_reports_time_idx on public.crash_reports (created_at desc);
select cron.schedule('aile-crash-cleanup', '40 0 * * *', $job$ delete from public.crash_reports where created_at < now() - interval '30 days'; $job$);
