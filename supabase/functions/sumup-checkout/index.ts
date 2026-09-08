// ============================================================================
// SUMUP — crea la pagina di pagamento per un ordine
// Chiamata dal sito (ordine.html) con l'utente collegato. Verifica che l'ordine
// sia suo e non pagato, chiede a SumUp una "hosted checkout" e restituisce l'URL.
// Secrets necessari: SUMUP_API_KEY, SUMUP_MERCHANT_CODE (vedi GUIDA.md)
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

// Chiavi del progetto: Supabase ora le fornisce come elenco JSON; resta il ripiego sulle vecchie.
function pickKey(json: string | undefined, legacy: string | undefined): string {
  if (json) { try { const j = JSON.parse(json); const v = Array.isArray(j) ? j[0] : Object.values(j)[0]; const k = typeof v === "string" ? v : (v?.api_key || v?.key || v?.secret); if (k) return k; } catch (_) { /* ignora */ } }
  return legacy || "";
}
const ANON_KEY = pickKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), Deno.env.get("SUPABASE_ANON_KEY"));
const SERVICE_KEY = pickKey(Deno.env.get("SUPABASE_SECRET_KEYS"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON = ANON_KEY;
    const SERVICE = SERVICE_KEY;
    const SUMUP_KEY = Deno.env.get("SUMUP_API_KEY");
    const MERCHANT = Deno.env.get("SUMUP_MERCHANT_CODE");
    if (!SUMUP_KEY || !MERCHANT) return json({ error: "Pagamento con carta non ancora configurato (SumUp)." }, 500);

    // 1. chi sta chiamando?
    const auth = req.headers.get("Authorization") || "";
    const userClient = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Non collegato" }, 401);

    const { order_id, lang, return_url } = await req.json();
    const admin = createClient(SUPABASE_URL, SERVICE);
    const { data: o } = await admin.from("orders").select("*").eq("id", order_id).maybeSingle();
    if (!o || o.user_id !== user.id) return json({ error: "Ordine non trovato" }, 404);
    if (o.pagato) return json({ error: "Ordine già pagato" }, 400);
    if (o.stato === "annullato") return json({ error: "Ordine annullato" }, 400);
    if (o.metodo_pagamento !== "carta") return json({ error: "Questo ordine non è con carta" }, 400);

    // 2. chiede a SumUp una pagina di pagamento
    const body = {
      checkout_reference: `ORD-${o.numero}-${Date.now()}`,
      amount: Number(o.totale),
      currency: "EUR",
      merchant_code: MERCHANT,
      description: `Carminello — ordine ${o.numero}`,
      hosted_checkout: { enabled: true },
      redirect_url: return_url,   // dove torna il cliente dopo aver pagato
    };
    const r = await fetch("https://api.sumup.com/v0.1/checkouts", {
      method: "POST",
      headers: { Authorization: `Bearer ${SUMUP_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await r.json();
    if (!r.ok || !data.id) {
      console.error("SumUp error", r.status, data);
      return json({ error: "SumUp ha rifiutato la richiesta: " + (data.message || data.error_message || r.status) }, 502);
    }
    const url = data.hosted_checkout_url || data.hosted_checkout?.url;
    if (!url) return json({ error: "SumUp non ha restituito la pagina di pagamento" }, 502);

    // 3. memorizza l'id del checkout sull'ordine
    await admin.from("orders").update({ sumup_checkout_id: data.id }).eq("id", o.id);
    return json({ url, checkout_id: data.id, lang });
  } catch (e) {
    console.error(e);
    return json({ error: String(e?.message || e) }, 500);
  }
});
