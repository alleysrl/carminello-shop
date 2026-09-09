// ============================================================================
// PARTITA IVA — cerca ragione sociale e indirizzo nell'archivio VIES (UE, gratuito)
// Chiamata dal sito durante la registrazione di locali e rivenditori.
// Nessun segreto necessario. "Verify JWT" va tenuto OFF (chiamata pubblica).
// ============================================================================
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const titolo = (s: string) => s.toLowerCase().replace(/(^|[\s'/-])(\S)/g, (m, p, c) => p + c.toUpperCase());

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    let piva = "";
    if (req.method === "POST") { const b = await req.json().catch(() => ({})); piva = String(b.piva || ""); }
    else piva = new URL(req.url).searchParams.get("piva") || "";
    piva = piva.replace(/\D/g, "");
    if (piva.length !== 11) return json({ valid: false, error: "La Partita IVA deve avere 11 cifre" }, 400);

    const r = await fetch(`https://ec.europa.eu/taxation_customs/vies/rest-api/ms/IT/vat/${piva}`, { headers: { Accept: "application/json" } });
    if (!r.ok) return json({ valid: false, error: "Archivio VIES non raggiungibile, riprova tra poco" }, 502);
    const d = await r.json();
    if (!d.isValid) return json({ valid: false, error: "Partita IVA non trovata o non attiva" });

    // Indirizzo VIES: "VIA ROMA 10 \n50100 FIRENZE FI\n"
    const righe = String(d.address || "").split("\n").map((x: string) => x.trim()).filter(Boolean);
    let via = "", cap = "", citta = "", prov = "";
    const ultima = righe[righe.length - 1] || "";
    const m = ultima.match(/^(\d{5})\s+(.+?)\s+([A-Z]{2})$/);
    if (m) { cap = m[1]; citta = titolo(m[2]); prov = m[3]; via = titolo(righe.slice(0, -1).join(", ")); }
    else via = titolo(righe.join(", "));
    return json({ valid: true, piva, ragione_sociale: String(d.name || "").trim(), via, cap, citta, prov, indirizzo_grezzo: righe.join(", ") });
  } catch (e) {
    return json({ valid: false, error: String((e as Error)?.message || e) }, 500);
  }
});
