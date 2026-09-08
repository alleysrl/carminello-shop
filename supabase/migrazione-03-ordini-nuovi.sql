-- ============================================================================
-- MIGRAZIONE 03 — ordini "nuovi" (non ancora visti) e aggiornamenti in tempo reale
-- ============================================================================
alter table public.orders add column if not exists visto boolean not null default false;
update public.orders set visto = true where visto = false and created_at < now() - interval '1 day';

create or replace function public.admin_segna_ordini_visti(p_ids uuid[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  update public.orders set visto = true where id = any(p_ids) and visto = false;
end $$;
grant execute on function public.admin_segna_ordini_visti(uuid[]) to authenticated;

-- Tempo reale: la dashboard viene avvisata subito quando arriva un ordine
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders') then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;
