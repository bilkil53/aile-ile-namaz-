-- Davet kodunu bilen (ya da tahmin eden) biri, istek onaylanmadan havuzun ve Aile Reisinin adını
-- öğrenemesin: bekleyen istek listesi artık ad döndürmez (sütunlar eski uygulamalarla uyum için boş kalır).
create or replace function public.my_outgoing_requests()
returns table (id uuid, pool_name text, owner_name text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select r.id, ''::text, ''::text, r.created_at
    from public.join_requests r
   where r.user_id = (select auth.uid())
     and r.status = 'pending'
     and r.created_at > now() - interval '5 minutes'
   order by r.created_at desc;
$$;
revoke execute on function public.my_outgoing_requests() from public, anon;
grant execute on function public.my_outgoing_requests() to authenticated;
