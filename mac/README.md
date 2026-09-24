<div align="center">

<img src="Sources/OpusScreen/Resources/logo.png" alt="OpusScreen" width="300">

# 👁️ OpusScreen pour macOS

**Luminosité 5 % → 150 %, température de couleur, daltonisme et basse vision, pour Mac.**

Portage intégral de [OpusScreen](https://github.com/antoinebonpro/OpusScreen), écrit pour
Windows. Toutes les fonctions sont là — les quatre étages du moteur, les onze pages, le test
de vision guidé, les quinze raccourcis — reconstruites sur les API de macOS plutôt que
traduites mot à mot.

</div>

```
5 %                    100 %                    150 %
 |──────────────────────|────────────────────────|
 └── voile logiciel     └── état normal          └── rétroéclairage physique
     (technique             (rien n'est modifié)      + courbe gamma + gain
      PangoBright)                                    (territoire inédit)
```

---

## 🎯 Pourquoi une version Mac

macOS ne descend pas sous la luminosité minimale de la dalle, ne monte jamais au-dessus de
100 %, et ses filtres de couleur d'accessibilité n'offrent que cinq réglages figés sans
gravité réglable. Night Shift fait la température, et rien d'autre. Aucun de ces outils ne
se cumule avec le Zoom.

OpusScreen réunit les quatre techniques, les rend réglables écran par écran, et y ajoute ce
qui manque partout : une correction du daltonisme **qui se vérifie**.

## ⬇️ Installer

**[OpusScreen-1.0.0.dmg — version 1.0.0](https://github.com/antoinebonpro/OpusScreen/releases/download/mac-v1.0.0/OpusScreen-1.0.0.dmg)**
· [notes de version](https://github.com/antoinebonpro/OpusScreen/releases/tag/mac-v1.0.0)

Ouvrez l'image, glissez **OpusScreen** dans *Applications*, ouvrez-le. macOS 13 (Ventura) ou
plus récent, Apple Silicon comme Intel.

## 🔨 Construire et lancer

Aucune dépendance à installer, **aucun Xcode** : les outils en ligne de commande d'Apple
suffisent.

```bash
./build.sh              # construit OpusScreen.app
open OpusScreen.app     # lance (icône dans la barre des menus)

./build.sh run          # les deux d'un coup

./run-tests.sh          # 135 tests de calcul, en mode à blanc
./run-tests.sh all      # + 30 vérifications sur le matériel réel
                        # + 20 de bout en bout sur l'application livrée

tools/make-dmg.sh       # l'image disque telle qu'elle est publiée
```

> 💿 **L'image disque se refabrique d'une commande**, fond de fenêtre compris : celui-ci est
> **tracé** par `tools/dmg-fond.swift` plutôt que dessiné dans un éditeur, pour la même
> raison que le reste de l'interface — ce qui se redessine se vérifie et se corrige. La mise
> en page des icônes passe par le Finder, que macOS demande d'autoriser une fois
> (*Réglages → Confidentialité → Automatisation*) ; sans cette autorisation le script le dit
> et produit une image sans mise en page, qui s'installe tout aussi bien.

**Prérequis** : macOS 13 ou plus récent, Apple Silicon ou Intel.
Installer les outils si besoin : `xcode-select --install`.

> 👁️ **Une fois lancée, l'application n'a pas de fenêtre permanente** : elle se range dans
> la **barre des menus**, en haut à droite. Son icône est un œil dont la pupille prend la
> couleur que votre écran rend à cet instant. Si la barre est pleine — c'est vite le cas sur
> un portable à encoche — maintenez ⌘ et faites glisser l'icône vers la gauche.

> 🔐 **Une autorisation est demandée : « Enregistrement de l'écran ».** Elle sert à la
> correction du daltonisme, à la saturation, aux filtres et à la loupe : ces fonctions
> lisent l'image affichée, la transforment et la reposent à l'écran, image par image. Rien
> n'est enregistré, rien ne sort de la machine. **La luminosité et la température
> fonctionnent sans cette autorisation** — l'application le dit et continue.

> 🛡️ **macOS affichera un avertissement au premier lancement** si vous récupérez un paquet
> tout fait : il n'est pas signé par un certificat de développeur, qui se loue quatre-vingt-dix-neuf
> euros par an. Clic droit sur l'application → *Ouvrir*, puis *Ouvrir* dans la boîte qui suit ;
> une seule fois. Si vous préférez ne pas faire confiance à un binaire, `./build.sh` compile
> le vôtre en une commande.

## ⚖️ Ce qu'il fait

| | Réglages macOS | f.lux | Lunar Pro 23 $ | **OpusScreen** |
|---|:--:|:--:|:--:|:--:|
| 🔆 Luminosité logicielle | — | — | oui | **5-150 %** |
| 🚀 Au-delà de 100 % | — | — | payant | **oui** |
| 💡 Rétroéclairage physique (DDC/CI) | interne seulement | — | oui | **oui** |
| 🌡️ Température de couleur | Night Shift | oui | — | **oui** |
| 🌅 Suivi solaire | oui | oui | oui | **oui, hors ligne** |
| 🎬 Adaptation au contenu | — | — | — | **oui** |
| 🗂️ Profils par application | — | — | payant | **oui** |
| 🖥️ Réglages par écran | luminosité | — | oui | **les quatre étages** |
| ⏰ Pauses 20-20-20 | — | — | — | **oui** |
| ⌨️ Ligne de commande | — | — | payant | **oui** |
| 💰 Prix | — | gratuit | 23 $ | **gratuit** |

Et sur le terrain de l'accessibilité :

| | Réglages macOS | f.lux | Lunar Pro | **OpusScreen** |
|---|:--:|:--:|:--:|:--:|
| 🎨 Filtres daltonisme | 3 types figés | — | — | **3 types** |
| 📊 Gravité réglable (anomalies) | intensité globale | — | — | **0 à 100 %** |
| 🔬 Simulation pour concepteurs | — | — | — | **oui** |
| ✅ Vérification chiffrée du réglage | — | — | — | **oui** |
| 🧪 Test de vision guidé | — | — | — | **oui** |
| 🏷️ Identificateur de couleur | — | — | — | **oui** |
| 🔍 Loupe **cumulée avec les filtres** | — | — | — | **oui** |
| 🎯 Anneau de repérage du pointeur | — | — | — | **oui** |
| 🌗 Inversion à teintes conservées | inversion simple | — | — | **oui** |
| 👀 Rappel de clignement | — | — | — | **oui** |
| 🔊 Compatible VoiceOver | — | — | — | **oui** |

Plus de **80 réglages** répartis sur 11 pages, 20 modes livrés, 15 raccourcis globaux
reconfigurables.

## 🖱️ Utilisation

- **Clic** sur l'icône : le menu — modes, luminosité, écrans, aides à la vision
- **⌥ clic** : ouvre directement les réglages
- **Molette au-dessus de l'icône** : luminosité

### ⌨️ Raccourcis

Les combinaisons sont celles de la version Windows : `Ctrl` y devient ⌃ et `Alt` devient ⌥.
Elles restent donc identiques d'une machine à l'autre, et le fichier de configuration les
transporte telles quelles.

| Raccourci | Effet |
|---|---|
| `⌃⌥ ↑ / ↓` | luminosité ± 5 % |
| `⌃⌥ ← / →` | température ± 200 K |
| `⌃⌥P` | suspendre / reprendre |
| `⌃⌥M` | mode suivant |
| `⌃⌥D` | 🎨 correction daltonisme |
| `⌃⌥C` | 🏷️ identifier la couleur sous le pointeur |
| `⌃⌥⇧C` | 📋 copier cette couleur |
| `⌃⌥Z` | 🔍 loupe plein écran |
| `⌃⌥H` | 🎯 anneau autour du pointeur |
| **`⌃⌥⇧R`** | 🆘 **secours : écran normal en toutes circonstances** |

### 💻 Ligne de commande

```bash
open -a OpusScreen --args --brightness 130
open -a OpusScreen --args --mode "Nuit profonde"
open -a OpusScreen --args --vision vert      # aucune | rouge | vert | bleu
open -a OpusScreen --args --severity 70      # gravité de la déficience, 0 à 100
open -a OpusScreen --args --magnifier 2.5    # loupe, 1 à 8 (1 = éteinte)
open -a OpusScreen --args --beacon on
open -a OpusScreen --args --reset

# Le binaire interne accepte les mêmes options, sans passer par « open » :
/Applications/OpusScreen.app/Contents/MacOS/OpusScreen --brightness 130 --temp 3400
```

---

## ♿ Accessibilité

C'est la moitié de ce que fait cette application, et la moitié que les autres ne font pas.

### 🎨 Daltonisme

Environ **8 % des hommes** et 0,5 % des femmes perçoivent mal une partie du spectre. macOS
propose bien trois filtres, mais sans gravité réglable et sans moyen de vérifier qu'ils
servent à quelque chose.

- **Trois déficiences** — rouge (protanopie), vert (deutéranopie, la plus répandue), bleu
  (tritanopie).
- **Une gravité de 0 à 100 %.** La dichromatie complète est le cas rare ; le cas fréquent
  est l'**anomalie**. Un filtre calibré sur la dichromatie sur-corrige la majorité des
  personnes concernées : l'écran devient criard sans être plus lisible.
- **Une intensité de correction** séparée, de 0 à 150 %.
- **Un mode simulation**, pour qui conçoit une interface et veut vérifier qu'elle reste
  lisible.
- **Un test guidé de deux minutes** qui trouve le type par des planches, puis mesure la
  gravité par un escalier adaptatif — la méthode des seuils en psychophysique.

**Le comparateur** est le cœur de la page. Il montre des paires de couleurs que votre
réglage rend indistinguables, d'abord telles que vous les percevez, puis telles que vous les
percevriez après correction, avec l'écart chiffré en ΔE :

```
Couleurs confondues     Aujourd'hui              Avec la correction
gris, deux nuances      ▉▉  1,4  identiques      ▉▉  3,9  distinctes
gris, deux nuances      ▉▉  2,1  identiques      ▉▉  4,5  distinctes
gris / mauve            ▉▉  1,7  identiques      ▉▉  4,6  distinctes
```

Ces paires ne sont pas choisies à la main. Elles sont **calculées** à partir de la matrice
de simulation, puis calibrées par dichotomie pour rester juste sous le seuil de perception.

> Un curseur sans vérification n'aide personne : sans point de comparaison, il est
> impossible de savoir si l'on vient d'améliorer ou d'aggraver la situation.

### 🏷️ Identifier une couleur

`⌃⌥C` fait suivre le pointeur d'une étiquette qui **nomme la couleur en français**, avec une
grille de pixels agrandie, la valeur hexadécimale et les composantes. `⌃⌥⇧C` la copie.

La lecture se fait **avant** la table de couleurs et avant les filtres : les réglages en
cours ne faussent donc jamais la réponse.

### 🔍 Basse vision

- **Loupe plein écran**, de 1× à 8×, qui suit le pointeur. Elle partage sa passe de calcul
  avec la matrice de couleur : l'agrandissement et la correction du daltonisme **se
  cumulent**. Ni le Zoom de macOS ni ses filtres de couleur ne savent le faire — le premier
  ignore les réglages de couleur, les seconds ignorent le Zoom.
- **Anneau de repérage** autour du curseur, taille, couleur et opacité réglables. Il est
  percé en son centre : rien ne masque la cible, aucun clic n'est intercepté, et il
  n'apparaît ni dans les captures ni dans les partages d'écran.
- **Inversion à teintes conservées** : les documents passent au sombre sans que les photos
  virent au négatif.
- **Modes livrés** : *Basse vision*, *Achromatopsie*, *Photophobie*.
- **Teintes de lecture** — bleue, verte, ambre, saumon, grise.

### 👀 Confort et fatigue oculaire

- **Pauses 20-20-20** : toutes les 20 minutes, regarder à 6 mètres pendant 20 secondes.
- **Rappel de clignement.** Devant un écran, la fréquence de clignement chute de plus de
  moitié : c'est la première cause de sécheresse oculaire au travail. Le bandeau dure trois
  secondes et n'attend aucune réponse.
- **Réduction du bleu** par la température, la balance des canaux, ou les deux.
- **Volume de sortie** — avec une note honnête : macOS n'a pas de mixeur par application, il
  n'y a donc rien à « récupérer » comme sur Windows.

### 🔊 VoiceOver

Les curseurs, interrupteurs, listes et onglets sont dessinés à la main — ils seraient donc
**invisibles** pour VoiceOver, qui ne verrait que des rectangles sans nom, sans rôle et sans
valeur. Ils déclarent tous ce qu'ils représentent, et l'ensemble se parcourt au clavier.

> Une application dont la raison d'être est l'accessibilité ne pouvait pas rester elle-même
> inaccessible.

---

## 🖥️ Plusieurs écrans

Luminosité, température, voile **et filtres** se règlent écran par écran : profil
indépendant, simple décalage, exclusion, ou extinction complète.

C'est le seul point où le portage **gagne** sur l'original. Sur Windows,
`MagSetFullscreenColorEffect` n'exposait qu'un effet pour tout le bureau : la saturation et
les filtres ne pouvaient pas différer d'un écran à l'autre, et la documentation le signalait
comme une limite de l'API. Ici la matrice est recalculée écran par écran. Le réglage
« écran de référence » demeure, mais il devient un **choix** — une correction daltonienne
qui change d'un écran à l'autre perturbe plus qu'elle n'aide.

---

## ⚠️ La règle de sécurité

Sur Windows, une table de couleurs modifiée **survit à la mort du processus qui l'a posée** :
si l'application disparaît alors que l'écran est à 5 %, l'écran reste à 5 %.

**macOS ne se comporte pas ainsi** — et c'est mesuré, pas supposé : le serveur de fenêtres
rend la table d'origine dès que le processus disparaît, `SIGKILL` compris. Le test de bout
en bout le constate à chaque exécution.

Ce qui reste, et qui justifie les cinq protections : un processus **figé** détient toujours
sa table, son voile et son image filtrée, et personne ne les lui reprendra. Voir
[docs/SECURITE.md](docs/SECURITE.md).

> 🆘 **À retenir : `⌃⌥⇧R` rétablit un écran normal en toutes circonstances.**
> Si l'interface ne répond plus dans les trois secondes, l'application se termine d'elle-même
> après avoir rendu l'écran : un écran rendu vaut mieux qu'une application qui tient.

---

## 📚 Documentation

| Document | Contenu |
|---|---|
| 🏗️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Les quatre étages sur macOS, organisation du code |
| 🔀 [docs/PORTAGE.md](docs/PORTAGE.md) | Ce qui change par rapport à Windows, et pourquoi |
| 🛡️ [docs/SECURITE.md](docs/SECURITE.md) | Les cinq protections anti-écran-noir |
| 🧪 [docs/PROTOCOLES-TESTS.md](docs/PROTOCOLES-TESTS.md) | Ce qui est vérifié, et comment le lancer |
| 🔧 [docs/DEPANNAGE.md](docs/DEPANNAGE.md) | Symptômes courants, dont le piège de la luminosité automatique |
| 📓 [CHANGELOG.md](CHANGELOG.md) | Historique des versions |

## 🔄 Compatibilité des réglages

Le fichier de configuration est **rigoureusement celui de la version Windows** :
`~/Library/Application Support/OpusScreen/settings.ini`. Une configuration exportée depuis un
PC s'importe ici telle quelle, et inversement. Quelqu'un qui travaille sur les deux systèmes
ne règle ses quatre-vingts curseurs qu'une fois.

## 🪤 Un piège à connaître

Sur Windows, c'était le DPST des pilotes Intel. Sur macOS, c'est **« Régler automatiquement
la luminosité »** — et **True Tone** pour la température. Les deux agissent **en aval** de
la table de couleurs : aucune application ne peut les compenser, et ils sont invisibles aux
mesures logicielles. Symptôme identique : l'écran « respire » et aucun réglage ne tient.

OpusScreen les détecte, l'explique, et propose de les couper depuis la page *Avancé* — voir
[docs/DEPANNAGE.md](docs/DEPANNAGE.md).

## 📄 Licence et attributions

Code sous licence **GNU AGPL v3** — voir [LICENSE](../LICENSE).

Ce projet **ne contient aucun code** de PangoBright ni de f.lux. Les techniques employées
sont des API publiques et documentées de macOS, à trois exceptions signalées et chargées à
l'exécution : `DisplayServices` (rétroéclairage de la dalle interne, luminosité
automatique), `IOAVService` (DDC/CI sur Apple Silicon) et `CBBlueLightClient` (détection de
Night Shift). Chacune se désactive proprement si elle disparaît d'une version de macOS.

- **PangoBright** — © Pangolin Laser Systems Inc.
- **f.lux** — © f.lux Software LLC. Les températures de ses ambiances sont reprises de son
  fichier de configuration public.

Les matrices de simulation des déficiences chromatiques sont les matrices classiques de la
littérature (Viénot, Brettel), employées ici comme les approximations qu'elles sont.
