/* ---------------------------------------------------------------------------
   OpusScreen - le site

   Aucune bibliotheque, aucune ressource exterieure, aucun traqueur : la page
   dit que rien ne sort de votre machine, elle doit donc s'y tenir elle-meme.

   La demonstration n'illustre pas, elle CALCULE : les matrices de simulation et
   de correction sont celles de src/ColorMatrixEffect.cs, et l'ecart percu est
   le meme Delta E CIE76 que celui affiche par l'application.
   --------------------------------------------------------------------------- */

(function () {
  'use strict';

  // ---------------------------------------------------------------- theme

  var root = document.documentElement;
  var stored = null;
  try { stored = localStorage.getItem('theme'); } catch (e) { /* navigation privee */ }
  if (stored === 'light' || stored === 'dark') root.setAttribute('data-theme', stored);
  else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches)
    root.setAttribute('data-theme', 'light');

  var themeBtn = document.getElementById('theme');
  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('theme', next); } catch (e) { /* tant pis */ }
    });
  }

  // ---------------------------------------------------------------- onglets

  var tabs = [].slice.call(document.querySelectorAll('[role="tab"]'));
  function selectTab(tab) {
    tabs.forEach(function (t) {
      var panel = document.getElementById(t.getAttribute('aria-controls'));
      var on = t === tab;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      if (panel) panel.hidden = !on;
    });
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { selectTab(tab); });
    tab.addEventListener('keydown', function (e) {
      var step = e.key === 'ArrowRight' ? 1 : (e.key === 'ArrowLeft' ? -1 : 0);
      if (!step) return;
      e.preventDefault();
      var next = tabs[(i + step + tabs.length) % tabs.length];
      selectTab(next);
      next.focus();
    });
  });

  // ---------------------------------------------------------------- couleurs

  // Matrices de simulation, convention entree -> sortie : sortie[j] = somme(entree[i] * M[i][j]).
  // Vienot / Brettel, reprises telles quelles de l'application.
  var FULL = {
    protanopia:   [[0.567, 0.558, 0.000], [0.433, 0.442, 0.242], [0.000, 0.000, 0.758]],
    deuteranopia: [[0.625, 0.700, 0.000], [0.375, 0.300, 0.300], [0.000, 0.000, 0.700]],
    tritanopia:   [[0.950, 0.000, 0.000], [0.050, 0.433, 0.475], [0.000, 0.567, 0.525]]
  };

  /** Simulation a gravite reglable : interpolation entre vision normale et dichromatie. */
  function simulation(kind, severity) {
    var full = FULL[kind], m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++)
        m[i][j] = (1 - severity) * (i === j ? 1 : 0) + severity * full[i][j];
    return m;
  }

  /**
   * Correction : on simule ce que la personne ne distingue pas, on mesure l'ecart
   * avec l'image d'origine, et on reinjecte cet ecart sur les canaux qu'elle percoit
   * encore.   M = I + intensite x (I - simulation) x redistribution
   */
  function daltonize(kind, severity, strength) {
    var sim = simulation(kind, severity);
    var shift = kind === 'tritanopia'
      ? [[1, 0, 0], [0, 1, 0], [0.7, 0.7, 0]]
      : [[0, 0.7, 0.7], [0, 1, 0], [0, 0, 1]];

    var d = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], i, j, k;
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++)
        d[i][j] = (i === j ? 1 : 0) - sim[i][j];

    var m = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
    for (i = 0; i < 3; i++)
      for (j = 0; j < 3; j++) {
        var acc = 0;
        for (k = 0; k < 3; k++) acc += d[i][k] * shift[k][j];
        m[i][j] = (i === j ? 1 : 0) + strength * acc;
      }
    return m;
  }

  function apply(m, rgb) {
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

  // sRGB -> CIE L*a*b*, illuminant D65 : l'ecart percu ne se mesure pas en RVB.
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

  function css(rgb) { return 'rgb(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ')'; }

  // ---------------------------------------------------------------- demonstration

  /*
     Les paires ne sont pas choisies a la main : ecrites d'apres le sens commun
     (« rouge et vert »), elles se revelent souvent parfaitement distinctes une fois
     simulees - elles different surtout par la CLARTE, que la deficience ne touche
     pas. La page montrerait alors deux colonnes identiques et se contredirait
     elle-meme.

     On les construit donc comme l'application : en s'ecartant d'un ton moyen le long
     de la direction de confusion, c'est-a-dire la direction que la simulation ecrase
     le plus. Par construction, ces deux couleurs-la sont confondues.
  */

  /** Direction de confusion : vecteur propre de M.Mt associe a la plus petite valeur propre. */
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

    // Iteration inverse : multiplier par A^-1 amplifie la plus PETITE valeur propre.
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

  var ANCHORS = [[0.50, 0.50, 0.50], [0.60, 0.46, 0.42], [0.44, 0.54, 0.46], [0.48, 0.46, 0.60]];

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
    return deltaE(apply(sim, rgbAt(anchor, d, -t / 2)), apply(sim, rgbAt(anchor, d, t / 2)));
  }

  function buildPairs(kind, sim) {
    var d = confusionDirection(kind), pairs = [];
    ANCHORS.forEach(function (anchor) {
      var t = confusedSpread(anchor, d, sim);
      var a = rgbAt(anchor, d, -t / 2), b = rgbAt(anchor, d, t / 2);
      if (a[0] === b[0] && a[1] === b[1] && a[2] === b[2]) return;
      pairs.push([a, b]);
    });
    return pairs;
  }

  var state = { vision: 'deuteranopia', severity: 0.7 };
  var before = document.getElementById('before');
  var after = document.getElementById('after');

  function swatch(a, b) {
    var row = document.createElement('div');
    row.className = 'pair';
    [a, b].forEach(function (c) {
      var cell = document.createElement('div');
      cell.style.background = css(c);
      row.appendChild(cell);
    });
    return row;
  }

  function show(id, value) {
    var el = document.getElementById(id);
    if (!el) return;
    var text = value.toFixed(1).replace('.', ',');
    el.textContent = text + (value < 2.3 ? ' — indistinguables' : ' — distinctes');
  }

  function renderDemo() {
    if (!before || !after) return;

    var sim = simulation(state.vision, state.severity);
    var corrected = multiply(daltonize(state.vision, state.severity, 1.0), sim);
    var pairs = buildPairs(state.vision, sim);

    before.innerHTML = '';
    after.innerHTML = '';
    var sumBefore = 0, sumAfter = 0;

    pairs.forEach(function (pair) {
      var a = pair[0], b = pair[1];
      sumBefore += deltaE(apply(sim, a), apply(sim, b));
      sumAfter += deltaE(apply(corrected, a), apply(corrected, b));
      before.appendChild(swatch(apply(sim, a), apply(sim, b)));
      after.appendChild(swatch(apply(corrected, a), apply(corrected, b)));
    });

    show('delta-before', sumBefore / pairs.length);
    show('delta-after', sumAfter / pairs.length);
  }

  [].slice.call(document.querySelectorAll('[data-vision]')).forEach(function (btn) {
    btn.addEventListener('click', function () {
      [].slice.call(document.querySelectorAll('[data-vision]')).forEach(function (b) { b.classList.remove('on'); });
      btn.classList.add('on');
      state.vision = btn.getAttribute('data-vision');
      renderDemo();
    });
  });

  var sev = document.getElementById('sev'), sevOut = document.getElementById('sev-out');
  if (sev) {
    sev.addEventListener('input', function () {
      state.severity = parseInt(sev.value, 10) / 100;
      if (sevOut) sevOut.textContent = sev.value + ' %';
      renderDemo();
    });
  }

  renderDemo();

  // ---------------------------------------------------------------- derniere version

  // Confort, pas necessite : si GitHub ne repond pas, le texte ecrit dans la page
  // reste juste. Aucune donnee n'est envoyee, c'est une simple lecture publique.
  if (window.fetch) {
    fetch('https://api.github.com/repos/antoinebonpro/OpusScreen/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (data) {
        if (!data || !data.tag_name) return;
        var size = 0;
        (data.assets || []).forEach(function (a) { if (/\.exe$/i.test(a.name)) size = a.size; });
        var label = data.tag_name.replace(/^v/, '');
        var text = 'version ' + label + (size ? ' · ' + Math.round(size / 1024) + ' Ko' : '') + ' · un seul fichier';
        ['release-meta', 'release-meta-2'].forEach(function (id) {
          var el = document.getElementById(id);
          if (el) el.textContent = text;
        });
      })
      .catch(function () { /* hors ligne : le texte de la page suffit */ });
  }
})();
