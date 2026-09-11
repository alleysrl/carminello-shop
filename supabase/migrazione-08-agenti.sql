-- ============================================================================
-- MIGRAZIONE 08 — AGENTI (rappresentanti) e PROVVIGIONI
-- Un agente porta clienti (esercenti/rivenditori), non compra. Il titolare lo
-- approva e gli assegna una percentuale. Ogni ordine di un suo cliente salva la
-- provvigione del giorno. Si può rilanciare senza danni.
-- ============================================================================

-- 1. Profili: nuovo ruolo 'agente' e campi collegati
alter table public.profiles drop constraint if exists profiles_ruolo_check;
alter table public.profiles add constraint profiles_ruolo_check check (ruolo in ('cliente','admin','agente'));
alter table public.profiles add column if not exists agente_id            uuid references public.profiles(id) on delete set null; -- cliente → il suo agente
alter table public.profiles add column if not exists codice_agente        text unique;                 -- solo agenti: codice per link/QR
alter table public.profiles add column if not exists provvigione_pct      numeric(5,2) not null default 0; -- solo agenti
alter table public.profiles add column if not exists accordo_accettato_il timestamptz;                 -- solo agenti (accordo, in futuro)
alter table public.profiles add column if not exists origine              text not null default 'sito' check (origine in ('sito','link','invito','manuale'));
create index if not exists profiles_agente_idx on public.profiles(agente_id);

-- 2. Ordini: fotografia dell'agente e della provvigione al momento dell'ordine
alter table public.orders add column if not exists agente_id                uuid references public.profiles(id) on delete set null;
alter table public.orders add column if not exists provvigione_pct          numeric(5,2) not null default 0;
alter table public.orders add column if not exists provvigione              numeric(10,2) not null default 0;
alter table public.orders add column if not exists provvigione_liquidata_il timestamptz;
create index if not exists orders_agente_idx on public.orders(agente_id, created_at desc);

-- 3. Chi è agente (approvato)?
create or replace function public.is_agente() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and ruolo = 'agente' and approvato);
$$;
grant execute on function public.is_agente() to anon, authenticated;

-- Codice agente leggibile (es. MARIO24), unico
create or replace function public.genera_codice_agente(p_nome text) returns text
language plpgsql security definer set search_path = public as $$
declare base text; c text; n int := 0;
begin
  base := upper(regexp_replace(coalesce(nullif(trim(p_nome),''), 'AGENTE'), '[^A-Za-z]', '', 'g'));
  if base = '' then base := 'AGENTE'; end if;
  base := left(base, 8);
  loop
    c := base || lpad((floor(random()*90)+10)::int::text, 2, '0');
    exit when not exists (select 1 from public.profiles where codice_agente = c);
    n := n + 1; if n > 50 then c := base || substr(gen_random_uuid()::text, 1, 4); exit; end if;
  end loop;
  return c;
end $$;

-- 4. Registrazione: agente (dall'app agenti) oppure cliente con codice agente (link/QR o invito)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_ruolo text := case when m->>'ruolo' = 'agente' then 'agente' else 'cliente' end;
  v_agente uuid;
  v_origine text := case when m->>'origine' in ('link','invito') then m->>'origine' else 'sito' end;
begin
  if v_ruolo = 'cliente' and coalesce(m->>'codice_agente','') <> '' then
    select id into v_agente from public.profiles where codice_agente = upper(trim(m->>'codice_agente')) and ruolo = 'agente' and approvato;
  end if;
  if v_agente is null then v_origine := 'sito'; end if;
  insert into public.profiles (id, email, tipo, ruolo, nome, cognome, telefono, ragione_sociale, piva, sdi, pec, indirizzo, lingua, agente_id, origine, codice_agente)
  values (
    new.id, new.email,
    case when v_ruolo = 'cliente' and m->>'tipo' in ('b2b','rivenditore') then m->>'tipo' else 'b2c' end,
    v_ruolo,
    nullif(m->>'nome',''), nullif(m->>'cognome',''), nullif(m->>'telefono',''),
    nullif(m->>'ragione_sociale',''), nullif(m->>'piva',''), nullif(m->>'sdi',''), nullif(m->>'pec',''),
    case when jsonb_typeof(m->'indirizzo') = 'object' then m->'indirizzo' else null end,
    coalesce(nullif(m->>'lingua',''), 'it'),
    v_agente, v_origine,
    case when v_ruolo = 'agente' then public.genera_codice_agente(m->>'nome') else null end
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- 5. Permessi di lettura: l'agente vede solo i suoi clienti, i loro ordini e i loro prezzi
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select
  using (id = auth.uid() or public.is_admin() or (agente_id = auth.uid() and public.is_agente()));

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select
  using (user_id = auth.uid() or public.is_admin()
         or (public.is_agente() and exists (select 1 from public.profiles p where p.id = orders.user_id and p.agente_id = auth.uid())));

drop policy if exists prezzi_read on public.prezzi_cliente;
create policy prezzi_read on public.prezzi_cliente for select
  using (user_id = auth.uid() or public.is_admin()
         or (public.is_agente() and exists (select 1 from public.profiles p where p.id = prezzi_cliente.user_id and p.agente_id = auth.uid())));

-- Note: il titolare vede tutte; l'agente solo quelle scritte da lui
drop policy if exists note_admin_read on public.note_clienti;
create policy note_admin_read on public.note_clienti for select
  using (public.is_admin() or (created_by = auth.uid() and public.is_agente()));

-- Push: ognuno (titolare o agente) vede e gestisce i propri dispositivi
drop policy if exists push_admin_read on public.push_subscriptions;
create policy push_admin_read on public.push_subscriptions for select
  using (user_id = auth.uid() and (public.is_admin() or public.is_agente()));

create or replace function public.admin_salva_push(p_sub jsonb, p_dispositivo text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_admin() or public.is_agente()) then raise exception 'Riservato al titolare e agli agenti'; end if;
  insert into public.push_subscriptions (endpoint, user_id, sub, dispositivo)
  values (p_sub->>'endpoint', auth.uid(), p_sub, p_dispositivo)
  on conflict (endpoint) do update set sub = excluded.sub, user_id = excluded.user_id, dispositivo = excluded.dispositivo;
end $$;
create or replace function public.admin_rimuovi_push(p_endpoint text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_admin() or public.is_agente()) then raise exception 'Riservato al titolare e agli agenti'; end if;
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
end $$;

-- 6. Ordine: gli agenti non ordinano; sull'ordine si fotografa agente e provvigione (solo sulla merce)
create or replace function public.crea_ordine(p_righe jsonb, p_metodo text, p_indirizzo jsonb, p_note text default null, p_lingua text default 'it')
returns public.orders
language plpgsql security definer set search_path = public as $$
declare
  prof public.profiles%rowtype;
  r jsonb; prod public.products%rowtype;
  v_prezzo numeric; v_qty int;
  righe jsonb := '[]'::jsonb;
  sub numeric := 0; cart int := 0; sped numeric; supp numeric := 0;
  o public.orders;
  v_stato text; v_pagato boolean := false;
  pro boolean;
  v_agente uuid; v_pct numeric := 0;
begin
  if auth.uid() is null then raise exception 'Devi accedere per ordinare'; end if;
  select * into prof from public.profiles where id = auth.uid();
  if prof.id is null then raise exception 'Profilo non trovato'; end if;
  if prof.ruolo = 'agente' then raise exception 'Gli account agente non possono ordinare'; end if;
  pro := prof.tipo in ('b2b','rivenditore');
  if pro and not prof.approvato then raise exception 'Account in attesa di attivazione: ti contattiamo per il prezzo'; end if;
  if p_metodo not in ('carta','bonifico','contrassegno') then raise exception 'Metodo di pagamento non valido'; end if;
  if p_metodo = 'contrassegno' and not pro then raise exception 'Il contrassegno è riservato a esercenti e rivenditori'; end if;
  if p_indirizzo is null or coalesce(p_indirizzo->>'via','') = '' or coalesce(p_indirizzo->>'citta','') = '' or coalesce(p_indirizzo->>'cap','') = '' then
    raise exception 'Indirizzo di consegna incompleto';
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_righe, '[]'::jsonb)) loop
    v_qty := coalesce((r->>'qty')::int, 0);
    if v_qty <= 0 then continue; end if;
    if v_qty > 999 then raise exception 'Quantità troppo alta'; end if;
    select * into prod from public.products where id = r->>'product_id' and attivo;
    if prod.id is null then raise exception 'Prodotto non disponibile: %', r->>'product_id'; end if;
    if pro then
      if prod.canale <> 'b2b' then raise exception 'Prodotto non disponibile per questo tipo di cliente'; end if;
      select prezzo into v_prezzo from public.prezzi_cliente where user_id = prof.id and product_id = prod.id;
      if v_prezzo is null then raise exception 'Prezzo non ancora concordato per %', prod.nome_it; end if;
    else
      if prod.canale <> 'b2c' or prod.prezzo is null then raise exception 'Prodotto non disponibile'; end if;
      v_prezzo := prod.prezzo;
    end if;
    righe := righe || jsonb_build_object('product_id', prod.id, 'nome', prod.nome_it, 'nome_en', prod.nome_en, 'pezzi', prod.pezzi, 'qty', v_qty, 'prezzo', v_prezzo, 'totale', round(v_prezzo * v_qty, 2));
    sub := sub + v_prezzo * v_qty; cart := cart + v_qty;
  end loop;
  if cart = 0 then raise exception 'Il carrello è vuoto'; end if;
  sped := public.costo_spedizione(cart);
  if p_metodo = 'contrassegno' then
    select coalesce((valore->>'supplemento')::numeric, 0) into supp from public.impostazioni where chiave = 'contrassegno';
  end if;
  v_stato := case when p_metodo = 'contrassegno' then 'da_spedire' else 'da_pagare' end;
  -- agente del cliente (se approvato) e sua percentuale di oggi
  if prof.agente_id is not null then
    select id, provvigione_pct into v_agente, v_pct from public.profiles where id = prof.agente_id and ruolo = 'agente' and approvato;
  end if;
  insert into public.orders (user_id, tipo, stato, metodo_pagamento, pagato, righe, cartoni, subtotale, spedizione, supplemento, totale, indirizzo, note, lingua, agente_id, provvigione_pct, provvigione)
  values (prof.id, prof.tipo, v_stato, p_metodo, v_pagato, righe, cart, round(sub,2), sped, coalesce(supp,0), round(sub + sped + coalesce(supp,0), 2), p_indirizzo, nullif(p_note,''), coalesce(p_lingua,'it'),
          v_agente, coalesce(v_pct,0), case when v_agente is null then 0 else round(sub * coalesce(v_pct,0) / 100, 2) end)
  returning * into o;
  return o;
end $$;

-- 7. Funzioni del titolare
-- Approva un agente e imposta percentuale (e, se vuoi, il codice)
create or replace function public.admin_imposta_agente(p_user_id uuid, p_approvato boolean, p_pct numeric default null, p_codice text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_pct is not null and (p_pct < 0 or p_pct > 100) then raise exception 'Percentuale non valida'; end if;
  update public.profiles set
    approvato = p_approvato,
    provvigione_pct = coalesce(p_pct, provvigione_pct),
    codice_agente = coalesce(nullif(upper(regexp_replace(coalesce(p_codice,''), '[^A-Za-z0-9]', '', 'g')),''), codice_agente, public.genera_codice_agente(nome))
  where id = p_user_id and ruolo = 'agente';
  if not found then raise exception 'Agente non trovato'; end if;
end $$;

-- Rende agente un account esistente (o lo riporta a cliente)
create or replace function public.admin_cambia_ruolo(p_user_id uuid, p_ruolo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_ruolo not in ('cliente','agente') then raise exception 'Ruolo non valido'; end if;
  if p_user_id = auth.uid() then raise exception 'Non puoi cambiare il tuo ruolo'; end if;
  update public.profiles set
    ruolo = p_ruolo, approvato = false,
    codice_agente = case when p_ruolo = 'agente' then coalesce(codice_agente, public.genera_codice_agente(nome)) else null end
  where id = p_user_id and ruolo <> 'admin';
end $$;

-- Collega (o scollega, con null) un cliente a un agente
create or replace function public.admin_assegna_agente(p_cliente_id uuid, p_agente_id uuid default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_agente_id is not null and not exists (select 1 from public.profiles where id = p_agente_id and ruolo = 'agente') then raise exception 'Agente non trovato'; end if;
  update public.profiles set agente_id = p_agente_id, origine = case when p_agente_id is null then origine else 'manuale' end
  where id = p_cliente_id and ruolo = 'cliente';
end $$;

-- Segna liquidate (o non liquidate) le provvigioni di un agente per un mese
create or replace function public.admin_liquida_provvigioni(p_agente_id uuid, p_mese date, p_liquidata boolean default true) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  update public.orders set provvigione_liquidata_il = case when p_liquidata then now() else null end
  where agente_id = p_agente_id and pagato and stato <> 'annullato' and provvigione > 0
    and date_trunc('month', created_at at time zone 'Europe/Rome') = date_trunc('month', p_mese);
  get diagnostics n = row_count;
  return n;
end $$;

-- Eliminazione cliente: sistema anche i collegamenti se era un agente
create or replace function public.admin_elimina_cliente(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_user_id = auth.uid() then raise exception 'Non puoi eliminare il tuo account'; end if;
  update public.profiles set agente_id = null where agente_id = p_user_id;
  update public.orders set agente_id = null where agente_id = p_user_id;
  delete from public.note_clienti where user_id = p_user_id or created_by = p_user_id;
  delete from public.push_subscriptions where user_id = p_user_id;
  delete from public.prezzi_cliente where user_id = p_user_id;
  delete from public.orders where user_id = p_user_id;
  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;
end $$;

grant execute on function public.admin_imposta_agente(uuid, boolean, numeric, text) to authenticated;
grant execute on function public.admin_cambia_ruolo(uuid, text) to authenticated;
grant execute on function public.admin_assegna_agente(uuid, uuid) to authenticated;
grant execute on function public.admin_liquida_provvigioni(uuid, date, boolean) to authenticated;

-- 8. Riepilogo provvigioni per mese (titolare: tutti; agente: solo se stesso)
create or replace function public.provvigioni_mensili(p_agente_id uuid default null)
returns table (agente_id uuid, mese date, ordini int, cartoni int, fatturato numeric, maturata numeric, liquidata numeric, in_attesa numeric)
language sql stable security definer set search_path = public as $$
  select o.agente_id,
         (date_trunc('month', o.created_at at time zone 'Europe/Rome'))::date as mese,
         count(*) filter (where o.stato <> 'annullato')::int as ordini,
         coalesce(sum(o.cartoni) filter (where o.stato <> 'annullato'), 0)::int as cartoni,
         coalesce(sum(o.subtotale) filter (where o.pagato and o.stato <> 'annullato'), 0) as fatturato,
         coalesce(sum(o.provvigione) filter (where o.pagato and o.stato <> 'annullato'), 0) as maturata,
         coalesce(sum(o.provvigione) filter (where o.pagato and o.stato <> 'annullato' and o.provvigione_liquidata_il is not null), 0) as liquidata,
         coalesce(sum(o.provvigione) filter (where not o.pagato and o.stato <> 'annullato'), 0) as in_attesa
  from public.orders o
  where o.agente_id is not null
    and (public.is_admin() or (public.is_agente() and o.agente_id = auth.uid()))
    and (p_agente_id is null or o.agente_id = p_agente_id)
  group by o.agente_id, 2
  order by 2 desc;
$$;
grant execute on function public.provvigioni_mensili(uuid) to authenticated;

-- 9. Funzioni dell'agente
-- Note sui propri clienti
create or replace function public.agente_aggiungi_nota(p_user_id uuid, p_tipo text, p_testo text, p_esito text default null)
returns public.note_clienti
language plpgsql security definer set search_path = public as $$
declare n public.note_clienti;
begin
  if not public.is_agente() then raise exception 'Riservato agli agenti attivi'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id and agente_id = auth.uid()) then raise exception 'Non è un tuo cliente'; end if;
  insert into public.note_clienti (user_id, tipo, testo, esito, created_by)
  values (p_user_id, coalesce(p_tipo,'nota'), p_testo, nullif(p_esito,''), auth.uid())
  returning * into n;
  return n;
end $$;
create or replace function public.agente_elimina_nota(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_agente() then raise exception 'Riservato agli agenti attivi'; end if;
  delete from public.note_clienti where id = p_id and created_by = auth.uid();
end $$;
grant execute on function public.agente_aggiungi_nota(uuid, text, text, text) to authenticated;
grant execute on function public.agente_elimina_nota(uuid) to authenticated;

-- Dal sito: nome dell'agente a partire dal codice (per "Il tuo rappresentante: Mario")
create or replace function public.agente_da_codice(p_codice text)
returns table (nome text, cognome text)
language sql stable security definer set search_path = public as $$
  select nome, cognome from public.profiles
  where codice_agente = upper(trim(coalesce(p_codice,''))) and ruolo = 'agente' and approvato limit 1;
$$;
grant execute on function public.agente_da_codice(text) to anon, authenticated;

-- Dal sito: il cliente vede chi è il suo rappresentante
create or replace function public.mio_agente()
returns table (nome text, cognome text, telefono text)
language sql stable security definer set search_path = public as $$
  select a.nome, a.cognome, a.telefono from public.profiles c join public.profiles a on a.id = c.agente_id
  where c.id = auth.uid() and a.ruolo = 'agente';
$$;
grant execute on function public.mio_agente() to authenticated;

-- L'agente aggiorna i propri dati (telefono, nome...) con aggiorna_profilo già esistente.
-- Accordo: quando lo faremo, una funzione accetta_accordo() scriverà accordo_accettato_il.
