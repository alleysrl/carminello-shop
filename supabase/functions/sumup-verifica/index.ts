// ============================================================================
// SUMUP — verifica se un ordine è stato pagato e, se sì, lo segna pagato.
// Chiamata dal sito al ritorno da SumUp (ordine.html) e dal pannello.
// Può chiamarla il proprietario dell'ordine o l'amministratore.
// ============================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

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
    const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const SUMUP_KEY = Deno.env.get("SUMUP_API_KEY");
    if (!SUMUP_KEY) return json({ error: "SumUp non configurato" }, 500);

    const auth = req.headers.get("Authorization") || "";
    const userClient = createClient(SUPABASE_URL, ANON, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Non collegato" }, 401);

    const { order_id } = await req.json();
    const admin = createClient(SUPABASE_URL, SERVICE);
    const [{ data: o }, { data: prof }] = await Promise.all([
      admin.from("orders").select("*").eq("id", order_id).maybeSingle(),
      admin.from("profiles").select("ruolo").eq("id", user.id).maybeSingle(),
    ]);
    if (!o) return json({ error: "Ordine non trovato" }, 404);
    if (o.user_id !== user.id && prof?.ruolo !== "admin") return json({ error: "Non autorizzato" }, 403);
    if (o.pagato) return json({ pagato: true, status: "PAID" });
    if (!o.sumup_checkout_id) return json({ pagato: false, status: "NESSUN_CHECKOUT" });

    const r = await fetch(`https://api.sumup.com/v0.1/checkouts/${o.sumup_checkout_id}`, {
      headers: { Authorization: `Bearer ${SUMUP_KEY}` },
    });
    const data = await r.json();
    if (!r.ok) { console.error("SumUp", r.status, data); return json({ pagato: false, status: "ERRORE_SUMUP" }); }

    // SumUp: PENDING → PAID / FAILED. Confronta anche l'importo per sicurezza.
    const paid = data.status === "PAID" && Math.abs(Number(data.amount) - Number(o.totale)) < 0.01;
    if (paid) {
      await admin.from("orders").update({
        pagato: true, pagato_il: new Date().toISOString(),
        stato: o.stato === "da_pagare" ? "da_spedire" : o.stato,
      }).eq("id", o.id);
    }
    return json({ pagato: paid, status: data.status });
  } catch (e) {
    console.error(e);
    return json({ error: String(e?.message || e) }, 500);
  }
});
