/* ===========================================================================
   OpusScreen - le site

   Deux demonstrations, et aucune n'illustre : toutes deux calculent, avec les
   formules du logiciel.

   - Le voile de la page reprend ColorTemp.Multipliers et le voile de
     GammaEngine : regler la page, c'est faire exactement ce que fait
     l'application sur un ecran.
   - Les paires de couleurs sont construites le long de l'axe de confusion,
     comme dans Vision.ConfusionPairs, et mesurees en Delta E CIE76.

   Aucune bibliotheque, aucune ressource distante. La page affirme que rien ne
   sort de la machine ; elle s'y tient.
   =========================================================================== */

(function () {
  'use strict';

  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ------------------------------------------------------------------ temperature

  /** ColorTemp.Multipliers : {r,g,b} dans [0..1], exactement {1,1,1} a 6500 K. */
  function multipliers(kelvin) {
    kelvin = Math.max(1200, Math.min(6500, kelvin));
    var t = kelvin / 100, r, g, b;

    if (t <= 66) r = 255;
    else r = 329.698727446 * Math.pow(t - 60, -0.1332047592);

    if (t <= 66) g = 99.4708025861 * Math.log(t) - 161.1195681661;
    else g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);

    if (t >= 66) b = 255;
    else if (t <= 19) b = 0;
    else b = 138.5177312231 * Math.log(t - 10) - 305.0447927307;

    function norm(v, ref) { v = v / ref; return v < 0 ? 0 : (v > 1 ? 1 : v); }
    return [norm(r, 255), norm(g, 254.1097), norm(b, 250.0522)];
  }

  var veil = document.getElementById('veil');
  var gain = document.getElementById('gain');
  var kelvinIn = document.getElementById('kelvin');
  var lumIn = document.getElementById('lum');
  var kelvinOut = document.getElementById('kelvin-out');
  var lumOut = document.getElementById('lum-out');

  function paint(kelvin, lum) {
    if (!veil) return;
    var m = multipliers(kelvin);

    // Sous 100 %, on retire de la lumiere : c'est le voile, en multiplication.
    // Au-dessus, on ne peut qu'ECLAIRCIR une page deja affichee - la carte
    // graphique, elle, multiplie vraiment le signal. La page le simule donc
    // faiblement, et le dit.
    var dim = Math.min(1, lum / 100);
    veil.style.backgroundColor = 'rgb(' + Math.round(m[0] * 255 * dim) + ','
                                        + Math.round(m[1] * 255 * dim) + ','
                                        + Math.round(m[2] * 255 * dim) + ')';

    var over = Math.max(0, (lum - 100) / 100);
    gain.style.backgroundColor = 'rgba(255,255,255,' + (over * 0.35).toFixed(3) + ')';

    if (kelvinOut) kelvinOut.textContent = kelvin + ' K';
    if (lumOut) lumOut.textContent = lum + ' %';
  }

  function current() {
    return [parseInt(kelvinIn.value, 10), parseInt(lumIn.value, 10)];
  }

  if (veil && kelvinIn && lumIn) {
    kelvinIn.addEventListener('input', function () { var c = current(); paint(c[0], c[1]); });
    lumIn.addEventListener('input', function () { var c = current(); paint(c[0], c[1]); });

    var reset = document.getElementById('reset');
    if (reset) {
      reset.addEventListener('click', function () {
        kelvinIn.value = 6500; lumIn.value = 100;
        paint(6500, 100);
      });
    }

    // Le seul mouvement non demande de la page : au chargement, elle se rechauffe
    // une fois, de la lumiere du jour vers 4600 K. C'est la demonstration la plus
    // courte possible du produit - et elle ne se repete jamais.
    if (reduced) {
      paint(5200, 100);
    } else {
      paint(6500, 100);
      var start = null;
      requestAnimationFrame(function step(now) {
        if (start === null) start = now;
        var t = Math.min(1, (now - start) / 1400);
        var eased = 0.5 - 0.5 * Math.cos(Math.PI * t);
        paint(Math.round(6500 - eased * 1300), 100);
        if (t < 1) requestAnimationFrame(step);
        else kelvinIn.value = 5200;
      });
    }
  }

  // ------------------------------------------------------------------ couleurs

  // Matrices de simulation, convention entree -> sortie : sortie[j] = somme(entree[i] * M[i][j]).
  var FULL = {
    protanopia:   [[0.567, 0.558, 0.000], [0.433, 0.442, 0.242], [0.000, 0.000, 0.758]],
    deuteranopia: [[0.625, 0.700, 0.000], [0.375, 0.300, 0.300], [0.000, 0.000, 0.700]],
    tritanopia:   [[0.950, 0.000, 0.000], [0.050, 0.433, 0.475], [0.000, 0.567, 0.525]]
  };

  function simulation(kind, severity) {
    var full = FULL[kind], m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++)
        m[i][j] = (1 - severity) * (i === j ? 1 : 0) + severity * full[i][j];
    return m;
  }

  /** M = I + intensite x (I - simulation) x redistribution. */
  function daltonize(kind, severity, strength) {
    var sim = simulation(kind, severity);
    var shift = kind === 'tritanopia'
      ? [[1, 0, 0], [0, 1, 0], [0.7, 0.7, 0]]
      : [[0, 0.7, 0.7], [0, 1, 0], [0, 0, 1]];

    var d = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j, k;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++) d[i][j] = (i === j ? 1 : 0) - sim[i][j];

    var m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++) {
        var acc = 0;
        for (k = 0; k < 3; k++) acc += d[i][k] * shift[k][j];
        m[i][j] = (i === j ? 1 : 0) + strength * acc;
      }
    return m;
  }

  function applyM(m, rgb) {
    var out = [0, 0, 0], i, j;
    for (j = 0; j < 3; j++) {
      var s = 0;
      for (i = 0; i < 3; i++) s += rgb[i] * m[i][j];
      out[j] = Math.max(0, Math.min(255, Math.round(s)));
    }
    return out;
  }

  function multiply(a, b) {
    var m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j, k;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++) {
        var s = 0;
        for (k = 0; k < 3; k++) s += a[i][k] * b[k][j];
        m[i][j] = s;
      }
    return m;
  }

  function lab(rgb) {
    function lin(v) { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
    var r = lin(rgb[0]), g = lin(rgb[1]), b = lin(rgb[2]);
    var x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
    var y = (r * 0.2126 + g * 0.7152 + b * 0.0722);
    var z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
    function f(t) { return t > 0.008856 ? Math.pow(t, 1 / 3) : (7.787 * t) + 16 / 116; }
    var fx = f(x), fy = f(y), fz = f(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  function deltaE(a, b) {
    var la = lab(a), lb = lab(b);
    var dl = la[0] - lb[0], da = la[1] - lb[1], db = la[2] - lb[2];
    return Math.sqrt(dl * dl + da * da + db * db);
  }

  /* Les paires ne sont pas choisies a la main : ecrites d'apres le sens commun
     (« rouge et vert »), elles se revelent souvent distinctes une fois simulees,
     car elles different surtout par la CLARTE - que la deficience ne touche pas.
     On les construit donc le long de la direction de confusion : la direction que
     la simulation ecrase le plus, c'est-a-dire le vecteur propre de M.Mt associe
     a la plus petite valeur propre. */
  function confusionDirection(kind) {
    var m = FULL[kind], a = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j, k;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++) {
        var s = 0;
        for (k = 0; k < 3; k++) s += m[i][k] * m[j][k];
        a[i][j] = s;
      }
    var inv = invert3(a);
    if (!inv) return [1, -1, 0];

    var v = [0.577, -0.577, 0.577];
    for (var step = 0; step < 60; step++) {
      var w = [0, 0, 0];
      for (i = 0; i < 3; i++) w[i] = inv[i][0] * v[0] + inv[i][1] * v[1] + inv[i][2] * v[2];
      var n = Math.sqrt(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]);
      if (n < 1e-12) break;
      v = [w[0] / n, w[1] / n, w[2] / n];
    }
    return v;
  }

  function invert3(m) {
    var det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
            - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
            + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    if (Math.abs(det) < 1e-12) return null;
    return [
      [(m[1][1] * m[2][2] - m[1][2] * m[2][1]) / det, (m[0][2] * m[2][1] - m[0][1] * m[2][2]) / det, (m[0][1] * m[1][2] - m[0][2] * m[1][1]) / det],
      [(m[1][2] * m[2][0] - m[1][0] * m[2][2]) / det, (m[0][0] * m[2][2] - m[0][2] * m[2][0]) / det, (m[0][2] * m[1][0] - m[0][0] * m[1][2]) / det],
      [(m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det, (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det, (m[0][0] * m[1][1] - m[0][1] * m[1][0]) / det]
    ];
  }

  // Ancrages colores : un ancrage gris donne deux gris - exact, mais une
  // demonstration ou l'on ne voit aucune couleur n'apprend rien a qui regarde.
  var ANCHORS = [[0.62, 0.48, 0.44], [0.44, 0.56, 0.48], [0.48, 0.46, 0.62]];

  function rgbAt(anchor, d, t) {
    function comp(v) { v = Math.round(v * 255); return v < 0 ? 0 : (v > 255 ? 255 : v); }
    return [comp(anchor[0] + d[0] * t), comp(anchor[1] + d[1] * t), comp(anchor[2] + d[2] * t)];
  }

  function maxSpread(anchor, d) {
    var t = 2.0;
    for (var i = 0; i < 3; i++) {
      if (Math.abs(d[i]) < 1e-6) continue;
      t = Math.min(t, 2.0 * Math.min((anchor[i] - 0.06) / Math.abs(d[i]), (0.94 - anchor[i]) / Math.abs(d[i])));
    }
    return t;
  }

  /** Le plus grand ecart qui reste indistinguable une fois simule. */
  function confusedSpread(anchor, d, sim) {
    var max = maxSpread(anchor, d);
    if (max < 0.05) return 0;
    if (simulatedDelta(anchor, d, max, sim) <= 2.3) return max;

    var lo = 0, hi = max;
    for (var i = 0; i < 22; i++) {
      var mid = (lo + hi) / 2;
      if (simulatedDelta(anchor, d, mid, sim) <= 2.3) lo = mid; else hi = mid;
    }
    return lo;
  }

  function simulatedDelta(anchor, d, t, sim) {
    return deltaE(applyM(sim, rgbAt(anchor, d, -t / 2)), applyM(sim, rgbAt(anchor, d, t / 2)));
  }

  function css(rgb) { return 'rgb(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ')'; }
  function fr(v) { return v.toFixed(1).replace('.', ','); }

  var state = { vision: 'deuteranopia', severity: 0.7 };
  var host = document.getElementById('pairs');

  function row(a, b, value, when) {
    var line = document.createElement('div');
    line.className = 'pair-row ' + (value < 2.3 ? 'merged' : 'separated');

    [a, b].forEach(function (c) {
      var half = document.createElement('div');
      half.className = 'half';
      half.style.background = css(c);
      line.appendChild(half);
    });

    var read = document.createElement('div');
    read.className = 'read';

    var moment = document.createElement('span');
    moment.className = 'moment';
    moment.textContent = when;

    var v = document.createElement('span');
    v.className = 'value';
    v.textContent = fr(value) + ' Delta E';

    var verdict = document.createElement('span');
    verdict.className = 'verdict';
    verdict.textContent = value < 2.3 ? 'une seule couleur' : 'deux couleurs';

    read.appendChild(moment);
    read.appendChild(v);
    read.appendChild(verdict);
    line.appendChild(read);
    return line;
  }

  function render() {
    if (!host) return;
    var sim = simulation(state.vision, state.severity);
    var corrected = multiply(daltonize(state.vision, state.severity, 1.0), sim);
    var d = confusionDirection(state.vision);

    while (host.firstChild) host.removeChild(host.firstChild);

    ANCHORS.forEach(function (anchor) {
      var t = confusedSpread(anchor, d, sim);
      var a = rgbAt(anchor, d, -t / 2), b = rgbAt(anchor, d, t / 2);
      if (a[0] === b[0] && a[1] === b[1] && a[2] === b[2]) return;

      var block = document.createElement('div');
      block.className = 'pair-block';
      block.appendChild(row(applyM(sim, a), applyM(sim, b),
                            deltaE(applyM(sim, a), applyM(sim, b)), 'Aujourd’hui'));
      block.appendChild(row(applyM(corrected, a), applyM(corrected, b),
                            deltaE(applyM(corrected, a), applyM(corrected, b)), 'Avec la correction'));
      host.appendChild(block);
    });
  }

  [].slice.call(document.querySelectorAll('[data-vision]')).forEach(function (btn) {
    btn.addEventListener('click', function () {
      [].slice.call(document.querySelectorAll('[data-vision]')).forEach(function (b) { b.classList.remove('on'); });
      btn.classList.add('on');
      state.vision = btn.getAttribute('data-vision');
      render();
    });
  });

  var sev = document.getElementById('sev'), sevOut = document.getElementById('sev-out');
  if (sev) {
    sev.addEventListener('input', function () {
      state.severity = parseInt(sev.value, 10) / 100;
      if (sevOut) sevOut.textContent = sev.value + ' %';
      render();
    });
  }

  render();

  // ------------------------------------------------------------------ version

  // Confort, pas necessite : si GitHub ne repond pas, le texte de la page reste
  // juste. Lecture publique, rien n'est envoye.
  if (window.fetch) {
    fetch('https://api.github.com/repos/antoinebonpro/OpusScreen/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.tag_name) return;
        var size = 0;
        (data.assets || []).forEach(function (a) { if (/\.exe$/i.test(a.name)) size = a.size; });
        var v = data.tag_name.replace(/^v/, '');
        var one = document.getElementById('release-meta');
        var two = document.getElementById('release-meta-2');
        if (one) one.textContent = 'Version ' + v + (size ? ', ' + Math.round(size / 1024) + ' Ko' : '')
                                 + ', un seul fichier, rien à installer.';
        if (two) two.textContent = 'Version ' + v + ', pour Windows. Posez le fichier où vous voulez et double-cliquez.';
      })
      .catch(function () { /* hors ligne : le texte ecrit suffit */ });
  }
})();
