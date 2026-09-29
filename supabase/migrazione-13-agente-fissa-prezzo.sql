-- ============================================================================
-- MIGRAZIONE 13 — L'AGENTE FISSA IL PREZZO E ATTIVA IL CLIENTE
-- ----------------------------------------------------------------------------
-- Prima: l'agente registrava il cliente e poi aspettava che il titolare
-- concordasse il prezzo e lo attivasse. Ora fa tutto lui.
--
-- Unico limite: le basi costano 1,70 € l'una e si vendono a cartoni, quindi il
-- prezzo di un cartone non può scendere sotto 1,70 € × le basi che contiene
-- (cartone da 20 = 34,00 €). Sopra quella soglia l'agente è libero: se è bravo
-- vende a 35,00 €. Sotto, il sistema blocca il salvataggio.
--
-- Il limite sta QUI nel database, non solo nell'app: così vale anche se
-- qualcuno prova a scavalcare la pagina.
-- Si può rilanciare senza danni.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Chi ha fissato il prezzo, chi ha attivato, chi ha sospeso
-- ---------------------------------------------------------------------------
alter table public.prezzi_cliente add column if not exists aggiornato_da uuid references public.profiles(id) on delete set null;
alter table public.prezzi_cliente add column if not exists aggiornato_il timestamptz not null default now();
alter table public.profiles       add column if not exists attivato_da   uuid references public.profiles(id) on delete set null;
alter table public.profiles       add column if not exists attivato_il   timestamptz;
alter table public.profiles       add column if not exists sospeso_da    uuid references public.profiles(id) on delete set null;
alter table public.profiles       add column if not exists sospeso_il    timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Il prezzo minimo
-- ---------------------------------------------------------------------------
-- Costo di una base pizza. Per cambiarlo si cambia solo questo numero.
create or replace function public.prezzo_minimo_base() returns numeric
language sql immutable as $$ select 1.70::numeric $$;

-- Minimo di un cartone = 1,70 € × le basi che contiene (cartone da 20 → 34,00 €).
create or replace function public.prezzo_minimo_cartone(p_product_id text) returns numeric
language sql stable security definer set search_path = public as $$
  select round(public.prezzo_minimo_base() * greatest(coalesce(pezzi, 1), 1), 2)
  from public.products where id = p_product_id;
$$;
grant execute on function public.prezzo_minimo_base() to anon, authenticated;
grant execute on function public.prezzo_minimo_cartone(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. L'agente fissa il prezzo dei suoi clienti (e li attiva)
-- ---------------------------------------------------------------------------
create or replace function public.agente_imposta_prezzi(p_user_id uuid, p_prezzi jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  cli public.profiles%rowtype;
  prod public.products%rowtype;
  k text; v numeric; v_min numeric; n int := 0; senza_prezzo int;
begin
  if not public.is_agente() then raise exception 'Riservato agli agenti attivi'; end if;

  select * into cli from public.profiles where id = p_user_id;
  if cli.id is null then raise exception 'Cliente non trovato'; end if;
  if cli.agente_id is distinct from auth.uid() then raise exception 'Questo cliente non è collegato a te'; end if;
  if cli.ruolo <> 'cliente' then raise exception 'Il prezzo si fissa solo ai clienti'; end if;
  if cli.tipo not in ('b2b','rivenditore') then raise exception 'Il prezzo riservato vale solo per esercenti e rivenditori'; end if;
  if cli.sospeso_il is not null and not cli.approvato then
    raise exception 'Questo cliente è stato sospeso da Carminello: prima di rimetterlo in vendita parlane con noi';
  end if;

  for k, v in select key, value::numeric from jsonb_each_text(coalesce(p_prezzi, '{}'::jsonb)) loop
    select * into prod from public.products where id = k and canale = 'b2b' and attivo;
    if prod.id is null then raise exception 'Prodotto non disponibile'; end if;
    if v is null then raise exception 'Scrivi il prezzo di %', prod.nome_it; end if;

    v_min := public.prezzo_minimo_cartone(prod.id);
    if round(v, 2) < v_min then
      raise exception 'Il prezzo non può scendere sotto % € a cartone (% € a base × % basi). Puoi solo salire.',
        replace(to_char(v_min, 'FM999990.00'), '.', ','),
        replace(to_char(public.prezzo_minimo_base(), 'FM990.00'), '.', ','),
        prod.pezzi;
    end if;

    insert into public.prezzi_cliente (user_id, product_id, prezzo, aggiornato_da, aggiornato_il)
    values (p_user_id, prod.id, round(v, 2), auth.uid(), now())
    on conflict (user_id, product_id) do update
      set prezzo = excluded.prezzo, aggiornato_da = excluded.aggiornato_da, aggiornato_il = excluded.aggiornato_il;
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Nessun prezzo da salvare'; end if;

  -- Il cliente si attiva da solo quando ha il prezzo di tutti i cartoni in vendita.
  -- (L'email "il tuo account è attivo" parte in automatico, come quando attiva il titolare.)
  select count(*) into senza_prezzo
  from public.products pr
  where pr.canale = 'b2b' and pr.attivo
    and not exists (select 1 from public.prezzi_cliente pc where pc.user_id = p_user_id and pc.product_id = pr.id);

  if senza_prezzo = 0 and not cli.approvato then
    update public.profiles
       set approvato = true, attivato_da = auth.uid(), attivato_il = now(), sospeso_da = null, sospeso_il = null
     where id = p_user_id;
  end if;
end $$;
revoke all on function public.agente_imposta_prezzi(uuid, jsonb) from public;
grant execute on function public.agente_imposta_prezzi(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Il titolare: come prima, ma ora resta scritto chi ha fatto cosa
-- ---------------------------------------------------------------------------
-- Il titolare non ha il limite dei 1,70 €: se vuole fare un prezzo speciale può.
-- Se sospende un cliente, l'agente non può riattivarlo da solo.
create or replace function public.admin_imposta_cliente(p_user_id uuid, p_approvato boolean, p_prezzi jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text; v numeric; era boolean;
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  select approvato into era from public.profiles where id = p_user_id;
  for k, v in select key, value::numeric from jsonb_each_text(coalesce(p_prezzi, '{}'::jsonb)) loop
    insert into public.prezzi_cliente (user_id, product_id, prezzo, aggiornato_da, aggiornato_il)
    values (p_user_id, k, v, auth.uid(), now())
    on conflict (user_id, product_id) do update
      set prezzo = excluded.prezzo, aggiornato_da = excluded.aggiornato_da, aggiornato_il = excluded.aggiornato_il;
  end loop;
  update public.profiles set
    approvato   = p_approvato,
    attivato_da = case when p_approvato and not coalesce(era, false) then auth.uid() else attivato_da end,
    attivato_il = case when p_approvato and not coalesce(era, false) then now() else attivato_il end,
    sospeso_da  = case when p_approvato then null else auth.uid() end,
    sospeso_il  = case when p_approvato then null else now() end
  where id = p_user_id;
end $$;
