-- ============================================================================
-- MIGRAZIONE 02 — terzo tipo di cliente (rivenditore), note/chiamate, avvisi
-- Eseguita l'8 settembre 2026. Si può rilanciare senza danni.
-- ============================================================================

-- 1. Tre tipi di cliente: b2c (privati), b2b (locali), rivenditore (grossisti/rappresentanti)
alter table public.profiles drop constraint if exists profiles_tipo_check;
alter table public.profiles add constraint profiles_tipo_check check (tipo in ('b2c','b2b','rivenditore'));
alter table public.orders drop constraint if exists orders_tipo_check;
alter table public.orders add constraint orders_tipo_check check (tipo in ('b2c','b2b','rivenditore'));

-- 2. Note e chiamate sui clienti (solo amministratore)
create table if not exists public.note_clienti (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  tipo       text not null default 'nota' check (tipo in ('nota','chiamata','whatsapp','email')),
  testo      text not null,
  esito      text,                       -- es. 'riordina', 'in pausa', 'perso', 'nessuna risposta'
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists note_clienti_user_idx on public.note_clienti(user_id, created_at desc);
alter table public.note_clienti enable row level security;
drop policy if exists note_admin_read on public.note_clienti;
create policy note_admin_read on public.note_clienti for select using (public.is_admin());
grant select on public.note_clienti to authenticated;

create or replace function public.admin_aggiungi_nota(p_user_id uuid, p_tipo text, p_testo text, p_esito text default null)
returns public.note_clienti
language plpgsql security definer set search_path = public as $$
declare n public.note_clienti;
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  insert into public.note_clienti (user_id, tipo, testo, esito, created_by)
  values (p_user_id, coalesce(p_tipo,'nota'), p_testo, nullif(p_esito,''), auth.uid())
  returning * into n;
  return n;
end $$;

create or replace function public.admin_elimina_nota(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  delete from public.note_clienti where id = p_id;
end $$;

-- 3. L'amministratore può cambiare il tipo di un cliente (es. da locale a rivenditore)
create or replace function public.admin_cambia_tipo(p_user_id uuid, p_tipo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  if p_tipo not in ('b2c','b2b','rivenditore') then raise exception 'Tipo non valido'; end if;
  update public.profiles set tipo = p_tipo, approvato = case when p_tipo = 'b2c' then false else approvato end where id = p_user_id;
end $$;
grant execute on function public.admin_aggiungi_nota(uuid, text, text, text) to authenticated;
grant execute on function public.admin_elimina_nota(uuid) to authenticated;
grant execute on function public.admin_cambia_tipo(uuid, text) to authenticated;

-- 4. Soglie degli avvisi (modificabili dalla dashboard)
insert into public.impostazioni (chiave, valore) values
 ('avvisi', '{"ritardo_x":1.5,"rischio_x":2.5,"perso_x":3,"perso_giorni":90,"nuovo_giorni":45,"flessione_pct":30}')
on conflict (chiave) do nothing;

-- 5. Registrazione: accetta anche il tipo rivenditore
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, email, tipo, nome, cognome, telefono, ragione_sociale, piva, sdi, pec, lingua)
  values (
    new.id, new.email,
    case when m->>'tipo' in ('b2b','rivenditore') then m->>'tipo' else 'b2c' end,
    nullif(m->>'nome',''), nullif(m->>'cognome',''), nullif(m->>'telefono',''),
    nullif(m->>'ragione_sociale',''), nullif(m->>'piva',''), nullif(m->>'sdi',''), nullif(m->>'pec',''),
    coalesce(nullif(m->>'lingua',''), 'it')
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- 6. Catalogo e ordini: i rivenditori si comportano come i locali (prezzo per cliente, attivazione, contrassegno)
create or replace function public.catalogo()
returns table (id text, canale text, nome_it text, nome_en text, descr_it text, descr_en text, pezzi int, prezzo numeric, immagine text, ordine int)
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles%rowtype;
begin
  if auth.uid() is not null then
    select * into p from public.profiles where profiles.id = auth.uid();
  end if;
  if p.tipo in ('b2b','rivenditore') then
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
begin
  if auth.uid() is null then raise exception 'Devi accedere per ordinare'; end if;
  select * into prof from public.profiles where id = auth.uid();
  if prof.id is null then raise exception 'Profilo non trovato'; end if;
  pro := prof.tipo in ('b2b','rivenditore');
  if pro and not prof.approvato then raise exception 'Account in attesa di attivazione'; end if;
  if p_metodo not in ('carta','bonifico','contrassegno') then raise exception 'Metodo di pagamento non valido'; end if;
  if p_metodo = 'contrassegno' and not pro then raise exception 'Il contrassegno è riservato ai locali e ai rivenditori'; end if;
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

  insert into public.orders (user_id, tipo, stato, metodo_pagamento, pagato, righe, cartoni, subtotale, spedizione, supplemento, totale, indirizzo, note, lingua)
  values (prof.id, prof.tipo, v_stato, p_metodo, v_pagato, righe, cart, round(sub,2), sped, coalesce(supp,0), round(sub + sped + coalesce(supp,0), 2), p_indirizzo, nullif(p_note,''), coalesce(p_lingua,'it'))
  returning * into o;
  return o;
end $$;
