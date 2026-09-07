-- ============================================================================
-- CARMINELLO SHOP — DATABASE (Supabase / PostgreSQL)
-- ----------------------------------------------------------------------------
-- Da incollare UNA volta nell'editor SQL di Supabase (Dashboard → SQL Editor →
-- New query → incolla tutto → Run). Crea tabelle, regole di sicurezza e funzioni.
-- Si può rilanciare senza danni: usa "if not exists" / "create or replace".
-- ============================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. TABELLE
-- ---------------------------------------------------------------------------

-- Prodotti in vendita. "canale" = a chi è destinato: b2c (privati) o b2b (locali).
-- Per i b2c il prezzo sta qui; per i b2b il prezzo è per cliente (tabella prezzi_cliente).
create table if not exists public.products (
  id          text primary key,
  canale      text not null check (canale in ('b2c','b2b')),
  nome_it     text not null,
  nome_en     text,
  descr_it    text,
  descr_en    text,
  pezzi       int  not null default 8,
  prezzo      numeric(10,2),
  immagine    text,
  attivo      boolean not null default true,
  ordine      int not null default 1,
  created_at  timestamptz not null default now()
);

-- Anagrafica clienti: una riga per ogni utente registrato.
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  email           text,
  tipo            text not null default 'b2c' check (tipo in ('b2c','b2b')),
  ruolo           text not null default 'cliente' check (ruolo in ('cliente','admin')),
  nome            text,
  cognome         text,
  telefono        text,
  ragione_sociale text,
  piva            text,
  sdi             text,
  pec             text,
  indirizzo       jsonb,
  approvato       boolean not null default false,   -- solo b2b: può ordinare?
  lingua          text default 'it',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Prezzo riservato di ogni cliente b2b per ogni prodotto b2b.
create table if not exists public.prezzi_cliente (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  prezzo     numeric(10,2) not null check (prezzo >= 0),
  primary key (user_id, product_id)
);

-- Ordini. "righe" contiene i prodotti con nome e prezzo AL MOMENTO dell'ordine.
create sequence if not exists public.order_number_seq start 1001;
create table if not exists public.orders (
  id                uuid primary key default gen_random_uuid(),
  numero            int  not null unique default nextval('public.order_number_seq'),
  user_id           uuid not null references public.profiles(id),
  tipo              text not null check (tipo in ('b2c','b2b')),
  stato             text not null default 'da_pagare' check (stato in ('da_pagare','da_spedire','spedito','annullato')),
  metodo_pagamento  text not null check (metodo_pagamento in ('carta','bonifico','contrassegno')),
  pagato            boolean not null default false,
  pagato_il         timestamptz,
  righe             jsonb not null,
  cartoni           int not null,
  subtotale         numeric(10,2) not null,
  spedizione        numeric(10,2) not null,
  supplemento       numeric(10,2) not null default 0,
  totale            numeric(10,2) not null,
  indirizzo         jsonb not null,
  note              text,
  lingua            text default 'it',
  sumup_checkout_id text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists orders_user_idx on public.orders(user_id, created_at desc);
create index if not exists orders_stato_idx on public.orders(stato);

-- Impostazioni modificabili dal pannello (spedizione, contrassegno, bonifico, email avvisi).
create table if not exists public.impostazioni (
  chiave text primary key,
  valore jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. DATI INIZIALI (solo se mancano)
-- ---------------------------------------------------------------------------
insert into public.products (id, canale, nome_it, nome_en, descr_it, descr_en, pezzi, prezzo, immagine, attivo, ordine) values
 ('base-33-cartone-8', 'b2c',
  'Base Pizza Carminello 33 cm — cartone da 8',
  'Carminello 33 cm Pizza Base — box of 8',
  'Base pizza artigianale da 33 cm con bordo rialzato, cotta a infrarossi. Impasto a lunga maturazione, alta digeribilità, farine 100% italiane. Si conserva oltre 30 giorni a temperatura ambiente, senza frigorifero.',
  'Handcrafted 33 cm pizza base with raised crust, infrared-baked. Long-fermented dough, highly digestible, 100% Italian flours. Keeps for over 30 days at room temperature, no fridge needed.',
  8, 14.99, 'assets/img/base-classica.webp', true, 1),
 ('base-33-cartone-20', 'b2b',
  'Base Pizza Carminello 33 cm — cartone da 20 (buste da 2)',
  'Carminello 33 cm Pizza Base — box of 20 (packs of 2)',
  'Formato professionale: cartone da 20 basi in 10 buste da 2. Base 33 cm con bordo rialzato, cotta a infrarossi, oltre 30 giorni di conservazione a temperatura ambiente.',
  'Professional format: box of 20 bases in 10 packs of 2. 33 cm base with raised crust, infrared-baked, keeps for over 30 days at room temperature.',
  20, null, 'assets/img/base-classica.webp', true, 2)
on conflict (id) do nothing;

insert into public.impostazioni (chiave, valore) values
 ('spedizione',   '[{"fino_a":1,"costo":6.99},{"fino_a":2,"costo":15.98},{"fino_a":3,"costo":20.97},{"fino_a":9,"costo":24.99},{"fino_a":null,"costo":0}]'),
 ('contrassegno', '{"supplemento":5.00}'),
 ('bonifico',     '{"intestatario":"ALLEYS SRL","iban":"COMPILA DAL PANNELLO","banca":"","bic":""}'),
 ('notifiche',    '{"email":"info@carminello.eu"}')
on conflict (chiave) do nothing;

-- ---------------------------------------------------------------------------
-- 3. FUNZIONI DI SUPPORTO
-- ---------------------------------------------------------------------------

-- È l'utente collegato un amministratore?
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and ruolo = 'admin');
$$;

-- Quando un utente si registra, crea la sua riga in profiles con i dati del modulo.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, email, tipo, nome, cognome, telefono, ragione_sociale, piva, sdi, pec, lingua)
  values (
    new.id, new.email,
    case when m->>'tipo' = 'b2b' then 'b2b' else 'b2c' end,
    nullif(m->>'nome',''), nullif(m->>'cognome',''), nullif(m->>'telefono',''),
    nullif(m->>'ragione_sociale',''), nullif(m->>'piva',''), nullif(m->>'sdi',''), nullif(m->>'pec',''),
    coalesce(nullif(m->>'lingua',''), 'it')
  )
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Tiene aggiornato updated_at
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
drop trigger if exists orders_touch on public.orders;
create trigger orders_touch before update on public.orders for each row execute function public.touch_updated_at();

-- Costo di spedizione per N cartoni, secondo le fasce in impostazioni.
create or replace function public.costo_spedizione(n int) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare f jsonb; fasce jsonb;
begin
  if n <= 0 then return 0; end if;
  select valore into fasce from public.impostazioni where chiave = 'spedizione';
  for f in select * from jsonb_array_elements(coalesce(fasce, '[]'::jsonb)) loop
    if (f->>'fino_a') is null or n <= (f->>'fino_a')::int then
      return round((f->>'costo')::numeric, 2);
    end if;
  end loop;
  return 0;
end $$;

-- ---------------------------------------------------------------------------
-- 4. FUNZIONI CHIAMATE DAL SITO
-- ---------------------------------------------------------------------------

-- Catalogo visibile all'utente collegato, con il prezzo giusto per lui.
--  - non collegato o privato: prodotti b2c con prezzo di listino
--  - locale attivato: prodotti b2b con il SUO prezzo riservato
--  - locale non ancora attivato: nessun prodotto
create or replace function public.catalogo()
returns table (id text, canale text, nome_it text, nome_en text, descr_it text, descr_en text, pezzi int, prezzo numeric, immagine text, ordine int)
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles%rowtype;
begin
  if auth.uid() is not null then
    select * into p from public.profiles where profiles.id = auth.uid();
  end if;
  if p.tipo = 'b2b' then
    if not coalesce(p.approvato, false) then return; end if;
    return query
      select pr.id, pr.canale, pr.nome_it, pr.nome_en, pr.descr_it, pr.descr_en, pr.pezzi, pc.prezzo, pr.immagine, pr.ordine
      from public.products pr
      join public.prezzi_cliente pc on pc.product_id = pr.id and pc.user_id = p.id
      where pr.canale = 'b2b' and pr.attivo
      order by pr.ordine;
  else
    return query
      select pr.id, pr.canale, pr.nome_it, pr.nome_en, pr.descr_it, pr.descr_en, pr.pezzi, pr.prezzo, pr.immagine, pr.ordine
      from public.products pr
      where pr.canale = 'b2c' and pr.attivo and pr.prezzo is not null
      order by pr.ordine;
  end if;
end $$;

-- Crea un ordine. I prezzi vengono ricalcolati QUI, mai presi dal browser.
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
begin
  if auth.uid() is null then raise exception 'Devi accedere per ordinare'; end if;
  select * into prof from public.profiles where id = auth.uid();
  if prof.id is null then raise exception 'Profilo non trovato'; end if;
  if prof.tipo = 'b2b' and not prof.approvato then raise exception 'Account in attesa di attivazione'; end if;
  if p_metodo not in ('carta','bonifico','contrassegno') then raise exception 'Metodo di pagamento non valido'; end if;
  if p_metodo = 'contrassegno' and prof.tipo <> 'b2b' then raise exception 'Il contrassegno è riservato ai locali'; end if;
  if p_indirizzo is null or coalesce(p_indirizzo->>'via','') = '' or coalesce(p_indirizzo->>'citta','') = '' or coalesce(p_indirizzo->>'cap','') = '' then
    raise exception 'Indirizzo di consegna incompleto';
  end if;

  for r in select * from jsonb_array_elements(coalesce(p_righe, '[]'::jsonb)) loop
    v_qty := coalesce((r->>'qty')::int, 0);
    if v_qty <= 0 then continue; end if;
    if v_qty > 999 then raise exception 'Quantità troppo alta'; end if;
    select * into prod from public.products where id = r->>'product_id' and attivo;
    if prod.id is null then raise exception 'Prodotto non disponibile: %', r->>'product_id'; end if;
    if prof.tipo = 'b2b' then
      if prod.canale <> 'b2b' then raise exception 'Prodotto non disponibile per i locali'; end if;
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

  insert into public.orders (user_id, tipo, stato, metodo_pagamento, pagato, righe, cartoni, subtotale, spedizione, supplemento, totale, indirizzo, note, lingua)
  values (prof.id, prof.tipo, v_stato, p_metodo, v_pagato, righe, cart, round(sub,2), sped, coalesce(supp,0), round(sub + sped + coalesce(supp,0), 2), p_indirizzo, nullif(p_note,''), coalesce(p_lingua,'it'))
  returning * into o;
  return o;
end $$;

-- Il cliente aggiorna i propri dati (solo i campi permessi).
create or replace function public.aggiorna_profilo(p_dati jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Non collegato'; end if;
  update public.profiles set
    nome            = coalesce(nullif(p_dati->>'nome',''), nome),
    cognome         = coalesce(nullif(p_dati->>'cognome',''), cognome),
    telefono        = coalesce(nullif(p_dati->>'telefono',''), telefono),
    ragione_sociale = case when p_dati ? 'ragione_sociale' then nullif(p_dati->>'ragione_sociale','') else ragione_sociale end,
    piva            = case when p_dati ? 'piva' then nullif(p_dati->>'piva','') else piva end,
    sdi             = case when p_dati ? 'sdi' then nullif(p_dati->>'sdi','') else sdi end,
    pec             = case when p_dati ? 'pec' then nullif(p_dati->>'pec','') else pec end,
    indirizzo       = case when p_dati ? 'indirizzo' then p_dati->'indirizzo' else indirizzo end
  where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------
-- 5. FUNZIONI DEL PANNELLO (solo amministratore)
-- ---------------------------------------------------------------------------
create or replace function public.admin_aggiorna_ordine(p_id uuid, p_stato text default null, p_pagato boolean default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  update public.orders set
    pagato    = coalesce(p_pagato, pagato),
    pagato_il = case when p_pagato is true and pagato is false then now() else pagato_il end,
    stato     = coalesce(p_stato, case when p_pagato is true and stato = 'da_pagare' then 'da_spedire' else stato end)
  where id = p_id;
end $$;

create or replace function public.admin_imposta_cliente(p_user_id uuid, p_approvato boolean, p_prezzi jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text; v numeric;
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  for k, v in select key, value::numeric from jsonb_each_text(coalesce(p_prezzi, '{}'::jsonb)) loop
    insert into public.prezzi_cliente (user_id, product_id, prezzo) values (p_user_id, k, v)
    on conflict (user_id, product_id) do update set prezzo = excluded.prezzo;
  end loop;
  update public.profiles set approvato = p_approvato where id = p_user_id;
end $$;

create or replace function public.admin_salva_prodotto(p_dati jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  insert into public.products (id, canale, nome_it, nome_en, descr_it, descr_en, pezzi, prezzo, immagine, attivo, ordine)
  values (
    p_dati->>'id', coalesce(p_dati->>'canale','b2c'), coalesce(p_dati->>'nome_it','Nuovo prodotto'), p_dati->>'nome_en',
    p_dati->>'descr_it', p_dati->>'descr_en', coalesce((p_dati->>'pezzi')::int, 8), (p_dati->>'prezzo')::numeric,
    p_dati->>'immagine', coalesce((p_dati->>'attivo')::boolean, true), coalesce((p_dati->>'ordine')::int, 1))
  on conflict (id) do update set
    nome_it  = coalesce(excluded.nome_it, products.nome_it),
    nome_en  = case when p_dati ? 'nome_en' then excluded.nome_en else products.nome_en end,
    descr_it = case when p_dati ? 'descr_it' then excluded.descr_it else products.descr_it end,
    descr_en = case when p_dati ? 'descr_en' then excluded.descr_en else products.descr_en end,
    pezzi    = coalesce(excluded.pezzi, products.pezzi),
    prezzo   = case when p_dati ? 'prezzo' then excluded.prezzo else products.prezzo end,
    immagine = case when p_dati ? 'immagine' then excluded.immagine else products.immagine end,
    attivo   = coalesce(excluded.attivo, products.attivo),
    ordine   = coalesce(excluded.ordine, products.ordine);
end $$;

create or replace function public.admin_salva_impostazione(p_chiave text, p_valore jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  insert into public.impostazioni (chiave, valore) values (p_chiave, p_valore)
  on conflict (chiave) do update set valore = excluded.valore, updated_at = now();
end $$;

-- ---------------------------------------------------------------------------
-- 6. SICUREZZA (RLS): chi può leggere cosa. Le scritture passano dalle funzioni.
-- ---------------------------------------------------------------------------
alter table public.products       enable row level security;
alter table public.profiles       enable row level security;
alter table public.prezzi_cliente enable row level security;
alter table public.orders         enable row level security;
alter table public.impostazioni   enable row level security;

drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (attivo or public.is_admin());

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select using (id = auth.uid() or public.is_admin());

drop policy if exists prezzi_read on public.prezzi_cliente;
create policy prezzi_read on public.prezzi_cliente for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists impostazioni_read on public.impostazioni;
create policy impostazioni_read on public.impostazioni for select using (true);

-- Permessi di esecuzione delle funzioni
grant usage on schema public to anon, authenticated;
grant select on public.products, public.impostazioni to anon, authenticated;
grant select on public.profiles, public.prezzi_cliente, public.orders to authenticated;
grant execute on function public.catalogo() to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.costo_spedizione(int) to anon, authenticated;
grant execute on function public.crea_ordine(jsonb, text, jsonb, text, text) to authenticated;
grant execute on function public.aggiorna_profilo(jsonb) to authenticated;
grant execute on function public.admin_aggiorna_ordine(uuid, text, boolean) to authenticated;
grant execute on function public.admin_imposta_cliente(uuid, boolean, jsonb) to authenticated;
grant execute on function public.admin_salva_prodotto(jsonb) to authenticated;
grant execute on function public.admin_salva_impostazione(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. DOPO AVER CREATO IL TUO ACCOUNT DAL SITO, RENDITI AMMINISTRATORE:
--    (sostituisci l'email con quella usata per registrarti, poi Run)
-- ---------------------------------------------------------------------------
-- update public.profiles set ruolo = 'admin' where email = 'LA-TUA-EMAIL@esempio.it';
