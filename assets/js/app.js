/* ============================================================================
   APP — parti comuni a tutte le pagine: intestazione, piè di pagina,
   collegamento a Supabase, utente, catalogo, avvisi.
   ========================================================================== */
const App = (function () {
  "use strict";

  const configured = CONFIG.SUPABASE_URL.indexOf("INCOLLA") === -1 && CONFIG.SUPABASE_KEY.indexOf("INCOLLA") === -1;
  const db = configured && window.supabase ? window.supabase.createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_KEY) : null;

  let user = null, profile = null;
  const listeners = [];

  // ---------- utilità ----------
  function money(n) {
    n = Number(n || 0);
    return new Intl.NumberFormat(Lang.get() === "en" ? "en-GB" : "it-IT", { style: "currency", currency: "EUR" }).format(n);
  }
  function dateFmt(iso) {
    if (!iso) return "";
    return new Date(iso).toLocaleDateString(Lang.get() === "en" ? "en-GB" : "it-IT", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
  function qs(name) { return new URLSearchParams(location.search).get(name); }

  function toast(msg, type) {
    let box = document.getElementById("toast-box");
    if (!box) { box = document.createElement("div"); box.id = "toast-box"; document.body.appendChild(box); }
    const t = document.createElement("div"); t.className = "toast " + (type || ""); t.textContent = msg;
    box.appendChild(t);
    setTimeout(() => t.classList.add("show"), 10);
    setTimeout(() => { t.classList.remove("show"); setTimeout(() => t.remove(), 400); }, 4200);
  }

  // ---------- utente ----------
  async function loadProfile() {
    if (!db || !user) { profile = null; return null; }
    const { data } = await db.from("profiles").select("*").eq("id", user.id).maybeSingle();
    profile = data || null;
    return profile;
  }
  function isAdmin() { return !!(profile && profile.ruolo === "admin"); }
  function isB2B() { return !!(profile && (profile.tipo === "b2b" || profile.tipo === "rivenditore")); }
  function b2bAttivo() { return isB2B() && !!profile.approvato; }
  function onAuth(fn) { listeners.push(fn); }
  function fire() { listeners.forEach(fn => { try { fn(user, profile); } catch (e) { console.error(e); } }); renderHeader(); }

  // Impostazioni (spedizione, contrassegno, bonifico) lette dal database:
  // così quello che il titolare cambia dal pannello vale subito anche qui.
  async function loadImpostazioni() {
    if (!db) return;
    const { data } = await db.from("impostazioni").select("chiave,valore");
    (data || []).forEach(r => {
      if (r.chiave === "spedizione" && Array.isArray(r.valore)) CONFIG.SPEDIZIONE = r.valore.map(f => ({ fino_a: f.fino_a == null ? Infinity : Number(f.fino_a), costo: Number(f.costo || 0) }));
      if (r.chiave === "contrassegno" && r.valore) CONFIG.CONTRASSEGNO_SUPPLEMENTO = Number(r.valore.supplemento || 0);
      if (r.chiave === "bonifico" && r.valore) Object.assign(CONFIG.BONIFICO, r.valore);
    });
  }

  const ready = (async function () {
    if (!db) return;
    const [{ data }] = await Promise.all([db.auth.getSession(), loadImpostazioni()]);
    user = data.session ? data.session.user : null;
    await loadProfile();
    db.auth.onAuthStateChange(async (event, session) => {
      const nu = session ? session.user : null;
      const changed = (nu && nu.id) !== (user && user.id);
      user = nu;
      if (changed || event === "USER_UPDATED") await loadProfile();
      if (changed || event === "PASSWORD_RECOVERY") fire();
      if (event === "PASSWORD_RECOVERY") document.dispatchEvent(new CustomEvent("auth:recovery"));
    });
  })();

  async function logout() { if (db) await db.auth.signOut(); user = null; profile = null; Cart.clear(); fire(); }
  function requireLogin(next) {
    if (user) return true;
    location.href = "account.html?next=" + encodeURIComponent(next || location.pathname.split("/").pop() || "shop.html");
    return false;
  }

  // ---------- catalogo ----------
  // Ritorna i prodotti visibili a QUESTO cliente, già con il prezzo giusto.
  async function catalogo() {
    if (db) {
      const { data, error } = await db.rpc("catalogo");
      if (!error && data) return data;
      console.error(error);
    }
    // senza database: solo il prodotto per privati, dalla configurazione
    return CONFIG.PRODOTTI_DEMO.filter(p => p.attivo && p.canale === "b2c");
  }

  // ---------- intestazione / piè di pagina ----------
  function renderHeader() {
    const h = document.getElementById("site-header"); if (!h) return;
    const page = location.pathname.split("/").pop() || "index.html";
    const n = Cart.count();
    const accLabel = user ? (profile && (profile.nome || profile.ragione_sociale) ? esc(profile.nome || profile.ragione_sociale) : Lang.t("nav.account")) : Lang.t("nav.login");
    h.innerHTML = `
      <div class="hdr-in">
        <a class="brand" href="index.html" aria-label="Carminello"><img src="assets/img/logo.png" alt="Carminello" width="150" height="60"></a>
        <button class="burger" id="burger" aria-label="Menu" aria-expanded="false"><span></span><span></span><span></span></button>
        <nav class="nav" id="nav">
          <a href="index.html" class="${page === "index.html" ? "on" : ""}" data-i18n="nav.home">Home</a>
          <a href="shop.html" class="${page === "shop.html" ? "on" : ""}" data-i18n="nav.shop">Ordina</a>
          <a href="index.html#b2b" data-i18n="nav.b2b">Per il tuo locale</a>
          <a href="info.html" class="${page === "info.html" ? "on" : ""}" data-i18n="nav.info">Info</a>
          <a href="info.html#contatti" data-i18n="nav.contatti">Contatti</a>
          ${isAdmin() ? `<a href="admin.html" class="adm ${page === "admin.html" ? "on" : ""}" data-i18n="nav.admin">Pannello</a>` : ""}
        </nav>
        <div class="hdr-tools">
          <div class="lang-sw" role="group" aria-label="Lingua">
            <button data-lang-btn="it" class="${Lang.get() === "it" ? "on" : ""}">IT</button><button data-lang-btn="en" class="${Lang.get() === "en" ? "on" : ""}">EN</button>
          </div>
          <a class="hdr-acc" href="account.html" title="${accLabel}"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-7 8-7s8 3 8 7"/></svg><span>${accLabel}</span></a>
          <a class="hdr-cart" href="shop.html" aria-label="${Lang.t("nav.cart")}"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.6a2 2 0 0 0 2-1.5L21 8H6.2"/><circle cx="10" cy="20" r="1.3"/><circle cx="17" cy="20" r="1.3"/></svg>${n ? `<b class="badge">${n}</b>` : ""}</a>
        </div>
      </div>`;
    h.querySelectorAll("[data-lang-btn]").forEach(b => b.addEventListener("click", () => Lang.set(b.getAttribute("data-lang-btn"))));
    const burger = h.querySelector("#burger"), nav = h.querySelector("#nav");
    burger.addEventListener("click", () => { const open = nav.classList.toggle("open"); burger.setAttribute("aria-expanded", open); burger.classList.toggle("x", open); });
    Lang.apply(h);
  }

  function renderFooter() {
    const f = document.getElementById("site-footer"); if (!f) return;
    const A = CONFIG.AZIENDA;
    f.innerHTML = `
      <div class="ftr-in">
        <div class="ftr-col brand-col">
          <img src="assets/img/logo-white.png" alt="Carminello" width="160" height="64">
          <p>${esc(A.ragione_sociale)}<br>${esc(A.indirizzo)}<br>P.IVA ${esc(A.piva)} · REA ${esc(A.rea)}</p>
        </div>
        <div class="ftr-col">
          <h4 data-i18n="footer.links">Informazioni</h4>
          <a href="info.html#spedizioni" data-i18n="footer.ship">Spedizioni</a>
          <a href="info.html#pagamenti" data-i18n="footer.pay">Metodi di pagamento</a>
          <a href="info.html#cottura" data-i18n="footer.cook">Cottura</a>
          <a href="info.html#condizioni" data-i18n="footer.terms">Condizioni di vendita</a>
          <a href="info.html#privacy" data-i18n="footer.privacy">Privacy</a>
          <a href="info.html#cookie" data-i18n="footer.cookie">Cookie</a>
        </div>
        <div class="ftr-col">
          <h4 data-i18n="contact.kicker">Contatti</h4>
          <a href="https://wa.me/${A.whatsapp}" target="_blank" rel="noopener">WhatsApp ${esc(A.telefono)}</a>
          <a href="mailto:${esc(A.email)}">${esc(A.email)}</a>
          <div class="social">
            <a href="${A.social.facebook}" target="_blank" rel="noopener" aria-label="Facebook">Facebook</a>
            <a href="${A.social.instagram}" target="_blank" rel="noopener" aria-label="Instagram">Instagram</a>
            <a href="${A.social.youtube}" target="_blank" rel="noopener" aria-label="YouTube">YouTube</a>
          </div>
        </div>
      </div>
      <div class="ftr-bottom">© ${new Date().getFullYear()} ${esc(A.marchio)} · ${esc(A.ragione_sociale)} · <span data-i18n="footer.rights">Tutti i diritti riservati.</span></div>`;
    Lang.apply(f);
  }

  function renderPendingBanner() {
    let b = document.getElementById("pending-banner");
    const show = isB2B() && !b2bAttivo();
    if (!show) { if (b) b.remove(); return; }
    if (!b) { b = document.createElement("div"); b.id = "pending-banner"; const h = document.getElementById("site-header"); h && h.insertAdjacentElement("afterend", b); }
    b.innerHTML = `<span>${Lang.t("banner.pending")}</span> <a href="https://wa.me/${CONFIG.AZIENDA.whatsapp}" target="_blank" rel="noopener">${Lang.t("banner.wa")}</a>`;
  }
  onAuth(renderPendingBanner);
  document.addEventListener("lang:change", renderPendingBanner);

  function init() {
    try { const ca = qs("agente"); if (ca) localStorage.setItem("carminello-agente", ca.toUpperCase().replace(/[^A-Z0-9]/g, "")); } catch (_) {}
    renderHeader(); renderFooter(); Lang.apply();
    ready.then(renderPendingBanner);
    document.addEventListener("cart:change", renderHeader);
    document.addEventListener("lang:change", () => { renderHeader(); renderFooter(); });
    if (!db) {
      const b = document.getElementById("cfg-banner");
      if (b) { b.hidden = false; b.textContent = Lang.t("common.notConfigured"); }
    }
    if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
      navigator.serviceWorker.register("sw.js").catch(() => {});
    }
  }
  document.addEventListener("DOMContentLoaded", init);

  return {
    get db() { return db; }, get user() { return user; }, get profile() { return profile; },
    configured, ready, money, dateFmt, esc, qs, toast, loadProfile, isAdmin, isB2B, b2bAttivo, onAuth, logout, requireLogin, catalogo, renderHeader
  };
})();
