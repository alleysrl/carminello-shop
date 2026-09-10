-- MIGRAZIONE 07 — solo testo: "locale" diventa "esercente" nei messaggi del database
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
  insert into public.orders (user_id, tipo, stato, metodo_pagamento, pagato, righe, cartoni, subtotale, spedizione, supplemento, totale, indirizzo, note, lingua)
  values (prof.id, prof.tipo, v_stato, p_metodo, v_pagato, righe, cart, round(sub,2), sped, coalesce(supp,0), round(sub + sped + coalesce(supp,0), 2), p_indirizzo, nullif(p_note,''), coalesce(p_lingua,'it'))
  returning * into o;
  return o;
end $$;
