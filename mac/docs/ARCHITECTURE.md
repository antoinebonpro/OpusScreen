# Architecture

## Le principe : quatre étages

Aucun système n'offre un moyen unique de régler la luminosité d'un écran. Il en existe
quatre, à des couches différentes du pipeline d'affichage, chacun avec ses forces et ses
limites. OpusScreen les combine — sur macOS comme sur Windows, avec les mêmes rôles et des
mécanismes différents.

```
   application dessine
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ④  matrice de couleur 5×5                          │  ← mélange les canaux
   │      ScreenCaptureKit + nuanceur Metal              │     réglable PAR ÉCRAN
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ③  voile logiciel          (fenêtre par écran)     │  ← ne peut que soustraire
   │      NSPanel, sharingType = .none                   │     technique PangoBright
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ②  table de couleurs       (carte graphique)       │  ← peut dépasser 100 %
   │      CGSetDisplayTransferByTable                    │     technique f.lux
   └─────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────────────────────────────────────────┐
   │  ①  rétroéclairage physique (dalle)                 │  ← vrais photons
   │      DisplayServices, ou DDC/CI                     │     ni f.lux ni PangoBright
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

## L'étage 1 : le rétroéclairage

Deux chemins, selon la dalle.

**Dalle interne** — `DisplayServicesSetBrightness`, une fonction du cadre privé
`DisplayServices`. Elle est chargée à l'exécution par `dlsym` : si elle disparaît d'une
version de macOS, l'étage se signale indisponible au lieu d'empêcher l'application de
démarrer. Un second chemin, public et bien plus ancien, prend le relais :
`IODisplaySetFloatParameter` sur le service `IODisplayConnect`.

**Écrans externes** — DDC/CI, le protocole du menu intégré du moniteur. C'est là que les
deux architectures divergent :

- **Apple Silicon** : `IOAVServiceWriteI2C`, sur le service `DCPAVServiceProxy` de l'écran.
  Aucune correspondance officielle n'existe entre un identifiant CoreGraphics et un service
  du registre : on apparie les services externes aux écrans externes **dans l'ordre**, ce
  qui est la pratique établie. C'est aussi pourquoi le DDC/CI est **vérifié avant d'être
  annoncé** — un appariement supposé ne vaut que confirmé par une réponse de l'écran.
- **Intel** : `IOI2CSendRequest` sur le `IOFramebuffer`, l'API publique historique.

Les appels DDC/CI prennent parfois 500 ms. Tout passe par une file dédiée avec fusion des
demandes : seule la dernière consigne reçue pour un écran est réellement appliquée, et le
curseur de l'interface ne se fige jamais pendant le glissement.

---

## L'étage 2 : la table de couleurs

Une seule passe fusionne tous les réglages qui n'exigent pas de mélange entre canaux :

```
courbe → contraste → gain → température × balance des canaux
```

```swift
v = (i / 255)^(1/gamma)                  // forme de la réponse
v = 0.5 + (v - 0.5) × contraste          // étalement autour du gris moyen
v = v × gain                             // niveau général
ramp[c][i] = v × tempMult[c] × userGain[c] × 65535
```

### Deux différences avec Windows

**1. macOS ne rabote pas les courbes.** Windows refusait ou écrêtait silencieusement les
tables trop éloignées de la linéaire, et il fallait débloquer `GdiIcmGammaRange` dans le
registre, en administrateur, avec une réouverture de session. Ce module entier disparaît
ici : `CGSetDisplayTransferByTable` accepte la table telle quelle. Le repli progressif est
conservé pour les cas où le système refuse quand même — session distante, écran virtuel.

**2. La table est PAR ÉCRAN.** Windows n'en avait qu'une par carte graphique. C'est ce qui
rendait les conflits avec f.lux si violents, et c'est une contrainte de moins ici.

**3. La table ne survit PAS au processus.** C'est la troisième différence, et la plus
importante pour la sécurité : macOS rend la table d'origine dès que le client qui l'avait
posée disparaît, `SIGKILL` compris. Le danger central de la version Windows n'existe pas
ici. Ce qui reste est le cas du processus figé — voir [SECURITE.md](SECURITE.md).

---

## L'étage 4 : la matrice de couleur

**Pourquoi il existe.** Une table de couleurs traite chaque canal *indépendamment* : elle
sait assombrir le bleu, mais pas calculer un rouge qui dépend du vert. Or c'est exactement
ce qu'exigent la saturation, l'inversion, le sépia et les filtres pour daltoniens.

**Pourquoi il a fallu le reconstruire.** Windows offrait `MagSetFullscreenColorEffect` : une
matrice 5×5 posée par le compositeur, en un appel. macOS n'a pas d'équivalent — ses filtres
de couleur d'accessibilité n'acceptent que cinq catégories figées, sans matrice libre.

L'étage est donc bâti ainsi :

```
   SCStream (ScreenCaptureKit)      capture l'affichage, 60 images/s, sRGB
          │
          ▼
   nuanceur Metal                   matrice 5×5 + agrandissement, en une passe
          │
          ▼
   NSPanel plein écran              sharingType = .none  ← s'exclut de sa propre capture
```

Trois points méritent d'être dits :

- **Le nuanceur est compilé à l'exécution**, par `makeLibrary(source:)`. Le compilateur
  `metal` n'est livré qu'avec Xcode, et cette application se construit avec les seuls outils
  en ligne de commande.
- **La matrice est appliquée sur les valeurs telles qu'elles sont encodées**, sans passer
  par le linéaire. Ce n'est pas un oubli : c'est ce que faisait le compositeur de Windows,
  c'est ce que fait `ColorMatrixEffect.transform` qui sert aux aperçus et aux tests, et
  c'est la seule façon que l'aperçu de la page Couleur montre exactement ce que l'écran
  affichera.
- **La fenêtre s'exclut de sa propre capture.** Sans cela le filtre se filmerait lui-même et
  l'image partirait en boucle. `sharingType = .none` est l'équivalent exact de
  `WDA_EXCLUDEFROMCAPTURE`, et il rend au passage les captures de l'utilisateur propres.

### Ce que le portage gagne

La matrice est **réglable écran par écran**, puisque chaque écran a sa propre passe de
rendu. C'était la limite que la documentation Windows signalait comme une contrainte de
l'API. Le réglage « écran de référence » demeure, mais comme un choix.

### Ce qu'il coûte, dit sans détour

- L'autorisation **« Enregistrement de l'écran »** est nécessaire. Sans elle, l'étage
  s'annonce indisponible — exactement comme la version Windows le faisait quand
  `magnification.dll` manquait. La luminosité et la température, elles, fonctionnent.
- Le **pointeur de la souris** est dessiné par le système au-dessus de toutes les fenêtres :
  il n'est donc pas recoloré par la matrice. Sous la loupe, un pointeur agrandi est ajouté à
  l'image pour que la cible reste visible.
- C'est l'étage le plus coûteux en calcul. Il ne s'arme que lorsqu'un filtre, une saturation
  ou la loupe le demandent, et se démonte dès qu'ils cessent.

### Les filtres daltonisme

Ce sont des filtres d'**assistance**, pas des simulations de la vision déficiente.

```
erreur   = pixel × (I − Simulation)
résultat = pixel + erreur × Redistribution
d'où  M  = I + (I − Simulation) × Redistribution
```

L'ordre des deux produits n'est pas interchangeable : la redistribution s'applique *à
l'erreur*, pas l'inverse.

**Propriété à préserver** : comme la simulation laisse les gris intacts, chaque colonne de
`(I − Simulation)` est de somme nulle. Un gris produit donc une erreur nulle et ressort
inchangé — le filtre ne teinte jamais l'interface. Vérifié par `MatrixTest`.

#### La gravité : pourquoi une dichromatie complète est le mauvais réglage par défaut

La **dichromatie** — un type de cône totalement absent — est le cas rare. Le cas fréquent,
et de très loin, est l'**anomalie** : le cône existe mais sa sensibilité est décalée. Un
filtre calibré uniquement sur la dichromatie sur-corrige donc la majorité des personnes
concernées.

```
Simulation(s) = (1 − s) × I  +  s × Simulation_complète
M(s, k)       = I + k × (I − Simulation(s)) × Redistribution
```

À `s = 0` comme à `k = 0`, la matrice redevient l'identité **exactement** : descendre un
curseur à zéro rend l'écran d'origine, pas « presque » l'écran d'origine.

#### Une transposition qui ne pardonne pas

La convention de la matrice est celle de l'API Windows : le pixel est un vecteur **ligne**.
Metal multiplie une matrice par un vecteur **colonne**. Les colonnes du `float3x3` envoyé au
nuanceur sont donc les lignes de la matrice d'origine.

C'est exactement le genre de détail qui, mal traité, rend des couleurs plausibles et
fausses. D'où la transposition explicite — et le test qui la vérifie en comparant le calcul
du nuanceur à `ColorMatrixEffect.transform`, couleur par couleur.

#### La direction de confusion, calculée et non devinée

Le comparateur doit montrer des couleurs que la personne confond *réellement*. Elles sont
obtenues en cherchant la direction que la simulation écrase le plus : le vecteur `v` qui
minimise `|v × M|`, c'est-à-dire le vecteur propre de `M × Mᵀ` associé à la plus petite
valeur propre, trouvé par itération inverse. L'écart le long de cet axe est ensuite calibré
par dichotomie pour rester **sous le seuil de perception** (ΔE 2,3 en CIE Lab).

Ce détour n'est pas de la coquetterie : une première version listait des paires écrites à la
main d'après le sens commun. Mesurées, elles se révélaient parfaitement distinctes une fois
simulées, car elles différaient surtout par la **clarté**, que la déficience ne touche pas.

---

## Organisation du code

Un fichier, une responsabilité. Aucun module ne connaît les autres étages ; seul
`DisplayController` les assemble.

```
Sources/OpusScreen/
├── Core/
│   ├── Native.swift            table de couleurs, chargement tardif, géométrie
│   ├── MonitorEnum.swift       énumération des écrans, identifiants uniques
│   └── DisplayConfig.swift     noms réels, connectique, services IOKit
│
├── Engine/                     aucun appel système : testable à froid
│   ├── RGB.swift               une couleur sRGB, et rien d'autre
│   ├── ColorTemp.swift         Kelvin → multiplicateurs RGB, ambiances f.lux
│   ├── GammaEngine.swift       plan de luminosité, construction et pose de la table
│   ├── ColorMatrixEffect.swift matrice 5×5 : saturation, filtres, gravité
│   ├── Vision.swift            déficiences, paires de confusion, noms de couleurs
│   ├── VisionExam.swift        planches, escalier adaptatif, ajustement
│   ├── Profile.swift           un jeu complet de réglages
│   ├── Settings.swift          persistance, format compatible Windows
│   ├── SolarClock.swift        lever et coucher du soleil (algorithme NOAA)
│   ├── Scheduler.swift         traduit l'heure en consigne
│   └── SafetyGuard.swift       les cinq protections anti-écran-noir
│
├── Layers/
│   ├── HardwareBacklight.swift DisplayServices et DDC/CI, sur file dédiée
│   ├── OverlayLens.swift       la « fade lens », technique PangoBright
│   ├── ScreenFilter.swift      ScreenCaptureKit + Metal : matrice et loupe
│   ├── ScreenMagnifier.swift   façade de la loupe
│   ├── CursorBeacon.swift      anneau de repérage autour du pointeur
│   └── ColorReader.swift       identificateur de couleur sous le pointeur
│
├── Automation/
│   ├── ContentAdaptive.swift   mesure du contenu affiché
│   ├── AppWatcher.swift        application au premier plan, détection plein écran
│   ├── BreakReminder.swift     pauses 20-20-20 et rappels de clignement
│   ├── ConflictDetector.swift  f.lux, Lunar, Night Shift, filtres de couleur macOS
│   ├── AutoBrightness.swift    le piège macOS : luminosité automatique, True Tone
│   └── SystemVolume.swift      CoreAudio, et ce que macOS ne permet pas
│
├── Controller/
│   └── DisplayController.swift assemble les quatre étages, gère les transitions
│
├── App/
│   ├── Entry.swift             point d'entrée, filets de sécurité, instance unique
│   ├── TrayApp.swift           cycle de vie, menu, événements système
│   ├── TrayGlyph.swift         l'icône de la barre des menus, tracée au vecteur
│   ├── Hotkeys.swift           raccourcis globaux, et le raccourci de secours
│   ├── CommandLine.swift       pilotage en ligne de commande
│   ├── Installer.swift         rangement dans /Applications, désinstallation
│   └── Updater.swift           vérification quotidienne chez GitHub
│
└── UI/
    ├── Theme.swift             jetons de design, contrastes vérifiés
    ├── Draw.swift              les gestes de dessin que tout répète
    ├── UiKit.swift             lignes de réglage réutilisables
    ├── Slider.swift            curseur et interrupteur dessinés à la main
    ├── DarkControls.swift      bouton et liste déroulante au thème
    ├── SideNav.swift           colonne de navigation, icônes vectorielles
    ├── SettingsPage.swift      base commune aux pages
    ├── ControlPanel.swift      coquille de la fenêtre
    ├── Page*.swift             les onze pages
    ├── VisionWidgets.swift     comparateur de couleurs, teintes de lecture
    ├── VisionExamDialog.swift  la fenêtre du test guidé
    └── Dialogs.swift           alertes, saisie, confirmation à rebours
```

### Flux d'une modification

```
interface / raccourci / ligne de commande
        │
        ▼
   Settings.current            ← le modèle, source unique de vérité
        │
        ▼
   TrayApp.applyAll()          ← laisse d'abord parler les automatismes
        │                         (planification, adaptation au contenu)
        ▼
   DisplayController.apply()   ← calcule le plan, interpole si fondu
        │
        ├──▶ HardwareBacklight.requestLevel()   (file dédiée, non bloquante)
        ├──▶ GammaEngine.apply()                (par écran)
        ├──▶ ScreenFilter.setMatrices()         (par écran)
        └──▶ OverlaySet.update()                (par écran)
```

---

## Choix techniques notables

**Interface dessinée à la main.** Les contrôles natifs délèguent leur rendu au thème du
système : sur un fond sombre choisi par l'application — et non par le système — ils restent
clairs et le texte devient illisible. Curseurs, interrupteurs, listes et icônes sont donc
redessinés. Et puisqu'un contrôle dessiné est invisible pour VoiceOver, **chacun déclare son
rôle, son nom et sa valeur**.

**Aucun emoji comme icône.** Un emoji change de dessin selon la police installée, ignore la
couleur du thème et rend mal à dix-huit points. Les onze icônes de navigation sont tracées
au vecteur.

**Mesurer et dessiner avec les mêmes options.** Un texte mesuré avec `usesFontLeading` et
dessiné sans compte une interligne différente : une fraction de point par ligne, assez pour
qu'une dernière ligne disparaisse d'un paragraphe de quatre. Les deux chemins passent par
`Draw`, avec les mêmes options.

**Pas de mise à l'échelle à faire.** Sur Windows, les polices grandissaient avec la densité
de l'écran tandis que les boîtes écrites en pixels ne bougeaient pas — tout se tassait
au-delà de 100 %. AppKit ne connaît que des points, et c'est le système qui multiplie.
`Theme.px` est conservé, et rend l'identité.

**Le plein écran ne suspend que le voile.** Les quatre étages n'y réagissent pas de la même
façon : le voile est une fenêtre posée sur l'écran, que le plein écran supporte mal ; la
table de couleurs, elle, est appliquée en sortie et traverse jeux et vidéos sans dommage. Or
c'est elle, avec le rétroéclairage, qui porte tout le boost au-delà de 100 %. Tout
suspendre revenait à retirer la luminosité au moment précis où un film sombre en a le plus
besoin.

---

## Compatibilité

| Fonction | Exigence minimale |
|---|---|
| Table de couleurs, voile, interface | macOS 13 |
| Rétroéclairage de la dalle interne | macOS 13 |
| Rétroéclairage DDC/CI | écran externe compatible |
| Matrice de couleur, loupe | macOS 13 + autorisation d'enregistrement de l'écran |
| Fil de secours autonome | autorisation d'accessibilité (sinon repli) |
| Lancement à l'ouverture de session | macOS 13 (`SMAppService`) |

Chaque fonction indisponible se désactive proprement et le signale dans l'onglet *Avancé*,
plutôt que d'échouer en silence.

**Contrainte partagée** : une seule table de couleurs par écran. Deux programmes qui y
écrivent se remplacent mutuellement en boucle. `ConflictDetector` repère les plus courants —
f.lux, Lunar, Iris, Gammy, MonitorControl — **ainsi que Night Shift et les filtres de
couleur de macOS**, qui sont des concurrents que Windows n'avait pas.
