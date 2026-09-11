-- MIGRAZIONE 09 — admin_assegna_agente: errore chiaro se il profilo scelto non è un cliente normale
create or replace function public.admin_assegna_agente(p_cliente_id uuid, p_agente_id uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_agente_id is not null and not exists (select 1 from public.profiles where id = p_agente_id and ruolo = 'agente') then raise exception 'Agente non trovato'; end if;
  select ruolo into r from public.profiles where id = p_cliente_id;
  if r is null then raise exception 'Cliente non trovato'; end if;
  if r = 'admin' then raise exception 'Questo è l''account del titolare: l''agente si collega solo a un cliente vero'; end if;
  if r = 'agente' then raise exception 'Questo account è un agente, non un cliente'; end if;
  update public.profiles set agente_id = p_agente_id, origine = case when p_agente_id is null then origine else 'manuale' end
  where id = p_cliente_id and ruolo = 'cliente';
end $$;
