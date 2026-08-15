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

---

## Organisation du code

Un fichier, une responsabilité. Aucun module ne connaît les autres étages ; seul
`DisplayController` les assemble.

```
src/
├── Native.cs               toutes les déclarations P/Invoke
│
├── MonitorEnum.cs          énumération des écrans, identifiants stables (EDID)
├── ColorTemp.cs            Kelvin → multiplicateurs RGB, ambiances f.lux
├── GammaEngine.cs          plan de luminosité, construction et pose de la LUT
├── ColorMatrixEffect.cs    matrice 5×5 : saturation, filtres
├── OverlayLens.cs          la « fade lens », technique PangoBright
├── HardwareBacklight.cs    DDC/CI et WMI, sur thread dédié
│
├── ContentAdaptive.cs      mesure du contenu affiché
├── AppWatcher.cs           application au premier plan, détection plein écran
├── SolarClock.cs           lever et coucher du soleil (algorithme NOAA)
├── Scheduler.cs            traduit l'heure en consigne
├── BreakReminder.cs        pauses 20-20-20
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
└── MakeIcon.cs             dessine assets/OpusScreen.ico, appelé par build.cmd
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
| Voile exclu des captures | Windows 10 version 2004 |
| Barre de titre sombre | Windows 10 version 1809 |

Chaque fonction indisponible se désactive proprement et le signale dans l'onglet
*Avancé*, plutôt que d'échouer en silence.

**Contrainte matérielle** : Windows ne dispose que d'**une seule table de couleurs par
carte graphique**. Deux programmes qui y écrivent se remplacent mutuellement en boucle.
`ConflictDetector` repère les plus courants (f.lux, PangoBright, Iris, Gammy…) et propose
de les fermer au démarrage.
