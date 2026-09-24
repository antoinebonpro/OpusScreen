/* ===========================================================================
   OpusScreen - le site

   Trois comportements, et aucun n'illustre : tous calculent, avec les formules
   du logiciel.

   - La maquette reprend ColorTemp.Multipliers et le voile de GammaEngine :
     regler la maquette, c'est faire exactement ce que fait l'application sur
     un ecran - a ceci pres que l'effet s'arrete au cadre.
   - Les paires de couleurs sont construites le long de l'axe de confusion,
     comme dans Vision.ConfusionPairs, et mesurees en Delta E CIE76.
   - Les onglets du heros echangent la capture affichee, sans rien charger.

   Aucune bibliotheque, aucune ressource distante. La page affirme que rien ne
   sort de la machine ; elle s'y tient.
   =========================================================================== */

(function () {
  'use strict';

  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ------------------------------------------------------------------ onglets

  var onglets = [].slice.call(document.querySelectorAll('.onglets [role="tab"]'));

  function montrer(tab) {
    onglets.forEach(function (t) {
      var actif = t === tab;
      t.setAttribute('aria-selected', actif ? 'true' : 'false');
      var vue = document.getElementById(t.getAttribute('aria-controls'));
      if (vue) vue.hidden = !actif;
    });
  }

  onglets.forEach(function (tab, i) {
    tab.addEventListener('click', function () { montrer(tab); });

    // Les fleches deplacent la selection : c'est ce qu'attend un lecteur
    // d'ecran d'une bande d'onglets, et ce que fait le clavier partout ailleurs.
    tab.addEventListener('keydown', function (e) {
      var pas = e.key === 'ArrowRight' ? 1 : (e.key === 'ArrowLeft' ? -1 : 0);
      if (!pas) return;
      e.preventDefault();
      var suivant = onglets[(i + pas + onglets.length) % onglets.length];
      montrer(suivant);
      suivant.focus();
    });
  });

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

  var voile = document.getElementById('voile');
  var maquette = voile && voile.parentNode ? voile.parentNode.querySelector('img') : null;
  var kelvinIn = document.getElementById('kelvin');
  var lumIn = document.getElementById('lum');
  var kelvinOut = document.getElementById('kelvin-out');
  var lumOut = document.getElementById('lum-out');

  function peindre(kelvin, lum) {
    if (!voile) return;
    var m = multipliers(kelvin);

    // Sous 100 %, on retire de la lumiere : c'est le voile, en multiplication,
    // exactement comme la fenetre noire de l'application.
    var sombre = Math.min(1, lum / 100);
    voile.style.backgroundColor = 'rgb(' + Math.round(m[0] * 255 * sombre) + ','
                                         + Math.round(m[1] * 255 * sombre) + ','
                                         + Math.round(m[2] * 255 * sombre) + ')';

    // Au-dessus de 100 %, la carte graphique MULTIPLIE le signal : un voile ne
    // sait pas faire cela, un filtre de luminosite si. C'est le meme geste.
    if (maquette) {
      var gain = Math.max(1, lum / 100);
      maquette.style.filter = gain > 1 ? 'brightness(' + gain.toFixed(2) + ')' : '';
    }

    // La reglette suit ce qui est peint : pendant le rechauffement automatique,
    // un curseur qui reste en arriere raconte autre chose que l'image.
    if (kelvinIn && parseInt(kelvinIn.value, 10) !== kelvin) kelvinIn.value = kelvin;
    if (kelvinOut) kelvinOut.textContent = kelvin + ' K';
    if (lumOut) lumOut.textContent = lum + ' %';
  }

  function reglages() {
    return [parseInt(kelvinIn.value, 10), parseInt(lumIn.value, 10)];
  }

  if (voile && kelvinIn && lumIn) {
    kelvinIn.addEventListener('input', function () { var c = reglages(); peindre(c[0], c[1]); });
    lumIn.addEventListener('input', function () { var c = reglages(); peindre(c[0], c[1]); });

    // Le seul mouvement non demande de la page : a l'arrivee dans le champ de
    // vision, la maquette se rechauffe une fois, de la lumiere du jour vers
    // 4200 K. C'est la demonstration la plus courte du produit, et elle ne se
    // repete jamais.
    var depart = function () {
      if (reduced) { peindre(4200, 100); return; }
      var debut = null;
      requestAnimationFrame(function pas(maintenant) {
        if (debut === null) debut = maintenant;
        var t = Math.min(1, (maintenant - debut) / 1400);
        var adouci = 0.5 - 0.5 * Math.cos(Math.PI * t);
        peindre(Math.round(6500 - adouci * 2300), 100);
        if (t < 1) requestAnimationFrame(pas);
      });
    };

    peindre(6500, 100);
    if (window.IntersectionObserver) {
      var guetteur = new IntersectionObserver(function (entrees) {
        entrees.forEach(function (e) {
          if (!e.isIntersecting) return;
          guetteur.disconnect();
          depart();
        });
      }, { threshold: 0.4 });
      guetteur.observe(voile.parentNode);
    } else {
      depart();
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

  var etat = { vision: 'deuteranopia', severity: 0.7 };
  var avant = document.getElementById('avant');
  var apres = document.getElementById('apres');

  // Les deux verdicts, dans la langue de la page : le site anglais charge le
  // meme fichier, et une colonne qui dit « une seule couleur » a un lecteur
  // anglophone n'explique rien.
  var EN = document.documentElement.lang === 'en';
  var UNE = EN ? ' — one colour' : ' — une seule couleur';
  var DEUX = EN ? ' — two colours' : ' — deux couleurs';

  /** Une paire de pastilles jointives, suivie de la mesure qui la juge. */
  function paire(colonne, a, b, ecart) {
    var bande = document.createElement('div');
    bande.className = 'paire';
    [a, b].forEach(function (c) {
      var moitie = document.createElement('div');
      moitie.style.background = css(c);
      bande.appendChild(moitie);
    });
    colonne.appendChild(bande);

    var mesure = document.createElement('p');
    mesure.className = 'mesure';
    var chiffre = document.createElement('strong');
    chiffre.textContent = (EN ? ecart.toFixed(1) : fr(ecart)) + ' Delta E';
    mesure.appendChild(chiffre);
    mesure.appendChild(document.createTextNode(ecart < 2.3 ? UNE : DEUX));
    colonne.appendChild(mesure);
  }

  function dessiner() {
    if (!avant || !apres) return;
    var sim = simulation(etat.vision, etat.severity);
    var corrige = multiply(daltonize(etat.vision, etat.severity, 1.0), sim);
    var d = confusionDirection(etat.vision);

    while (avant.firstChild) avant.removeChild(avant.firstChild);
    while (apres.firstChild) apres.removeChild(apres.firstChild);

    ANCHORS.forEach(function (anchor) {
      var t = confusedSpread(anchor, d, sim);
      var a = rgbAt(anchor, d, -t / 2), b = rgbAt(anchor, d, t / 2);
      if (a[0] === b[0] && a[1] === b[1] && a[2] === b[2]) return;

      var sa = applyM(sim, a), sb = applyM(sim, b);
      var ca = applyM(corrige, a), cb = applyM(corrige, b);
      paire(avant, sa, sb, deltaE(sa, sb));
      paire(apres, ca, cb, deltaE(ca, cb));
    });
  }

  var choix = [].slice.call(document.querySelectorAll('[data-vision]'));
  choix.forEach(function (btn) {
    btn.addEventListener('click', function () {
      choix.forEach(function (b) {
        b.classList.remove('actif');
        b.setAttribute('aria-pressed', 'false');   // l'etat doit s'entendre, pas seulement se voir
      });
      btn.classList.add('actif');
      btn.setAttribute('aria-pressed', 'true');
      etat.vision = btn.getAttribute('data-vision');
      dessiner();
    });
  });

  var sev = document.getElementById('sev'), sevOut = document.getElementById('sev-out');
  if (sev) {
    sev.addEventListener('input', function () {
      etat.severity = parseInt(sev.value, 10) / 100;
      if (sevOut) sevOut.textContent = sev.value + ' %';
      dessiner();
    });
  }

  dessiner();

  // ------------------------------------------------------------------ plateforme

  // La page propose les deux systemes. Celui du visiteur passe devant : un
  // utilisateur de Mac a qui l'on presente d'abord un .exe croit, a juste titre,
  // que le logiciel n'est pas pour lui.
  //
  // La detection ne sert qu'a ORDONNER. Les deux boutons restent la, et restent
  // cliquables : une detection qui se trompe doit couter un regard, pas un
  // telechargement impossible.
  var SUR_MAC = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || '');

  if (SUR_MAC) {
    [['dl-win', 'dl-mac'], ['dl-win-2', 'dl-mac-2']].forEach(function (paire) {
      var win = document.getElementById(paire[0]);
      var mac = document.getElementById(paire[1]);
      if (!win || !mac || !mac.parentNode) return;
      mac.className = 'bouton grand';
      win.className = 'bouton clair grand';
      mac.parentNode.insertBefore(mac, win);
    });
    var barre = document.getElementById('dl-barre');
    if (barre) barre.href = document.getElementById('dl-mac').href;
  }

  // ------------------------------------------------------------------ version

  // Confort, pas necessite : si GitHub ne repond pas, le texte de la page reste
  // juste. Lecture publique, rien n'est envoye.
  //
  // On demande la LISTE des publications, et non « la derniere ». Les deux
  // versions vivent dans le meme depot sans suivre la meme numerotation : la
  // derniere publication est celle de Windows, et l'on y chercherait en vain le
  // paquet macOS.
  if (window.fetch) {
    fetch('https://api.github.com/repos/antoinebonpro/OpusScreen/releases?per_page=30')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (liste) {
        if (!liste || !liste.length) return;

        var win = null, mac = null;
        liste.forEach(function (pub) {
          if (pub.draft) return;
          (pub.assets || []).forEach(function (a) {
            if (!win && /\.exe$/i.test(a.name)) win = { v: numero(pub.tag_name), taille: a.size };
            if (!mac && /^OpusScreen-mac\.zip$/i.test(a.name)) {
              mac = { v: numero(pub.tag_name), url: a.browser_download_url };
            }
          });
        });

        // Le lien macOS est fige dans la page pour qu'il fonctionne sans script ;
        // s'il existe plus recent, on le remplace.
        if (mac) {
          ['dl-mac', 'dl-mac-2'].forEach(function (id) {
            var a = document.getElementById(id);
            if (a) a.href = mac.url;
          });
          if (SUR_MAC) {
            var barre2 = document.getElementById('dl-barre');
            if (barre2) barre2.href = mac.url;
          }
        }

        var ko = (win && win.taille) ? ' · ' + Math.round(win.taille / 1024) + (EN ? ' KB' : ' Ko') : '';
        var un = document.getElementById('release-meta');
        var deux = document.getElementById('release-meta-2');
        var w = win ? 'Version ' + win.v + ko + (EN ? ' · Windows 7 to 11' : ' · Windows 7 à 11') : '';
        var m = mac ? 'version ' + mac.v + (EN ? ' · macOS 13 and later' : ' · macOS 13 et plus') : '';
        var lien = (w && m) ? ' — ' : '';
        if (un && (w || m)) un.textContent = w + lien + m;
        if (deux && (w || m)) {
          deux.textContent = (win ? (EN ? 'Windows 7 to 11' : 'Windows 7 à 11') : '')
                           + (win && mac ? ' · ' : '')
                           + (mac ? (EN ? 'macOS 13 and later' : 'macOS 13 et plus') : '');
        }
      })
      .catch(function () { /* hors ligne : le texte ecrit suffit */ });
  }

  // « v3.4.0 », « mac-v1.0.0 » : le numero commence au premier chiffre.
  function numero(etiquette) {
    var m = String(etiquette || '').match(/\d+(\.\d+)*/);
    return m ? m[0].replace(/\.0$/, '') : '';
  }
})();
