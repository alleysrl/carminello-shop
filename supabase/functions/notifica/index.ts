// ============================================================================
// NOTIFICHE EMAIL — chiamata automaticamente dal database (Database Webhook)
// quando: arriva un nuovo ordine, un ordine cambia stato, si registra un locale.
// Invia le email con Brevo (gratuito fino a 300 email/giorno).
// Secrets: BREVO_API_KEY, SENDER_EMAIL, SENDER_NAME, SITE_URL, WEBHOOK_SECRET
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

// Chiavi del progetto: Supabase ora le fornisce come elenco JSON; resta il ripiego sulle vecchie.
function pickKey(json: string | undefined, legacy: string | undefined): string {
  if (json) { try { const j = JSON.parse(json); const v = Array.isArray(j) ? j[0] : Object.values(j)[0]; const k = typeof v === "string" ? v : (v?.api_key || v?.key || v?.secret); if (k) return k; } catch (_) { /* ignora */ } }
  return legacy || "";
}
const ANON_KEY = pickKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), Deno.env.get("SUPABASE_ANON_KEY"));
const SERVICE_KEY = pickKey(Deno.env.get("SUPABASE_SECRET_KEYS"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

const eur = (n: unknown) => new Intl.NumberFormat("it-IT", { style: "currency", currency: "EUR" }).format(Number(n || 0));
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

async function sendMail(to: string, subject: string, html: string) {
  const KEY = Deno.env.get("BREVO_API_KEY");
  if (!KEY || !to) { console.log("Email non inviata (manca BREVO_API_KEY o destinatario)", subject); return; }
  const r = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": KEY, "Content-Type": "application/json" },
    body: JSON.stringify({
      sender: { name: Deno.env.get("SENDER_NAME") || "Carminello", email: Deno.env.get("SENDER_EMAIL") || "info@carminello.eu" },
      to: [{ email: to }], subject, htmlContent: html,
    }),
  });
  if (!r.ok) console.error("Brevo", r.status, await r.text());
}

function layout(title: string, body: string) {
  return `<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#22170f">
    <div style="background:#1c1512;padding:18px 24px;border-radius:12px 12px 0 0"><span style="color:#fff;font-size:22px;font-weight:bold">Carminello</span></div>
    <div style="background:#faf6ee;padding:24px;border:1px solid #e6dccb;border-top:0;border-radius:0 0 12px 12px">
      <h2 style="margin-top:0;color:#c8452b">${esc(title)}</h2>${body}
      <p style="color:#8a7a6c;font-size:12px;margin-top:28px">ALLEYS SRL · Via del Cantone, 91 – 50019 Sesto Fiorentino (FI) · P.IVA 07179450486 · info@carminello.eu · WhatsApp +39 379 3504521</p>
    </div></div>`;
}

function righeHtml(o: any) {
  const rows = (o.righe || []).map((r: any) => `<tr><td style="padding:6px 0;border-bottom:1px solid #e6dccb">${r.qty} × ${esc(r.nome)}</td><td style="text-align:right;padding:6px 0;border-bottom:1px solid #e6dccb">${eur(r.totale)}</td></tr>`).join("");
  return `<table style="width:100%;border-collapse:collapse">${rows}
    <tr><td style="padding:6px 0">Spedizione</td><td style="text-align:right">${Number(o.spedizione) ? eur(o.spedizione) : "gratis"}</td></tr>
    ${Number(o.supplemento) ? `<tr><td style="padding:6px 0">Contrassegno</td><td style="text-align:right">${eur(o.supplemento)}</td></tr>` : ""}
    <tr><td style="padding:10px 0;font-weight:bold;font-size:18px">Totale</td><td style="text-align:right;font-weight:bold;font-size:18px;color:#c8452b">${eur(o.totale)}</td></tr></table>`;
}
function indirizzoHtml(a: any) {
  return esc([a?.ragione_sociale, `${a?.nome || ""} ${a?.cognome || ""}`.trim(), a?.via, `${a?.cap || ""} ${a?.citta || ""} ${a?.prov ? "(" + a.prov + ")" : ""}`.trim(), a?.telefono].filter((x) => x && String(x).trim()).join(" · "));
}

// ---- Notifiche push (telefono/Mac) a tutti i dispositivi registrati dall'amministratore ----
async function inviaPush(admin: any, titolo: string, testo: string, url: string, badge?: number, tag?: string) {
  const PUB = Deno.env.get("VAPID_PUBLIC_KEY"), PRIV = Deno.env.get("VAPID_PRIVATE_KEY");
  if (!PUB || !PRIV) { console.log("Push non inviata: mancano le chiavi VAPID"); return { inviate: 0 }; }
  webpush.setVapidDetails(Deno.env.get("VAPID_SUBJECT") || "mailto:info@carminello.eu", PUB, PRIV);
  const { data: subs } = await admin.from("push_subscriptions").select("endpoint, sub");
  let inviate = 0;
  for (const s of subs || []) {
    try { await webpush.sendNotification(s.sub, JSON.stringify({ title: titolo, body: testo, url, badge, tag: tag || ("carminello-" + Date.now()) }), { urgency: "high", TTL: 3600 }); inviate++; }
    catch (e: any) {
      console.error("push", s.endpoint.slice(0, 60), e?.statusCode || e?.message);
      if (e?.statusCode === 404 || e?.statusCode === 410) await admin.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
    }
  }
  console.log("push inviate", inviate, "su", (subs || []).length, "dispositivi:", titolo);
  return { inviate };
}

const PM: Record<string, string> = { carta: "Carta (SumUp)", bonifico: "Bonifico bancario", contrassegno: "Contrassegno" };
const ST: Record<string, string> = { da_pagare: "In attesa di pagamento", da_spedire: "In preparazione", spedito: "Spedito", annullato: "Annullato" };

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const payload = await req.json();

    // Prova manuale dalla dashboard: serve il token di un amministratore
    if (payload?.type === "TEST") {
      const userClient = createClient(Deno.env.get("SUPABASE_URL")!, ANON_KEY, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
      const { data: { user } } = await userClient.auth.getUser();
      const adm = createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_KEY);
      const { data: prof } = user ? await adm.from("profiles").select("ruolo").eq("id", user.id).maybeSingle() : { data: null };
      if (!prof || prof.ruolo !== "admin") return new Response(JSON.stringify({ error: "Non autorizzato" }), { status: 403, headers: { ...cors, "Content-Type": "application/json" } });
      const r = await inviaPush(adm, "Carminello Dashboard", "Le notifiche push funzionano su questo dispositivo.", "#/cruscotto", 1, "test");
      return new Response(JSON.stringify({ ok: true, ...r }), { headers: { ...cors, "Content-Type": "application/json" } });
    }

    const secret = Deno.env.get("WEBHOOK_SECRET");
    if (secret && req.headers.get("x-webhook-secret") !== secret) return new Response("forbidden", { status: 403 });
    const { type, table, record, old_record } = payload;
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_KEY);
    const { data: imps } = await admin.from("impostazioni").select("chiave,valore");
    const imp: Record<string, any> = {}; (imps || []).forEach((r: any) => imp[r.chiave] = r.valore);
    const ownerEmail = imp.notifiche?.email || "info@carminello.eu";
    const site = (Deno.env.get("SITE_URL") || "").replace(/\/$/, "");

    // ---- NUOVO ORDINE ----
    if (table === "orders" && type === "INSERT") {
      const o = record;
      const { data: p } = await admin.from("profiles").select("email,nome,ragione_sociale,tipo").eq("id", o.user_id).maybeSingle();
      const cliente = p?.ragione_sociale || p?.nome || p?.email || "cliente";
      // 1) subito la push sul telefono/Mac del titolare (priorità alta), con il numero degli ordini non ancora visti
      try {
        const { count } = await admin.from("orders").select("id", { count: "exact", head: true }).eq("visto", false);
        await inviaPush(admin, `Nuovo ordine n. ${o.numero}`, `${cliente}: ${o.cartoni} cartoni, ${eur(o.totale)} (${PM[o.metodo_pagamento]})`, "#/ordini", count || 1, "ordine-" + o.numero);
      } catch (e) { console.error("push ordine", e); }
      // 2) email al titolare
      await sendMail(ownerEmail, `Nuovo ordine n. ${o.numero} — ${cliente} — ${eur(o.totale)}`,
        layout(`Nuovo ordine n. ${o.numero}`, `
          <p><b>Cliente:</b> ${esc(cliente)} (${o.tipo === "b2b" ? "locale" : o.tipo === "rivenditore" ? "rivenditore" : "privato"}) · ${esc(p?.email)}</p>
          <p><b>Consegna:</b> ${indirizzoHtml(o.indirizzo)}</p>
          <p><b>Pagamento:</b> ${PM[o.metodo_pagamento]} · <b>Stato:</b> ${ST[o.stato]}</p>
          ${o.note ? `<p><b>Note:</b> ${esc(o.note)}</p>` : ""}
          ${righeHtml(o)}
          ${site ? `<p style="margin-top:20px"><a href="${site}/admin.html" style="background:#c8452b;color:#fff;padding:10px 18px;border-radius:999px;text-decoration:none">Apri il pannello</a></p>` : ""}`));
      // 3) email al cliente
      let extra = "";
      if (o.metodo_pagamento === "bonifico") {
        const b = imp.bonifico || {};
        extra = `<div style="background:#fbf1da;border-left:4px solid #e0b25a;padding:12px 16px;border-radius:0 10px 10px 0;margin:16px 0">
          <b>Come pagare con bonifico</b><br>Intestatario: ${esc(b.intestatario)}<br>IBAN: <b>${esc(b.iban)}</b>${b.banca ? `<br>Banca: ${esc(b.banca)}` : ""}<br>Importo: <b>${eur(o.totale)}</b><br>Causale: <b>Ordine ${o.numero}</b><br><small>Spediamo appena riceviamo il bonifico.</small></div>`;
      } else if (o.metodo_pagamento === "contrassegno") {
        extra = `<p>Pagherai alla consegna, in contanti: <b>${eur(o.totale)}</b>.</p>`;
      } else if (!o.pagato) {
        extra = `<p>Se non hai completato il pagamento con carta, puoi farlo dalla pagina del tuo ordine.</p>`;
      }
      if (p?.email) await sendMail(p.email, `Carminello — abbiamo ricevuto il tuo ordine n. ${o.numero}`,
        layout(`Grazie per il tuo ordine!`, `
          <p>Ciao ${esc(p?.nome || "")}, abbiamo ricevuto il tuo ordine <b>n. ${o.numero}</b>.</p>
          ${righeHtml(o)}${extra}
          <p><b>Consegna a:</b> ${indirizzoHtml(o.indirizzo)}</p>
          ${site ? `<p><a href="${site}/ordine.html?id=${o.id}" style="background:#c8452b;color:#fff;padding:10px 18px;border-radius:999px;text-decoration:none">Vedi il tuo ordine</a></p>` : ""}
          <p>Per qualsiasi domanda rispondi a questa email o scrivici su WhatsApp.</p>`));
    }

    // ---- ORDINE CAMBIA STATO (spedito / pagato) → avviso al cliente ----
    if (table === "orders" && type === "UPDATE") {
      const o = record, old = old_record || {};
      const { data: p } = await admin.from("profiles").select("email,nome").eq("id", o.user_id).maybeSingle();
      if (p?.email && o.stato === "spedito" && old.stato !== "spedito") {
        await sendMail(p.email, `Carminello — il tuo ordine n. ${o.numero} è partito!`,
          layout("Il tuo ordine è in viaggio", `<p>Ciao ${esc(p.nome || "")}, il tuo ordine <b>n. ${o.numero}</b> è stato spedito. Di solito arriva in 2–3 giorni lavorativi.</p>${righeHtml(o)}<p>Buona pizza!</p>`));
      }
      if (p?.email && o.pagato && !old.pagato && o.metodo_pagamento !== "carta") {
        await sendMail(p.email, `Carminello — pagamento ricevuto per l'ordine n. ${o.numero}`,
          layout("Pagamento ricevuto", `<p>Ciao ${esc(p.nome || "")}, abbiamo ricevuto il pagamento dell'ordine <b>n. ${o.numero}</b>. Lo prepariamo subito.</p>`));
      }
    }

    // ---- PRIVATO CHE CHIEDE DI DIVENTARE LOCALE/RIVENDITORE → avviso al titolare ----
    if (table === "profiles" && type === "UPDATE" && (record.tipo === "b2b" || record.tipo === "rivenditore") && old_record?.tipo === "b2c") {
      const c = record; const cosa = c.tipo === "rivenditore" ? "rivenditore" : "locale";
      try { await inviaPush(admin, `Richiesta: vuole diventare ${cosa}`, `${c.ragione_sociale || c.email} · ${c.telefono || ""}`, "#/clienti/attivare"); } catch (e) { console.error("push upgrade", e); }
      await sendMail(ownerEmail, `${c.ragione_sociale || c.email} chiede di diventare ${cosa}`,
        layout(`Richiesta di passaggio a ${cosa}`, `
          <p>Un cliente privato ha chiesto di passare ad account ${cosa}:</p>
          <p><b>${esc(c.ragione_sociale)}</b><br>${esc(c.nome)} ${esc(c.cognome)}<br>${esc(c.email)} · ${esc(c.telefono)}<br>P.IVA ${esc(c.piva)}${c.sdi ? " · SDI " + esc(c.sdi) : ""}${c.pec ? " · PEC " + esc(c.pec) : ""}</p>
          <p>Contattalo, concorda il prezzo e attivalo dalla dashboard.</p>
          ${site ? `<p><a href="https://alleysrl.github.io/carminello-dashboard/#/clienti/attivare" style="background:#c8452b;color:#fff;padding:10px 18px;border-radius:999px;text-decoration:none">Apri la dashboard</a></p>` : ""}`));
    }

    // ---- NUOVO LOCALE REGISTRATO → avviso al titolare ----
    if (table === "profiles" && type === "INSERT" && (record.tipo === "b2b" || record.tipo === "rivenditore")) {
      const c = record;
      try { await inviaPush(admin, c.tipo === "rivenditore" ? "Nuovo rivenditore da attivare" : "Nuovo locale da attivare", `${c.ragione_sociale || c.email} · ${c.telefono || ""}`, "#/clienti/attivare"); } catch (e) { console.error("push registrazione", e); }
      await sendMail(ownerEmail, `Nuovo ${c.tipo === "rivenditore" ? "rivenditore" : "locale"} registrato: ${c.ragione_sociale || c.email}`,
        layout(c.tipo === "rivenditore" ? "Nuovo rivenditore da attivare" : "Nuovo locale da attivare", `
          <p><b>${esc(c.ragione_sociale)}</b><br>${esc(c.nome)} ${esc(c.cognome)}<br>${esc(c.email)} · ${esc(c.telefono)}<br>P.IVA ${esc(c.piva)}${c.sdi ? " · SDI " + esc(c.sdi) : ""}${c.pec ? " · PEC " + esc(c.pec) : ""}</p>
          <p>Contattalo, concorda il prezzo e attivalo dal pannello: da quel momento ordina da solo.</p>
          ${site ? `<p><a href="${site}/admin.html" style="background:#c8452b;color:#fff;padding:10px 18px;border-radius:999px;text-decoration:none">Apri il pannello</a></p>` : ""}`));
    }
    return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e?.message || e) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
