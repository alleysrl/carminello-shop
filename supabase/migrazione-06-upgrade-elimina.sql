-- MIGRAZIONE 06 — un privato può chiedere di diventare locale/rivenditore; l'admin può eliminare un cliente
create or replace function public.richiedi_tipo_azienda(p_tipo text, p_dati jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Non collegato'; end if;
  if p_tipo not in ('b2b','rivenditore') then raise exception 'Tipo non valido'; end if;
  if coalesce(p_dati->>'piva','') = '' or coalesce(p_dati->>'ragione_sociale','') = '' then raise exception 'Servono Partita IVA e ragione sociale'; end if;
  update public.profiles set
    tipo = p_tipo, approvato = false,
    ragione_sociale = p_dati->>'ragione_sociale', piva = p_dati->>'piva',
    sdi = nullif(p_dati->>'sdi',''), pec = nullif(p_dati->>'pec',''),
    indirizzo = case when jsonb_typeof(p_dati->'indirizzo') = 'object' then p_dati->'indirizzo' else indirizzo end
  where id = auth.uid();
end $$;
grant execute on function public.richiedi_tipo_azienda(text, jsonb) to authenticated;

-- Elimina un cliente con tutto quello che lo riguarda (ordini compresi). Solo amministratore, mai se stesso.
create or replace function public.admin_elimina_cliente(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_user_id = auth.uid() then raise exception 'Non puoi eliminare il tuo account'; end if;
  delete from public.note_clienti where user_id = p_user_id;
  delete from public.push_subscriptions where user_id = p_user_id;
  delete from public.prezzi_cliente where user_id = p_user_id;
  delete from public.orders where user_id = p_user_id;
  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;
end $$;
grant execute on function public.admin_elimina_cliente(uuid) to authenticated;
