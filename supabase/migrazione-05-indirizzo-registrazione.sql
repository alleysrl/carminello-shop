-- MIGRAZIONE 05 — alla registrazione salva anche l'indirizzo (compilato dalla Partita IVA)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, email, tipo, nome, cognome, telefono, ragione_sociale, piva, sdi, pec, indirizzo, lingua)
  values (
    new.id, new.email,
    case when m->>'tipo' in ('b2b','rivenditore') then m->>'tipo' else 'b2c' end,
    nullif(m->>'nome',''), nullif(m->>'cognome',''), nullif(m->>'telefono',''),
    nullif(m->>'ragione_sociale',''), nullif(m->>'piva',''), nullif(m->>'sdi',''), nullif(m->>'pec',''),
    case when jsonb_typeof(m->'indirizzo') = 'object' then m->'indirizzo' else null end,
    coalesce(nullif(m->>'lingua',''), 'it')
  )
  on conflict (id) do nothing;
  return new;
end $$;
