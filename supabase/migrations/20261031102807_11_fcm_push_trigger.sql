-- Uygulama kapalıyken aile bildirimleri: pool_events eklenince push-family fonksiyonu çağrılır.
create extension if not exists pg_net with schema extensions;

alter table public.pool_events add column if not exists pushed_at timestamptz;

create or replace function private.notify_push_family()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://tgshrnodnhmnofjhzpqp.supabase.co/functions/v1/push-family',
    body := jsonb_build_object('event_id', new.id),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- Bildirim gönderilemese bile olay kaydı başarısız olmasın
  return new;
end;
$$;

revoke all on function private.notify_push_family() from public, anon, authenticated;

drop trigger if exists pool_events_push on public.pool_events;
create trigger pool_events_push
  after insert on public.pool_events
  for each row execute function private.notify_push_family();
