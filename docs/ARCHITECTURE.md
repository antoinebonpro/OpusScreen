# Architecture

## Le principe : quatre étages

Windows n'offre aucun moyen unique de régler la luminosité d'un écran. Il en existe
quatre, à des couches différentes du pipeline d'affichage, chacun avec ses forces et ses
limites. OpusScreen les combine.

```
   application dessine
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ④  matrice de couleur 5×5   (compositeur Windows)  │  ← mélange les canaux
   │      MagSetFullscreenColorEffect                    │     global au bureau
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ③  voile logiciel          (fenêtre par écran)     │  ← ne peut que soustraire
   │      SetLayeredWindowAttributes                     │     technique PangoBright
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ②  table de couleurs       (carte graphique)       │  ← peut dépasser 100 %
   │      SetDeviceGammaRamp                             │     technique f.lux
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ①  rétroéclairage physique (dalle)                 │  ← vrais photons
   │      DDC/CI (dxva2) ou WMI                          │     ni f.lux ni PangoBright
   └─────────────────────────────────────────────────────┘
          │
          ▼
      lumière émise
```

### Répartition d'une consigne

```
  consigne 5 → 150 %
        │
        ├─ > 100 %  ──▶ ① rétroéclairage poussé au maximum
        │               ② courbe gamma  out = in^(1/g)   — aucun écrêtage
        │               ③ gain linéaire, seulement au-delà de 135 %
        │
        └─ ≤ 100 %  ──▶ ② gain linéaire décroissant
                        ③ sous 35 %, le voile prend le relais jusqu'à 5 %

  en parallèle ──▶ ④ saturation, inversion, sépia, filtres daltonisme
```

### Pourquoi trois étages pour monter au-dessus de 100 %

Aucun ne suffit seul :

| Étage | Apport | Limite |
|---|---|---|
| ① Rétroéclairage | seul à produire réellement plus de lumière | déjà au maximum la plupart du temps |
| ② Courbe gamma | relève les tons moyens **sans rien écrêter** | ne touche pas au blanc maximum |
| ③ Gain linéaire | pousse tout, y compris le blanc | **écrête** les hautes lumières |

L'ordre est choisi pour n'écrêter qu'en dernier recours.

### Calibration mesurée

Luminance au gris moyen (entrée 0,5), mesurée par `EngineTest` :

| Consigne | gamma | gain | écrêtage | gris moyen |
|---:|---:|---:|:---:|---:|
| 5 % | 1,00 | 0,35 + voile | non | 0,025 |
| 50 % | 1,00 | 0,50 | non | 0,250 |
| 100 % | 1,00 | 1,00 | non | 0,500 |
| 125 % | 1,40 | 1,00 | **non** | 0,610 |
| 135 % | 1,56 | 1,00 | **non** | 0,641 |
| 150 % | 1,80 | 1,12 | oui | 0,762 |

À 150 %, les tons moyens gagnent **+52 %** de luminance. **Rien n'est écrêté jusqu'à 135 %.**

---

## L'étage 2 : la table de couleurs

Une seule passe fusionne tous les réglages qui n'exigent pas de mélange entre canaux :

```
courbe → contraste → gain → température × balance des canaux
```

```csharp
v = (i / 255)^(1/gamma)                  // forme de la réponse
v = 0.5 + (v - 0.5) × contraste          // étalement autour du gris moyen
v = v × gain                             // niveau général
ramp[c][i] = v × tempMult[c] × userGain[c] × 65535
```

### Deux pièges Windows

**1. Windows rabote les rampes.** Depuis Vista, GDI refuse ou écrête silencieusement les
courbes trop éloignées de la linéaire. Le déblocage passe par :

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM
   GdiIcmGammaRange = 256   (DWORD)
```

Administrateur, puis réouverture de session. OpusScreen le détecte en relisant la rampe
après l'avoir écrite, et redescend progressivement jusqu'à une version acceptée plutôt
que d'échouer en silence.

**2. La rampe survit au processus.** Voir [SECURITE.md](SECURITE.md).

---

## L'étage 4 : la matrice de couleur

**Pourquoi il existe.** Une table de couleurs traite chaque canal *indépendamment* :
elle sait assombrir le bleu, mais pas calculer un rouge qui dépend du vert. Or c'est
exactement ce qu'exigent la saturation, l'inversion, le sépia et les filtres pour
daltoniens.

`MagSetFullscreenColorEffect` applique une matrice 5×5 sur tout le bureau, au niveau du
compositeur. Convention : le pixel est un vecteur **ligne** `[R G B A 1]` multiplié à
gauche de la matrice.

### Les filtres daltonisme

Ce sont des filtres d'**assistance**, pas des simulations de la vision déficiente.

```
erreur   = pixel × (I − Simulation)
résultat = pixel + erreur × Redistribution
d'où  M  = I + (I − Simulation) × Redistribution
```

L'ordre des deux produits n'est pas interchangeable : la redistribution s'applique *à
l'erreur*, pas l'inverse.

**Propriété à préserver** : comme la simulation laisse les gris intacts, chaque colonne
de `(I − Simulation)` est de somme nulle. Un gris produit donc une erreur nulle et
ressort inchangé — le filtre ne teinte jamais l'interface. Vérifié par `MatrixTest` :
0,50 → 0,50 exactement pour les trois filtres, tandis que rouge et vert restent distincts.

#### La gravité : pourquoi une dichromatie complète est le mauvais réglage par défaut

La **dichromatie** — un type de cône totalement absent — est le cas rare. Le cas
fréquent, et de très loin, est l'**anomalie** : le cône existe mais sa sensibilité est
décalée, et la confusion n'est que partielle. Un filtre calibré uniquement sur la
dichromatie sur-corrige donc la majorité des personnes concernées : l'écran devient
criard sans être plus lisible.

```
Simulation(s) = (1 − s) × I  +  s × Simulation_complète
M(s, k)       = I + k × (I − Simulation(s)) × Redistribution
```

`s` est la gravité (0 = vision normale, 1 = dichromatie), `k` l'intensité de la
correction. C'est une **approximation assumée** : le modèle exact demanderait de décaler
le pic d'absorption du cône dans l'espace LMS, ce qu'une interpolation linéaire ne sait
pas représenter. Elle conserve en revanche la propriété qui compte — l'axe de confusion
reste le même, seule son amplitude change — et c'est exactement ce que fait le réglage
d'intensité de macOS.

À `s = 0` comme à `k = 0`, la matrice redevient l'identité **exactement** : descendre un
curseur à zéro rend l'écran d'origine, pas « presque » l'écran d'origine.

#### La direction de confusion, calculée et non devinée

Le comparateur de la page Vision doit montrer des couleurs que la personne confond
*réellement*. Elles sont obtenues en cherchant la direction que la simulation écrase le
plus : le vecteur `v` qui minimise `|v × M|`, c'est-à-dire le vecteur propre de `M × Mᵀ`
associé à la plus petite valeur propre, trouvé par itération inverse. L'écart le long de
cet axe est ensuite calibré par dichotomie pour rester **sous le seuil de perception**
(ΔE 2,3 en CIE Lab).

Ce détour n'est pas de la coquetterie : une première version listait des paires écrites
à la main d'après le sens commun — rouge/vert, rose/gris. Mesurées, elles se révélaient
parfaitement distinctes une fois simulées, car elles différaient surtout par la
**clarté**, que la déficience ne touche pas.

#### Une limite honnête : l'effet est global au bureau

`MagSetFullscreenColorEffect` n'expose qu'un effet pour **tout** le bureau. La
saturation et les filtres ne peuvent donc pas différer d'un écran à l'autre — c'est une
contrainte de l'API, pas un choix. Plutôt que de laisser un écran arbitraire décider
pour les autres, un **écran de référence** est désigné explicitement (page Écrans), et
l'interface le dit. Les trois autres étages, eux, restent bien réglables écran par écran.

---

## Organisation du code

Un fichier, une responsabilité. Aucun module ne connaît les autres étages ; seul
`DisplayController` les assemble.

```
src/
├── Native.cs               toutes les déclarations P/Invoke
│
├── MonitorEnum.cs          énumération des écrans, identifiants uniques
├── DisplayConfig.cs        noms EDID réels, connectique, détection de la dalle interne
├── ColorTemp.cs            Kelvin → multiplicateurs RGB, ambiances f.lux
├── GammaEngine.cs          plan de luminosité, construction et pose de la LUT
├── ColorMatrixEffect.cs    matrice 5×5 : saturation, filtres, gravité
├── OverlayLens.cs          la « fade lens », technique PangoBright
├── HardwareBacklight.cs    DDC/CI et WMI, sur thread dédié
│
├── ContentAdaptive.cs      mesure du contenu affiché
├── AppWatcher.cs           application au premier plan, détection plein écran
├── SolarClock.cs           lever et coucher du soleil (algorithme NOAA)
├── Scheduler.cs            traduit l'heure en consigne
├── BreakReminder.cs        pauses 20-20-20 et rappels de clignement
│
├── Vision.cs               savoir métier : déficiences, paires de confusion, noms
├── ColorReader.cs          identificateur de couleur sous le pointeur
├── ScreenMagnifier.cs      loupe plein écran (API Magnification)
├── CursorBeacon.cs         anneau de repérage autour du pointeur
│
├── SafetyGuard.cs          les cinq protections anti-écran-noir
├── GammaUnlock.cs          déblocage de la plage gamma Windows
├── IntelDpst.cs            détection DPST / LACE des pilotes Intel
├── ConflictDetector.cs     autres programmes pilotant la même table
│
├── DisplayController.cs    assemble les quatre étages, gère les transitions
├── Profile.cs              un jeu complet de réglages
├── Settings.cs             persistance, import/export
│
├── Theme.cs                jetons de design, contrastes vérifiés
├── UiKit.cs                briques d'interface réutilisables
├── DarkControls.cs         contrôles au thème sombre
├── Slider.cs               curseur dessiné à la main
├── ConfirmDialog.cs        confirmation à rebours
│
├── SettingsPage.cs         base commune aux pages
├── PageDisplay.cs          page Écran
├── PageColor.cs            page Couleur
├── PageVision.cs           page Vision et comparateur de couleurs confondues
├── PageAuto.cs             pages Automatisme et Applications
├── PageScreens.cs          pages Écrans et Confort
├── PageAdvanced.cs         pages Raccourcis et Avancé
├── ControlPanel.cs         coquille de la fenêtre
│
├── AppIcon.cs              icône de l'application, embarquée dans l'exécutable
├── Taskbar.cs              raccourci du menu Démarrer, liste de tâches épinglée
│
├── TrayApp.cs              cycle de vie, événements système, raccourcis
├── CommandLine.cs          pilotage en ligne de commande
└── Program.cs              point d'entrée, filets de sécurité

tools/
└── MakeIcon.cs             dérive assets/OpusScreen.ico de assets/logo.png

assets/
├── logo.png                le logo, embarqué en pleine résolution dans l'exécutable
└── OpusScreen.ico          généré : recadré au centre sous 48 px pour rester lisible
```

### Épinglage à la barre des tâches

Windows n'épingle pas un exécutable, il épingle un **raccourci**, et regroupe les
fenêtres sous cette épingle par un identifiant d'application. Trois décisions en
découlent :

- **Aucun identifiant explicite n'est posé.** Windows en dérive un du chemin de
  l'exécutable. Un identifiant maison ferait apparaître deux boutons côte à côte pour
  un seul programme dès que l'utilisateur épingle l'exécutable lui-même plutôt que
  notre raccourci.
- **Un raccourci est déposé dans le menu Démarrer** à chaque démarrage, et sa cible
  corrigée si l'exécutable a changé de dossier.
- **Un second lancement ne refuse plus de démarrer.** Une application épinglée est
  relancée à chaque clic sur son icône : le nouveau processus diffuse un message
  enregistré, l'instance en cours ouvre sa fenêtre, et le nouveau processus s'efface.
  Le fichier d'ordres existant restait trop lent pour ce geste (jusqu'à une seconde).

L'épinglage proprement dit reste **un geste de l'utilisateur** : depuis Windows 10
version 1607, le shell ignore le verbe correspondant. L'application prépare le
raccourci et conduit l'utilisateur jusqu'à lui.

### Flux d'une modification

```
interface / raccourci / ligne de commande
        │
        ▼
   Settings.Current            ← le modèle, source unique de vérité
        │
        ▼
   TrayApp.ApplyAll()          ← laisse d'abord parler les automatismes
        │                         (planification, adaptation au contenu)
        ▼
   DisplayController.Apply()   ← calcule le plan, interpole si fondu
        │
        ├──▶ HardwareBacklight.RequestLevel()   (thread dédié, non bloquant)
        ├──▶ GammaEngine.Apply()                (par écran)
        ├──▶ ColorMatrixEffect.Apply()          (global)
        └──▶ OverlaySet.Update()                (par écran)
```

---

## Choix techniques notables

**Interface dessinée à la main.** Les contrôles natifs de WinForms délèguent leur rendu
au thème de Windows : sur fond sombre, une case à cocher devient illisible quelle que
soit la couleur demandée. Curseurs, interrupteurs, cases et icônes sont donc redessinés.

**Aucun emoji comme icône.** Un emoji change de dessin selon la police installée, ignore
la couleur du thème et rend mal à 16 px. Les huit icônes de navigation sont tracées au
vecteur.

**Le voile est exclu des captures d'écran** (`WDA_EXCLUDEFROMCAPTURE`). Double bénéfice :
l'analyse de contenu ne se mesure pas elle-même — ce qui interdit toute oscillation —
et les captures de l'utilisateur sortent propres, défaut connu de PangoBright.

**Conscience du DPI.** Sans `SetProcessDpiAwarenessContext`, le voile serait placé en
coordonnées logiques sur un écran à mise à l'échelle et ne couvrirait pas toute la surface.

**Le plein écran ne suspend que le voile.** Les quatre étages n'y réagissent pas de la
même façon : le voile est une fenêtre `TOPMOST` posée sur l'écran, que le plein écran
supporte mal ; la table de couleurs, elle, est appliquée par la carte graphique en sortie
et traverse jeux et vidéos sans dommage. Or c'est elle, avec le rétroéclairage, qui porte
tout le boost au-delà de 100 % — et le voile n'existe même pas dans cette plage
(`GammaEngine.Plan` ne le convoque qu'en dessous de 35 %). Tout suspendre revenait donc à
retirer la luminosité au moment précis où un film sombre en a le plus besoin.
`DisplayController` distingue pour cela deux niveaux : `Suspend()`, qui rend l'écran
intact, et `HoldOverlay()`, qui ne retire que l'étage ③. Le réglage
*Applications → En plein écran* choisit entre les deux, ou aucun des deux.

**Les appels DDC/CI vivent sur leur propre thread.** Ils prennent parfois 500 ms ; les
faire sur le thread d'interface figerait le curseur pendant le glissement.

---

## Compatibilité

| Fonction | Exigence minimale |
|---|---|
| Table de couleurs, voile, interface | Windows 7 |
| Rétroéclairage DDC/CI | écran externe compatible, Windows 7 |
| Rétroéclairage WMI | dalle de portable, Windows 7 |
| Matrice de couleur (saturation, filtres) | Windows 8 |
| Loupe plein écran | Windows 8 — repli sur la loupe de Windows sinon |
| Noms d'écran réels et détection de la dalle interne | Windows 7 — repli sur `EnumDisplayDevices` sinon |
| Voile exclu des captures | Windows 10 version 2004 |
| Barre de titre sombre | Windows 10 version 1809 |

Chaque fonction indisponible se désactive proprement et le signale dans l'onglet
*Avancé*, plutôt que d'échouer en silence.

**Contrainte matérielle** : Windows ne dispose que d'**une seule table de couleurs par
carte graphique**. Deux programmes qui y écrivent se remplacent mutuellement en boucle.
`ConflictDetector` repère les plus courants (f.lux, PangoBright, Iris, Gammy…) et propose
de les fermer au démarrage.
