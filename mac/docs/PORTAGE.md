# Ce qui change par rapport à Windows, et pourquoi

Ce document existe parce qu'un portage honnête doit dire où il diffère. Toutes les
fonctions de la version Windows sont présentes ; certaines reposent sur d'autres
mécanismes, deux sont meilleures, deux sont moindres, et trois modules Windows n'ont plus
d'objet.

---

## Les quatre étages, système par système

| Étage | Windows | macOS |
|---|---|---|
| ① Rétroéclairage | DDC/CI (dxva2) ou WMI | `DisplayServices` (dalle interne), DDC/CI via `IOAVService` (Apple Silicon) ou `IOI2CSendRequest` (Intel) |
| ② Table de couleurs | `SetDeviceGammaRamp`, **une par carte graphique** | `CGSetDisplayTransferByTable`, **une par écran** |
| ③ Voile | fenêtre `WS_EX_LAYERED` + `WDA_EXCLUDEFROMCAPTURE` | `NSPanel` + `sharingType = .none` |
| ④ Matrice de couleur | `MagSetFullscreenColorEffect`, **globale au bureau** | ScreenCaptureKit + nuanceur Metal, **par écran** |
| Loupe | `MagSetFullscreenTransform` | même passe Metal que ④ |

---

## Ce qui est meilleur

### La matrice de couleur est réglable écran par écran

Sur Windows, `MagSetFullscreenColorEffect` n'exposait qu'un effet pour tout le bureau. La
documentation d'origine le signalait comme une limite de l'API, et l'application désignait
un « écran de référence » faute de mieux.

Ici la matrice est recalculée par écran, puisque chaque écran a sa propre passe de rendu.
Le réglage demeure, mais il devient un **choix** : une correction daltonienne qui change
d'un écran à l'autre perturbe plus qu'elle n'aide, et certaines personnes préfèrent donc un
filtre unique.

### La table de couleurs ne survit pas au processus

C'est la différence qui compte le plus, et elle a été mesurée : macOS rend la table
d'origine dès que le processus qui l'avait posée disparaît, `SIGKILL` compris. Sur Windows,
elle reste — c'est le danger central que les cinq protections adressent.

Les protections restent justifiées, pour un cas plus étroit : un processus **figé** détient
toujours sa table et ses fenêtres, et personne ne les lui reprendra. C'est exactement ce que
le raccourci de secours et son chien de garde traitent.

### La table de couleurs n'est plus bridée

Windows rabotait silencieusement les courbes trop éloignées de la linéaire. Le déblocage
demandait une écriture dans le registre en administrateur (`GdiIcmGammaRange = 256`) et une
réouverture de session — tout un module, `GammaUnlock.cs`, existait pour cela, plus un
avertissement dans l'interface.

macOS accepte la table telle quelle. Le module disparaît. Le repli progressif est conservé
pour les cas où le système refuse quand même : session distante, écran virtuel.

---

## Ce qui est moindre, et dit comme tel

### L'étage ④ demande une autorisation

Windows posait la matrice en un appel, sans rien demander. Ici il faut lire l'image
affichée, donc l'autorisation **« Enregistrement de l'écran »**. Rien n'est enregistré et
rien ne sort de la machine, mais l'autorisation est bien celle-là, et macOS ne la présente
pas autrement.

Sans elle, la saturation, les filtres et la loupe sont indisponibles et le disent. La
luminosité et la température continuent de fonctionner : c'est le même comportement que la
version Windows quand `magnification.dll` manquait.

### Le pointeur n'est pas filtré

Le pointeur est dessiné par le système au-dessus de toutes les fenêtres, y compris la nôtre.
Il n'est donc pas recoloré par la matrice. Sous la loupe, un pointeur agrandi est **ajouté à
l'image** pour que la cible reste visible ; sans agrandissement, le pointeur garde ses
couleurs d'origine.

### Le fil de secours dépend d'une autorisation

Sur Windows, `RegisterHotKey` avec un `hwnd` nul déposait `WM_HOTKEY` directement dans la
file d'un fil dédié : le raccourci de secours répondait même si l'interface était figée.

macOS distribue les raccourcis Carbon par la boucle principale — celle qui peut justement
être bloquée. Deux chemins sont donc posés :

1. **Un capteur d'événements sur un fil dédié**, avec sa propre boucle. C'est l'équivalent
   exact du fil de secours de Windows. Il demande l'autorisation d'accessibilité.
2. **À défaut, le raccourci Carbon ordinaire**, qui couvre tous les cas sauf celui d'une
   interface totalement bloquée.

Dans les deux cas, la restauration de la table de couleurs ne passe pas par l'interface, et
le processus se termine si le fil principal ne répond pas dans les trois secondes. Un écran
rendu vaut mieux qu'une application qui tient.

### Il n'y a pas de mixeur par application

C'était l'une des fonctions les plus utiles de la version Windows : « tout remettre au
maximum » récupérait le volume que chaque application avait perdu dans le mixeur, un panneau
que peu de gens savent où trouver.

**macOS n'a pas de mixeur par application.** Il n'existe aucun volume propre à Safari ou à
VLC au niveau du système. Il n'y a donc rien à récupérer, et prétendre le contraire serait
inventer une fonction. Ce qui reste est vrai : le volume de sortie, le silence, et le
plafond matériel en décibels. La page le dit en toutes lettres.

---

## Ce qui n'a plus d'objet

| Module Windows | Sort sur macOS |
|---|---|
| `GammaUnlock.cs` | supprimé — macOS ne bride pas les tables |
| `IntelDpst.cs` | **remplacé** par `AutoBrightness.swift` : même piège, autre nom |
| `Taskbar.cs` | remplacé par la barre des menus et le réglage « montrer dans le Dock » |
| `Installer.cs` (copie dans `%LOCALAPPDATA%`) | réduit à une proposition de rangement dans `/Applications` |
| Conscience du DPI (`SetProcessDpiAwarenessContext`) | inutile — AppKit travaille en points |

### Le piège Intel devient le piège Apple

Le module `IntelDpst` détectait le DPST et le LACE des pilotes Intel : deux économiseurs
d'énergie qui font varier la luminosité selon le contenu, **en aval** de la table de
couleurs, invisibles à toute mesure logicielle. Symptôme : l'écran « respire » et aucun
réglage ne tient.

macOS a exactement le même piège, sous deux autres noms :

- **« Régler automatiquement la luminosité »** — le capteur de lumière ambiante pousse et
  baisse le rétroéclairage tout seul. Il se bat directement avec le premier étage, qui
  demande au même rétroéclairage de monter au maximum au-dessus de 100 %.
- **True Tone** — la température de la dalle est corrigée d'après la lumière de la pièce.
  Il se bat avec le réglage de température.

`AutoBrightness.swift` les détecte par `DisplayServicesAmbientLightCompensationEnabled`,
l'explique, et propose de les couper — ce que Windows ne permettait qu'au prix d'une
écriture dans le registre et d'un redémarrage.

### Deux concurrents que Windows n'avait pas

`ConflictDetector` surveille les applications qui écrivent dans la même table — f.lux,
Lunar, Iris, Gammy, MonitorControl. Sur macOS, il surveille en plus **deux fonctions du
système** :

- **Night Shift**, qui écrit exactement la même table de couleurs ;
- **les filtres de couleur d'accessibilité**, qui posent leur propre matrice par-dessus la
  nôtre.

Les ignorer aurait laissé l'utilisateur devant un écran trop chaud ou trop filtré sans
explication. L'application propose de les désactiver, et sait le faire.

---

## Ce qui ne change pas du tout

### Le fichier de configuration

Format identique, clef par clef, y compris `startWithWindows` — conservé sous ce nom pour
qu'un fichier venu d'un PC garde ce réglage. Les codes de touche des raccourcis sont
toujours ceux de Windows, traduits vers les codes Carbon au moment de poser le raccourci.

Une configuration exportée depuis un PC s'importe ici telle quelle, et inversement.

### Tout le calcul

`ColorTemp`, `GammaEngine`, `ColorMatrixEffect`, `Vision`, `VisionExam`, `SolarClock`,
`Scheduler` sont des portages ligne à ligne. Les mêmes constantes, les mêmes matrices, les
mêmes seuils. C'est ce qui permet aux deux versions de rendre exactement le même écran pour
un même fichier de réglages.

Une seule correction de fond a été faite au passage, et elle est mesurée :

> **6500 K est maintenant exactement neutre.** Les constantes de normalisation publiées sont
> arrondies à quatre décimales ; avec elles, 6500 K rendait 0,99996 sur le bleu au lieu de 1.
> Quatre centièmes de millième ne se voient pas à l'œil, mais ils se voient dans la table —
> deux ou trois niveaux d'écart sur 65 535 — et ils rendaient fausse la seule promesse que
> cette classe ait à tenir. La référence est désormais calculée par la formule elle-même.

### Les valeurs de l'interface

Les jetons du thème sont repris à l'octet près : mêmes couleurs, mêmes espacements, mêmes
rapports de contraste. Seule la police change — celle du système plutôt que Segoe UI, parce
que demander autre chose sur un Mac donne une application qui ne ressemble à rien de ce qui
l'entoure.
