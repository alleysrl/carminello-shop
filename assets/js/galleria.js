/* ============================================================================
   GALLERIA — l'elenco delle foto sta tutto qui.
   Per aggiungere una foto: mettila in assets/img/ e scrivi il nome nell'elenco.
   L'ordine dell'elenco è l'ordine in cui compaiono (la prima è la più in vista).
   ========================================================================== */
const GALLERIA = [
  "gallery-1.webp",
  "gallery-2.webp",
  "gallery-5.webp",
  "gallery-6.webp",
  "gallery-7.webp",
  "gallery-8.webp",
  "gallery-9.webp",
  "home-2.webp"
];

const Galleria = (function () {
  "use strict";
  const src = f => "assets/img/" + f;

  // Striscia orizzontale della home: altezza fissa, si scorre col dito o con le frecce
  function striscia(box, frecce) {
    if (!box) return;
    box.innerHTML = GALLERIA.map((f, i) => `<button type="button" class="g-item" data-i="${i}" aria-label="Foto ${i + 1}"><img src="${src(f)}" alt="" loading="lazy"></button>`).join("");
    box.querySelectorAll(".g-item").forEach(b => b.addEventListener("click", () => apri(+b.getAttribute("data-i"))));
    if (frecce) {
      const passo = () => Math.max(200, box.clientWidth * 0.8);
      frecce.prev && frecce.prev.addEventListener("click", () => box.scrollBy({ left: -passo(), behavior: "smooth" }));
      frecce.next && frecce.next.addEventListener("click", () => box.scrollBy({ left: passo(), behavior: "smooth" }));
    }
  }

  // Griglia completa della pagina galleria
  function griglia(box) {
    if (!box) return;
    box.innerHTML = GALLERIA.map((f, i) => `<button type="button" class="g-item" data-i="${i}" aria-label="Foto ${i + 1}"><img src="${src(f)}" alt="" loading="lazy"></button>`).join("");
    box.querySelectorAll(".g-item").forEach(b => b.addEventListener("click", () => apri(+b.getAttribute("data-i"))));
  }

  // Foto a schermo intero, con avanti/indietro e scorrimento col dito
  let lb = null, cur = 0;
  function apri(i) {
    if (!lb) {
      lb = document.createElement("div"); lb.className = "lightbox"; lb.hidden = true;
      lb.innerHTML = `<button type="button" class="lb-close" aria-label="Chiudi">✕</button><button type="button" class="lb-prev" aria-label="Precedente">‹</button><img alt=""><button type="button" class="lb-next" aria-label="Successiva">›</button><span class="lb-count"></span>`;
      document.body.appendChild(lb);
      lb.querySelector(".lb-close").onclick = chiudi;
      lb.querySelector(".lb-prev").onclick = e => { e.stopPropagation(); vai(-1); };
      lb.querySelector(".lb-next").onclick = e => { e.stopPropagation(); vai(1); };
      lb.addEventListener("click", e => { if (e.target === lb) chiudi(); });
      let x0 = null;
      lb.addEventListener("touchstart", e => { x0 = e.touches[0].clientX; }, { passive: true });
      lb.addEventListener("touchend", e => { if (x0 == null) return; const dx = e.changedTouches[0].clientX - x0; if (Math.abs(dx) > 50) vai(dx < 0 ? 1 : -1); x0 = null; });
      document.addEventListener("keydown", e => { if (lb.hidden) return; if (e.key === "Escape") chiudi(); if (e.key === "ArrowRight") vai(1); if (e.key === "ArrowLeft") vai(-1); });
    }
    cur = i; mostra(); lb.hidden = false; document.body.style.overflow = "hidden";
  }
  function vai(d) { cur = (cur + d + GALLERIA.length) % GALLERIA.length; mostra(); }
  function mostra() { lb.querySelector("img").src = src(GALLERIA[cur]); lb.querySelector(".lb-count").textContent = (cur + 1) + " / " + GALLERIA.length; }
  function chiudi() { lb.hidden = true; document.body.style.overflow = ""; }

  return { striscia, griglia, apri, totale: () => GALLERIA.length };
})();
