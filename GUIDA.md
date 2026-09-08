# GUIDA — Carminello Shop

Questa è la guida per mettere online il nuovo negozio delle basi pizza e usarlo tutti i giorni.
È scritta per chi non è un tecnico: segui i passi nell'ordine, ognuno dura pochi minuti.

> **Riassunto in una riga:** il sito sta su GitHub (gratis), i dati (clienti, ordini, prezzi) stanno
> su Supabase (gratis), le carte passano da SumUp, le email di avviso da Brevo (gratis).

---

## 0. Cosa c'è in questa cartella

| File / cartella | A cosa serve |
|---|---|
| `index.html` | La home: vetrina, prodotto, come si cuoce, galleria, sezione locali, contatti |
| `shop.html` | La pagina per ordinare (quantità, spedizione, totale) |
| `checkout.html` | Indirizzo, scelta del pagamento, conferma |
| `ordine.html` | La pagina del singolo ordine (con IBAN per il bonifico, o pulsante "paga con carta") |
| `account.html` | Accesso, registrazione (privato o locale), ordini passati, dati personali |
| `admin.html` | **Il tuo pannello**: ordini, clienti, prodotti, impostazioni |
| `info.html` | Spedizioni, pagamenti, cottura, condizioni di vendita, privacy, cookie |
| `assets/js/config.js` | **L'unico file da compilare a mano** (indirizzo e chiave di Supabase) |
| `assets/icons/` | Le icone dell'app (la mascotte su sfondo terracotta) |
| `supabase/schema.sql` | Il "progetto" del database, da incollare una volta su Supabase |
| `supabase/functions/` | Tre piccoli programmi che girano su Supabase: pagamento SumUp e email |

Per vedere il sito in anteprima basta aprire `index.html` con un doppio clic: si vede tutto,
ma finché Supabase non è collegato compare una striscia gialla e non si può ordinare.

---

## 1. Supabase — il database (15 minuti)

1. Vai su **https://supabase.com** → *Start your project* → crea l'account (va bene "Continue with GitHub"
   oppure email + password).
2. **New project**: nome `carminello`, scegli una password per il database (salvala in un posto sicuro,
   non serve tutti i giorni), regione **West EU (Ireland)** o **Central EU (Frankfurt)**. Attendi 1–2 minuti.
3. Nel menu a sinistra apri **SQL Editor** → *New query*. Apri il file `supabase/schema.sql` con TextEdit,
   copia **tutto** il contenuto, incollalo nell'editor e premi **Run**. Deve comparire "Success".
4. Menu a sinistra → **Project Settings** (l'ingranaggio) → **API**. Copia:
   - **Project URL** (es. `https://abcdefgh.supabase.co`)
   - la chiave **anon / publishable** (una stringa lunga)
5. Apri `assets/js/config.js` con TextEdit e incolla i due valori al posto di `INCOLLA_QUI_...`. Salva.
   Questa chiave è pubblica: può stare nel sito senza problemi.

### Impostazioni account (Authentication)
6. Menu **Authentication** → **Providers** → *Email*: lascia acceso "Confirm email" (i clienti confermano
   l'indirizzo con un clic nell'email: evita account finti).
7. **Authentication** → **URL Configuration**:
   - *Site URL*: per ora `http://localhost`, dopo la pubblicazione (punto 4) metterai l'indirizzo vero.
   - *Redirect URLs*: aggiungi l'indirizzo del sito seguito da `/account.html` (lo farai al punto 4).
8. **Importante — le email di conferma.** Supabase gratis manda pochissime email all'ora. Per non bloccare
   le registrazioni, colleghiamo Brevo (vedi punto 6) anche qui: **Project Settings → Authentication → SMTP Settings**
   → *Enable Custom SMTP*: Host `smtp-relay.brevo.com`, Port `587`, Username = la login di Brevo,
   Password = la **SMTP key** di Brevo, Sender email = la tua email mittente verificata su Brevo.

---

## 2. Diventa amministratore (2 minuti)

1. Apri il sito (anche in locale) → **Accedi** → **Registrati** come *Privato* con la tua email.
   Conferma l'email se richiesto.
2. Su Supabase → **SQL Editor** → *New query* → incolla e premi Run (con la TUA email):
   ```sql
   update public.profiles set ruolo = 'admin' where email = 'la-tua-email@esempio.it';
   ```
3. Ricarica il sito: in alto compare la voce verde **Pannello**. Aprila → scheda **Impostazioni**:
   - compila **intestatario e IBAN** per il bonifico;
   - controlla l'**email che riceve gli avvisi** (per ora puoi metterne una che leggi davvero,
     finché non recuperi info@carminello.eu);
   - le fasce di **spedizione** e il **supplemento contrassegno** sono già quelli concordati.

---

## 3. Pubblica il sito su GitHub Pages (10 minuti)

1. Apri **GitHub Desktop** → *File → Add Local Repository* → scegli questa cartella. Se dice che non è un
   repository, clicca *create a repository* (nome `carminello`, spunta "Initialize with README" NO).
2. In basso a sinistra scrivi "Prima versione" → **Commit to main** → in alto **Publish repository**.
   Togli la spunta "Keep this code private" (GitHub Pages gratis vuole il repository pubblico; nel codice
   non ci sono segreti, solo la chiave pubblica di Supabase).
3. Su github.com apri il repository → **Settings → Pages** → *Source: Deploy from a branch* → Branch `main`,
   cartella `/ (root)` → Save. Dopo 1–2 minuti il sito è online a un indirizzo tipo
   `https://alleysrl.github.io/carminello-shop/`.
4. Torna su Supabase → **Authentication → URL Configuration** e metti quell'indirizzo come *Site URL*
   e `https://alleysrl.github.io/carminello-shop/account.html` fra le *Redirect URLs*.

Ogni volta che si modifica qualcosa nella cartella: GitHub Desktop → Commit → **Push origin**. In un minuto è online.

> Quando recupererai l'accesso al dominio, in *Settings → Pages → Custom domain* si mette `carminello.eu`
> (o `shop.carminello.eu`) e nel pannello del dominio si aggiunge un record CNAME verso `NOMEACCOUNT.github.io`.

---

## 4. SumUp — pagamento con carta (10 minuti + eventuale attivazione)

1. Entra su **https://me.sumup.com** con il tuo account.
2. Il pagamento online ("SumUp Online Payments / Checkout") va abilitato sull'account: se nel menu non trovi
   *Developers* o *Online payments*, scrivi all'assistenza SumUp chiedendo di **attivare i pagamenti online
   con le API (Checkout API)** per il tuo account. È gratuito, pagano le stesse commissioni delle carte.
3. Menu **Developers → API keys → Create API key**: copia la chiave segreta (inizia con `sup_sk_`).
   **Non incollarla mai in chat né nei file del sito.**
4. Il **Merchant code** (es. `MCXXXXXX`) si trova nel profilo dell'account SumUp.
5. Su Supabase → **Edge Functions → Secrets** (oppure *Project Settings → Edge Functions*) aggiungi:
   - `SUMUP_API_KEY` = la chiave segreta
   - `SUMUP_MERCHANT_CODE` = il merchant code

### Caricare i tre programmi (Edge Functions)
6. Supabase → **Edge Functions** → *Deploy a new function* → *Via Editor*:
   - nome `sumup-checkout`, incolla il contenuto di `supabase/functions/sumup-checkout/index.ts` → Deploy.
   - ripeti con `sumup-verifica`.
   - ripeti con `notifica`; per questa, nelle impostazioni della funzione **disattiva "Verify JWT"**
     (viene chiamata dal database, non dai clienti; è protetta dalla parola segreta del punto 6).
7. Primo test: fai un ordine vero da 1 cartone con la tua carta, controlla che l'ordine risulti "Pagato"
   nel pannello, poi rimborsalo da SumUp.

---

## 5. Brevo — le email di avviso (10 minuti)

1. Crea un account gratuito su **https://www.brevo.com** (300 email al giorno gratis, più che sufficienti).
2. **Senders & IP → Senders → Add a sender**: metti l'email mittente. Brevo manda un link di conferma a
   quell'indirizzo, quindi deve essere una casella che leggi. Finché info@carminello.eu non è recuperata,
   usa un'altra tua email; dopo la cambierai.
3. **SMTP & API → API Keys → Generate a new API key**: copiala.
4. **SMTP & API → SMTP**: qui trovi login e **SMTP key** da usare al punto 1.8 (email di conferma account).
5. Su Supabase → **Edge Functions → Secrets** aggiungi:
   - `BREVO_API_KEY` = la chiave API
   - `SENDER_EMAIL` = l'email mittente verificata
   - `SENDER_NAME` = `Carminello`
   - `SITE_URL` = l'indirizzo pubblico del sito (senza barra finale)
   - `WEBHOOK_SECRET` = una parola segreta a tua scelta (es. 20 lettere e numeri a caso)

### Dire al database di avvisare (Database Webhooks)
6. Supabase → **Database → Webhooks** → *Create a new hook*:
   - Nome `avvisi-ordini`, tabella `orders`, eventi **Insert** e **Update**,
     tipo **Supabase Edge Functions** → funzione `notifica`,
     in *HTTP Headers* aggiungi `x-webhook-secret` = la parola segreta di sopra → Create.
   - Ripeti con nome `avvisi-locali`, tabella `profiles`, solo **Insert**, stessa funzione e stesso header.

Da questo momento: nuovo ordine → email a te e conferma al cliente (con IBAN se bonifico);
ordine spedito → email al cliente; nuovo locale registrato → email a te.

---

## 6. Come si usa tutti i giorni (il pannello)

Apri il sito → **Pannello** (compare solo se sei collegato con l'account amministratore).

**Ordini**
- *Da pagare*: bonifici non ancora arrivati e carte non completate. Quando vedi il bonifico sul conto,
  premi **Segna pagato**: l'ordine passa in "Da spedire" e il cliente riceve l'email.
- *Da spedire*: pagati (o in contrassegno). Quando spedisci, premi **Segna spedito**.
- **Dettagli** mostra indirizzo, telefono, note e righe dell'ordine.
- **Verifica SumUp** ricontrolla un pagamento con carta se qualcosa si fosse perso.

**Clienti**
- *Locali da attivare*: ogni nuovo locale registrato compare qui. Lo chiami, concordate il prezzo, scrivi il
  prezzo del cartone da 20 e premi **Salva e attiva**. Da quel momento vede il suo prezzo e ordina da solo
  (anche in contrassegno, +5 €).
- Puoi cambiare il prezzo di un locale in qualsiasi momento (vale dagli ordini successivi) o **sospenderlo**.

**Prodotti**
- Prezzo per i privati, nome in italiano e inglese, pezzi per cartone, attivo/non attivo.
- Per aggiungere un nuovo prodotto in futuro: chiedi a Claude, servono due righe nel database.

**Impostazioni**
- IBAN, email avvisi, fasce di spedizione, supplemento contrassegno. Le modifiche valgono subito.

---

## 6bis. Stato al 8 settembre 2026 (fatto insieme a Claude)
- Supabase, sito, dashboard (https://alleysrl.github.io/carminello-dashboard/), Brevo, i tre programmi e i due webhook sono **già configurati e provati**.
- Nelle funzioni la voce "Verify JWT with legacy secret" è **spenta** di proposito: le funzioni controllano da sole chi le chiama.
- Manca solo SumUp: quando avrai la chiave, aggiungi in *Edge Functions → Secrets* `SUMUP_API_KEY` e `SUMUP_MERCHANT_CODE`. Nient'altro da cambiare.

## 7. Se qualcosa non va

| Problema | Cosa controllare |
|---|---|
| Striscia gialla "non ancora collegato" | `config.js` ha ancora `INCOLLA_QUI`. |
| Non arriva l'email di conferma account | SMTP Brevo in Supabase (punto 1.8); controlla lo spam. |
| "Pagamento con carta non ancora configurato" | Mancano i secrets SumUp o la funzione `sumup-checkout` non è caricata. |
| "SumUp ha rifiutato la richiesta" | Pagamenti online non attivi sull'account SumUp, o merchant code sbagliato. |
| Non arrivano gli avvisi email | Webhook non creato, `x-webhook-secret` diverso dal secret, o mittente non verificato su Brevo. Su Supabase → Edge Functions → `notifica` → *Logs* si vede l'errore. |
| Il pannello dice "riservato al titolare" | Non hai eseguito la riga SQL del punto 2. |
| Un locale non vede il prezzo | Nel pannello → Clienti deve essere **Attivo** con un prezzo salvato. |

**Cose da non fare:** non caricare mai su GitHub file con chiavi segrete (SumUp, Brevo); non cancellare
righe dalle tabelle `orders` a mano (annulla gli ordini dal pannello); non condividere la password del database.
