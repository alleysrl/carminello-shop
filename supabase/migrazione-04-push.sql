-- ============================================================================
-- MIGRAZIONE 04 — notifiche push (telefono/Mac) per l'amministratore
-- ============================================================================
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  sub        jsonb not null,               -- l'abbonamento completo restituito dal browser
  dispositivo text,
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists push_admin_read on public.push_subscriptions;
create policy push_admin_read on public.push_subscriptions for select using (user_id = auth.uid() and public.is_admin());
grant select on public.push_subscriptions to authenticated;

create or replace function public.admin_salva_push(p_sub jsonb, p_dispositivo text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  insert into public.push_subscriptions (endpoint, user_id, sub, dispositivo)
  values (p_sub->>'endpoint', auth.uid(), p_sub, p_dispositivo)
  on conflict (endpoint) do update set sub = excluded.sub, user_id = excluded.user_id, dispositivo = excluded.dispositivo;
end $$;
create or replace function public.admin_rimuovi_push(p_endpoint text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
end $$;
grant execute on function public.admin_salva_push(jsonb, text) to authenticated;
grant execute on function public.admin_rimuovi_push(text) to authenticated;
