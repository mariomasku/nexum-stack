// Manual de Nexum Dev Stack: tema, Linux o Mac, búsqueda, índice y las pantallas con puntos
(function () {
  "use strict";
  var raiz = document.documentElement;

  function guardado(clave, valor) {
    try {
      if (valor === undefined) return localStorage.getItem(clave);
      localStorage.setItem(clave, valor);
    } catch (e) { return null; }
    return valor;
  }

  // --- Claro u oscuro (sin elegir, el del sistema)
  var tema = guardado("nexum-manual-tema");
  if (tema) raiz.setAttribute("data-tema", tema);
  document.getElementById("tema").addEventListener("click", function () {
    var oscuro = raiz.getAttribute("data-tema") ? raiz.getAttribute("data-tema") === "oscuro"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    raiz.setAttribute("data-tema", oscuro ? "claro" : "oscuro");
    guardado("nexum-manual-tema", raiz.getAttribute("data-tema"));
  });

  // --- Linux o Mac: lo de un solo sistema se ve solo con el suyo. El programa abre el manual con ?so=
  var params = new URLSearchParams(location.search);
  var so = params.get("so") || guardado("nexum-manual-so") ||
    (/Mac/.test(navigator.platform || navigator.userAgent) ? "mac" : "linux");
  function ponerSistema(s) {
    so = s === "mac" ? "mac" : "linux";
    document.body.setAttribute("data-sistema", so);
    document.querySelectorAll(".sistema button").forEach(function (b) {
      b.setAttribute("aria-pressed", b.dataset.valor === so ? "true" : "false");
    });
    document.querySelectorAll("img[data-linux]").forEach(function (img) {
      var src = img.dataset[so] || img.dataset.linux;
      if (img.getAttribute("src") !== src) img.setAttribute("src", src);
    });
    guardado("nexum-manual-so", so);
  }
  document.querySelectorAll(".sistema button").forEach(function (b) {
    b.addEventListener("click", function () { ponerSistema(b.dataset.valor); });
  });
  ponerSistema(so);

  // --- Índice: el apartado que se está leyendo, marcado
  var enlaces = Array.prototype.slice.call(document.querySelectorAll(".indice a[href^='#']"));
  if ("IntersectionObserver" in window) {
    var obs = new IntersectionObserver(function (entradas) {
      entradas.forEach(function (e) {
        if (!e.isIntersecting) return;
        enlaces.forEach(function (a) { a.classList.toggle("actual", a.getAttribute("href") === "#" + e.target.id); });
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    document.querySelectorAll("section.capitulo[id]").forEach(function (s) { obs.observe(s); });
  }
  document.querySelector(".boton-indice").addEventListener("click", function () {
    document.body.classList.toggle("indice-abierto");
  });
  enlaces.forEach(function (a) {
    a.addEventListener("click", function () { document.body.classList.remove("indice-abierto"); });
  });

  // --- Búsqueda: la lista de los sitios donde sale lo buscado (capítulo › apartado y un trozo del texto); al
  // pulsar uno, se va ahí y se ilumina. Dentro de una pregunta, se despliega; en un punto de una captura, se abre
  var buscar = document.getElementById("buscar");
  var caja = document.getElementById("resultados");
  function normal(t) { return t.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, ""); }
  function textoDe(el) { return el.textContent.replace(/\s+/g, " ").trim(); }
  // Los trozos que se buscan, en orden, cada uno con dónde está
  var trozos = [];
  document.querySelectorAll("section.capitulo").forEach(function (cap) {
    // (el nombre del capítulo, el del índice: la portada se titula con el logotipo)
    var enIndice = document.querySelector('.indice a[href="#' + cap.id + '"]');
    var capitulo = enIndice ? textoDe(enIndice) : textoDe(cap.querySelector("h1, h2"));
    var apartado = "";
    cap.querySelectorAll("h3, p, li, dt, dd, summary, .tarjeta").forEach(function (el) {
      if (el.tagName === "H3") { apartado = textoDe(el); return; }
      // (lo de dentro de otro trozo ya va en el suyo)
      if (el.parentNode.closest("li, dd, .tarjeta") && !el.matches(".puntos li")) return;
      if (el.closest(".tarjeta") && el !== el.closest(".tarjeta")) return;
      var donde = apartado;
      var det = el.closest("details");
      var punto = el.closest(".puntos li");
      if (punto) donde = "En la captura: " + textoDe(punto.querySelector("b"));
      else if (det) donde = textoDe(det.querySelector("summary"));
      else if (el.closest(".entrada") || (!apartado && el.tagName === "P")) donde = donde || "Introducción";
      var t = textoDe(el);
      if (t) trozos.push({ el: el, capitulo: capitulo, donde: donde, texto: t, norm: normal(t) });
    });
  });
  function trozoCon(t, q) {
    var i = normal(t).indexOf(q);
    var ini = Math.max(0, i - 50), fin = Math.min(t.length, i + q.length + 70);
    var esc = function (x) { return x.replace(/&/g, "&amp;").replace(/</g, "&lt;"); };
    return (ini > 0 ? "…" : "") + esc(t.slice(ini, i)) + "<mark>" + esc(t.slice(i, i + q.length)) + "</mark>" +
      esc(t.slice(i + q.length, fin)) + (fin < t.length ? "…" : "");
  }
  var elegido = -1, hallados = [];
  function ir(n) {
    var r = hallados[n];
    if (!r) return;
    var det = r.el.closest("details");
    if (det) det.open = true;
    document.body.classList.remove("indice-abierto");
    var punto = r.el.closest(".puntos li");
    var destino = punto ? punto.closest(".pantalla").querySelector(".lienzo") : r.el;
    destino.scrollIntoView({ block: "center", behavior: "smooth" });
    r.el.classList.remove("destello");
    void r.el.offsetWidth;
    r.el.classList.add("destello");
    if (punto) setTimeout(function () { punto.click(); }, 450);
  }
  function marcarElegido() {
    caja.querySelectorAll(".resultado").forEach(function (b, n) {
      b.classList.toggle("elegido", n === elegido);
      if (n === elegido) b.scrollIntoView({ block: "nearest" });
    });
  }
  buscar.addEventListener("input", function () {
    var q = normal(buscar.value.trim());
    elegido = -1;
    if (q.length < 2) { caja.hidden = true; caja.innerHTML = ""; return; }
    hallados = trozos.filter(function (t) { return t.norm.indexOf(q) >= 0; });
    caja.hidden = false;
    if (!hallados.length) {
      caja.innerHTML = '<div class="sin-resultados">No sale en el manual. Prueba con otra palabra (o con parte de ella).</div>';
      return;
    }
    caja.innerHTML = '<div class="cuantos">' + hallados.length + (hallados.length === 1 ? " sitio" : " sitios") + "</div>";
    hallados.forEach(function (r, n) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "resultado";
      b.setAttribute("role", "option");
      b.innerHTML = "<b>" + r.capitulo + (r.donde ? " › " + r.donde : "") + "</b><span>" + trozoCon(r.texto, q) + "</span>";
      b.addEventListener("click", function () { ir(n); });
      caja.appendChild(b);
    });
  });
  buscar.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape") { buscar.value = ""; buscar.dispatchEvent(new Event("input")); return; }
    if (!hallados.length || caja.hidden) return;
    if (ev.key === "ArrowDown") { ev.preventDefault(); elegido = Math.min(hallados.length - 1, elegido + 1); marcarElegido(); }
    if (ev.key === "ArrowUp") { ev.preventDefault(); elegido = Math.max(0, elegido - 1); marcarElegido(); }
    if (ev.key === "Enter") { ev.preventDefault(); ir(elegido < 0 ? 0 : elegido); }
  });

  // --- Pantallas con puntos: el número sobre la captura y su texto en un globo, uno a uno o de corrido
  document.querySelectorAll(".pantalla").forEach(function (pant) {
    var lienzo = pant.querySelector(".lienzo");
    var items = Array.prototype.slice.call(pant.querySelectorAll(".puntos li"));
    var globo = null, actual = -1;
    var botones = items.map(function (li, n) {
      var b = document.createElement("button");
      b.className = "punto";
      b.type = "button";
      b.textContent = n + 1;
      b.style.left = li.dataset.x + "%";
      b.style.top = li.dataset.y + "%";
      b.setAttribute("aria-label", (n + 1) + ": " + li.querySelector("b").textContent);
      b.addEventListener("click", function (ev) { ev.stopPropagation(); mostrar(n); });
      lienzo.appendChild(b);
      li.addEventListener("click", function () { mostrar(n); lienzo.scrollIntoView({ block: "nearest", behavior: "smooth" }); });
      li.addEventListener("mouseenter", function () { b.classList.add("activo"); });
      li.addEventListener("mouseleave", function () { if (n !== actual) b.classList.remove("activo"); });
      return b;
    });
    function cerrar() {
      if (globo) globo.remove();
      globo = null;
      actual = -1;
      botones.forEach(function (b) { b.classList.remove("activo"); });
      items.forEach(function (li) { li.classList.remove("activo"); });
    }
    function mostrar(n) {
      cerrar();
      if (n < 0 || n >= items.length) return;
      actual = n;
      botones[n].classList.add("activo");
      items[n].classList.add("activo");
      globo = document.createElement("div");
      globo.className = "globo";
      globo.setAttribute("role", "dialog");
      globo.innerHTML = '<button class="cerrar" type="button" aria-label="Cerrar">×</button>' +
        "<b>" + (n + 1) + ". " + items[n].querySelector("b").innerHTML + "</b>" +
        "<div>" + items[n].querySelector("span").innerHTML + "</div>" +
        '<div class="pasos"><button class="boton ant" type="button">← Anterior</button>' +
        "<span>" + (n + 1) + " de " + items.length + "</span>" +
        '<button class="boton azul sig" type="button">' + (n + 1 < items.length ? "Siguiente →" : "Terminar") + "</button></div>";
      lienzo.appendChild(globo);
      // (un clic dentro del globo no llega a la página: allí cuenta como «fuera» y lo cerraría, porque
      // Siguiente y Anterior ya han cambiado el globo por el nuevo cuando llega)
      globo.addEventListener("click", function (ev) { ev.stopPropagation(); });
      globo.querySelector(".cerrar").onclick = cerrar;
      globo.querySelector(".ant").disabled = n === 0;
      globo.querySelector(".ant").onclick = function () { mostrar(n - 1); };
      globo.querySelector(".sig").onclick = function () { if (n + 1 < items.length) mostrar(n + 1); else cerrar(); };
      // (al lado del punto, sin salirse de la captura)
      var w = lienzo.clientWidth, h = lienzo.clientHeight;
      var x = parseFloat(items[n].dataset.x) / 100 * w, y = parseFloat(items[n].dataset.y) / 100 * h;
      var gw = globo.offsetWidth, gh = globo.offsetHeight;
      var left = Math.min(Math.max(8, x - gw / 2), w - gw - 8);
      var top = y + 22 + gh < h ? y + 22 : Math.max(8, y - gh - 22);
      globo.style.left = left + "px";
      globo.style.top = top + "px";
    }
    var recorrido = pant.querySelector(".recorrido");
    if (recorrido) recorrido.addEventListener("click", function (ev) { ev.stopPropagation(); mostrar(0); lienzo.scrollIntoView({ block: "center", behavior: "smooth" }); });
    var ocultar = pant.querySelector(".ocultar");
    if (ocultar) ocultar.addEventListener("click", function () {
      var sin = lienzo.classList.toggle("sin-puntos");
      ocultar.textContent = sin ? "Mostrar los números" : "Ocultar los números";
      if (sin) cerrar();
    });
    document.addEventListener("click", function (ev) { if (globo && !globo.contains(ev.target)) cerrar(); });
    document.addEventListener("keydown", function (ev) {
      if (!globo) return;
      if (ev.key === "Escape") cerrar();
      if (ev.key === "ArrowRight" && actual + 1 < items.length) mostrar(actual + 1);
      if (ev.key === "ArrowLeft" && actual > 0) mostrar(actual - 1);
    });
    window.addEventListener("resize", function () { if (actual >= 0) mostrar(actual); });
  });
})();
