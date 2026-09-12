/* ============================================================================
   CARMINELLO SHOP — CONFIGURAZIONE
   ----------------------------------------------------------------------------
   Questo è l'UNICO file da compilare a mano. Tutto il resto funziona da solo.

   ⚠️ Le chiavi qui sotto sono PUBBLICHE (possono stare nel sito).
      Le chiavi segrete (SumUp, email) NON vanno qui: vanno nei "Secrets"
      di Supabase, come spiegato in GUIDA.md.
   ========================================================================== */
const CONFIG = {
  VERSIONE: "2026-09-12g",   // compare in fondo al sito: serve a capire quale versione ha il telefono

  // ---- Supabase (database, account, ordini) ---------------------------------
  // Si trovano su supabase.com → il tuo progetto → Project Settings → API
  SUPABASE_URL: "https://pbohjckxocshkwoyjiko.supabase.co",          // es. https://abcdefgh.supabase.co
  SUPABASE_KEY: "sb_publishable_yIq72Tx8gohzpKjui7oJMw_VTeNzqh5",    // inizia con sb_publishable_ oppure eyJ...

  // ---- Dati azienda (compaiono nel sito e nelle condizioni di vendita) ------
  AZIENDA: {
    marchio: "Carminello",
    ragione_sociale: "ALLEYS SRL",
    indirizzo: "Via del Cantone, 91 – 50019 Sesto Fiorentino (FI), Italia",
    piva: "07179450486",
    rea: "FI-685260",
    email: "info@carminello.eu",
    telefono: "+39 379 3504521",
    whatsapp: "393793504521",           // solo cifre, con prefisso, senza +
    social: {
      facebook: "https://www.facebook.com/",
      instagram: "https://www.instagram.com/",
      youtube: "https://www.youtube.com/"
    }
  },

  // ---- Bonifico bancario (mostrato al cliente che sceglie il bonifico) ------
  BONIFICO: {
    intestatario: "ALLEYS SRL",
    iban: "INCOLLA QUI L'IBAN",
    banca: "",                           // facoltativo, es. "Banca Intesa"
    bic: ""                              // facoltativo
  },

  // ---- Spedizione: costo in base al numero di cartoni -----------------------
  // Si legge così: "fino a 1 cartone 6,99 €; fino a 2 → 15,98 €; fino a 3 → 20,97 €;
  // fino a 9 → 24,99 €; oltre → gratis".
  SPEDIZIONE: [
    { fino_a: 1, costo: 6.99 },
    { fino_a: 2, costo: 15.98 },
    { fino_a: 3, costo: 20.97 },
    { fino_a: 9, costo: 24.99 },
    { fino_a: Infinity, costo: 0 }
  ],

  // ---- Contrassegno: solo per i locali (B2B), con supplemento --------------
  CONTRASSEGNO_SUPPLEMENTO: 5.00,

  // ---- Solo Italia ----------------------------------------------------------
  PAESI: ["IT"],

  // ---- Prodotti "di riserva" -------------------------------------------------
  // Usati solo finché Supabase non è collegato, così il sito si vede lo stesso.
  // Quelli veri stanno nella tabella "products" e si modificano dal pannello.
  PRODOTTI_DEMO: [
    {
      id: "base-33-cartone-8", canale: "b2c", attivo: true, ordine: 1,
      nome_it: "Base Pizza Carminello 33 cm — cartone da 8",
      nome_en: "Carminello 33 cm Pizza Base — box of 8",
      descr_it: "Base pizza artigianale da 33 cm con bordo rialzato, cotta a infrarossi. Impasto a lunga maturazione, alta digeribilità, farine 100% italiane. Si conserva oltre 30 giorni a temperatura ambiente, senza frigorifero.",
      descr_en: "Handcrafted 33 cm pizza base with raised crust, infrared-baked. Long-fermented dough, highly digestible, 100% Italian flours. Keeps for over 30 days at room temperature, no fridge needed.",
      pezzi: 8, prezzo: 14.99, immagine: "assets/img/base-classica.webp"
    },
    {
      id: "base-33-cartone-20", canale: "b2b", attivo: true, ordine: 2,
      nome_it: "Base Pizza Carminello 33 cm — cartone da 20 (buste da 2)",
      nome_en: "Carminello 33 cm Pizza Base — box of 20 (packs of 2)",
      descr_it: "Formato professionale: cartone da 20 basi in 10 buste da 2. Base 33 cm con bordo rialzato, cotta a infrarossi, oltre 30 giorni di conservazione a temperatura ambiente.",
      descr_en: "Professional format: box of 20 bases in 10 packs of 2. 33 cm base with raised crust, infrared-baked, keeps for over 30 days at room temperature.",
      pezzi: 20, prezzo: null, immagine: "assets/img/base-classica.webp"
    }
  ]
};
