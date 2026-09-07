# Carminello Shop

Sito vetrina + negozio per le basi pizza Carminello (ALLEYS SRL). Sostituisce il vecchio sito WordPress.

- **Frontend**: HTML/CSS/JS puro, nessun build. Pubblicabile su GitHub Pages (o qualsiasi hosting statico).
- **Backend**: Supabase (Postgres + Auth + Edge Functions). Schema in `supabase/schema.sql`.
- **Pagamenti**: SumUp hosted checkout (edge function `sumup-checkout` / `sumup-verifica`), bonifico, contrassegno (solo B2B).
- **Email**: Brevo via edge function `notifica`, attivata dai Database Webhooks.
- **Lingue**: IT/EN (`assets/js/i18n.js`).

Guida completa per il titolare: [GUIDA.md](GUIDA.md).

## Regole di prezzo
- Privati: prodotti `canale = 'b2c'`, prezzo in `products.prezzo`.
- Locali: prodotti `canale = 'b2b'`, prezzo per cliente in `prezzi_cliente`; ordinano solo se `profiles.approvato`.
- I totali sono calcolati **dal database** (`crea_ordine`), mai dal browser.
- Spedizione a fasce per numero di cartoni e supplemento contrassegno in `impostazioni` (modificabili dal pannello).

## Sviluppo locale
```bash
cd carminello-shop && python3 -m http.server 8766
```
Senza Supabase configurato il sito mostra i prodotti demo di `config.js` e blocca il checkout.
