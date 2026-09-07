/* ============================================================================
   CARRELLO — salvato nel telefono/computer del cliente (localStorage)
   Contiene solo "quanti cartoni di quale prodotto". I prezzi veri li ricalcola
   sempre il database al momento dell'ordine, così nessuno può imbrogliare.
   ========================================================================== */
const Cart = (function () {
  "use strict";
  const KEY = "carminello_cart_v1";

  function read() {
    try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; }
  }
  function write(c) { try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) {} ; notify(); }
  function notify() { document.dispatchEvent(new CustomEvent("cart:change")); }

  function get() { return read(); }
  function qty(id) { return read()[id] || 0; }
  function set(id, n) {
    const c = read(); n = Math.max(0, Math.floor(Number(n) || 0));
    if (n === 0) delete c[id]; else c[id] = n;
    write(c);
  }
  function add(id, n) { set(id, qty(id) + (n || 1)); }
  function clear() { write({}); }
  function count() { return Object.values(read()).reduce((a, b) => a + b, 0); }

  // Costo spedizione in base al numero totale di cartoni
  function spedizione(nCartoni) {
    if (nCartoni <= 0) return 0;
    for (const fascia of CONFIG.SPEDIZIONE) if (nCartoni <= fascia.fino_a) return fascia.costo;
    return 0;
  }

  // Totali del carrello dato il catalogo (già con i prezzi giusti per il cliente)
  function totali(catalogo, metodo) {
    const c = read(); let sub = 0, cartoni = 0; const righe = [];
    for (const p of catalogo) {
      const n = c[p.id] || 0; if (!n) continue;
      const prezzo = Number(p.prezzo || 0);
      righe.push({ id: p.id, nome: p.nome_it, nome_en: p.nome_en, qty: n, prezzo: prezzo, pezzi: p.pezzi, totale: round(prezzo * n) });
      sub += prezzo * n; cartoni += n;
    }
    const sped = spedizione(cartoni);
    const supp = metodo === "contrassegno" ? CONFIG.CONTRASSEGNO_SUPPLEMENTO : 0;
    return { righe, cartoni, subtotale: round(sub), spedizione: round(sped), supplemento: round(supp), totale: round(sub + sped + supp) };
  }
  function round(n) { return Math.round(n * 100) / 100; }

  return { get, qty, set, add, clear, count, spedizione, totali };
})();
