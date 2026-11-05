-- Misafir kaza sayılarının hesaba aktarımı: tek işlem (ya hepsi ya hiçbiri) + tekrar koruması.
-- Aynı aktarım kimliği ikinci kez gelirse (bağlantı koptu, tekrar denendi) hiçbir şey eklenmez.
create table if not exists public.guest_merges (
  user_id uuid not null references auth.users(id) on delete cascade,
  merge_id text not null check (char_length(merge_id) between 8 and 64),
  created_at timestamptz not null default now(),
  primary key (user_id, merge_id)
);
alter table public.guest_merges enable row level security;  -- politika yok: yalnızca aşağıdaki fonksiyon yazar
revoke all on public.guest_merges from anon, authenticated;

create or replace function public.merge_guest_kaza(p_merge_id text, p_items jsonb)
returns boolean language plpgsql security definer set search_path to '' as $$
declare
  v_uid uuid := auth.uid();
  k text; v jsonb; o int; c int;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if jsonb_typeof(p_items) is distinct from 'object' then raise exception 'invalid_items' using errcode = '22023'; end if;
  insert into public.guest_merges (user_id, merge_id) values (v_uid, p_merge_id) on conflict do nothing;
  if not found then return false; end if;  -- bu aktarım daha önce yapıldı
  for k, v in select * from jsonb_each(p_items) loop
    if k not in ('FAJR','DHUHR','ASR','MAGHRIB','ISHA','WITR') then raise exception 'invalid_type' using errcode = '22023'; end if;
    o := (v->>0)::int; c := (v->>1)::int;
    if o is null or c is null or o < 0 or c < 0 or o > 100000 or c > 100000 then
      raise exception 'invalid_count' using errcode = '22023';
    end if;
    insert into public.kaza_prayers (user_id, prayer_type, owed_count, completed_count, updated_at)
    values (v_uid, k, o, c, now())
    on conflict (user_id, prayer_type) do update
      set owed_count = public.kaza_prayers.owed_count + excluded.owed_count,
          completed_count = public.kaza_prayers.completed_count + excluded.completed_count,
          updated_at = now();
  end loop;
  return true;
end $$;
revoke all on function public.merge_guest_kaza(text, jsonb) from public, anon;
grant execute on function public.merge_guest_kaza(text, jsonb) to authenticated;
