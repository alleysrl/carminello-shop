-- MIGRAZIONE 11 — ordine annullato: la provvigione va a 0 (resta memorizzata la percentuale)
create or replace function public.admin_aggiorna_ordine(p_id uuid, p_stato text default null, p_pagato boolean default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Riservato al titolare'; end if;
  update public.orders set
    pagato    = coalesce(p_pagato, pagato),
    pagato_il = case when p_pagato is true and pagato is false then now() else pagato_il end,
    stato     = coalesce(p_stato, case when p_pagato is true and stato = 'da_pagare' then 'da_spedire' else stato end),
    provvigione = case when p_stato = 'annullato' then 0 else provvigione end,
    provvigione_liquidata_il = case when p_stato = 'annullato' then null else provvigione_liquidata_il end
  where id = p_id;
end $$;
-- ordini già annullati: provvigione a zero
update public.orders set provvigione = 0, provvigione_liquidata_il = null where stato = 'annullato' and provvigione <> 0;
