// ============================================================================
// INVITA CLIENTE — l'agente registra un esercente/rivenditore sul posto.
// Il cliente riceve l'email "Sei stato invitato" e sceglie la password.
// Secrets usati: SITE_URL (già presente) + chiavi del progetto.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

function pickKey(json: string | undefined, legacy: string | undefined): string {
  if (json) { try { const j = JSON.parse(json); const v = Array.isArray(j) ? j[0] : Object.values(j)[0]; const k = typeof v === "string" ? v : (v?.api_key || v?.key || v?.secret); if (k) return k; } catch (_) { /* ignora */ } }
  return legacy || "";
}
const ANON_KEY = pickKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), Deno.env.get("SUPABASE_ANON_KEY"));
const SERVICE_KEY = pickKey(Deno.env.get("SUPABASE_SECRET_KEYS"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, ANON_KEY, { global: { headers: { Authorization: req.headers.get("Authorization") || "" } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Devi accedere" }, 401);
    const admin = createClient(url, SERVICE_KEY);
    const { data: ag } = await admin.from("profiles").select("id,ruolo,approvato,codice_agente,nome,cognome").eq("id", user.id).maybeSingle();
    if (!ag || ag.ruolo !== "agente" || !ag.approvato) return json({ error: "Riservato agli agenti attivi" }, 403);

    const b = await req.json();
    const email = String(b.email || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "Email non valida" }, 400);
    const tipo = b.tipo === "rivenditore" ? "rivenditore" : "b2b";
    const piva = String(b.piva || "").replace(/\D/g, "");
    if (piva.length !== 11 || !String(b.ragione_sociale || "").trim()) return json({ error: "Servono Partita IVA (11 cifre) e ragione sociale" }, 400);
    if (!String(b.telefono || "").trim()) return json({ error: "Serve il telefono del cliente" }, 400);

    const meta: Record<string, unknown> = {
      tipo, origine: "invito", codice_agente: ag.codice_agente, lingua: "it",
      nome: String(b.nome || "").trim(), cognome: String(b.cognome || "").trim(), telefono: String(b.telefono || "").trim(),
      ragione_sociale: String(b.ragione_sociale || "").trim(), piva,
      sdi: String(b.sdi || "").trim().toUpperCase(), pec: String(b.pec || "").trim(),
    };
    if (b.indirizzo && typeof b.indirizzo === "object") meta.indirizzo = { via: b.indirizzo.via || "", citta: b.indirizzo.citta || "", cap: b.indirizzo.cap || "", prov: String(b.indirizzo.prov || "").toUpperCase() };

    const site = (Deno.env.get("SITE_URL") || "").replace(/\/$/, "");
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: meta, redirectTo: site + "/account.html" });
    if (error) {
      const gia = /already|exists|registered/i.test(error.message);
      return json({ error: gia ? "Questo cliente è già registrato su Carminello: chiedi al titolare di collegarlo a te." : error.message }, gia ? 409 : 400);
    }
    return json({ ok: true, id: data.user?.id });
  } catch (e: any) {
    console.error(e);
    return json({ error: String(e?.message || e) }, 500);
  }
});
