# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

---

## [1.0.3] — 2026-09-29

### Ajouté — `--version`

Un outil en ligne de commande qui ne sait pas dire son propre numéro est un outil qu'on ne
peut pas dépanner. Il le dit maintenant, et s'arrête là.

### Corrigé — une option mal orthographiée était ignorée en silence

`--brightnes 40` lançait l'application et ne faisait rien d'autre : l'ordre semblait ignoré
sans raison, et la ligne de commande passait pour cassée alors qu'elle n'avait rien reçu. Elle
le signale désormais, **et continue quand même** — refuser de démarrer serait pire, une copie
lancée à l'ouverture de session pouvant recevoir des arguments qu'elle ne connaît pas et qui
ne sont la faute de personne. Les arguments que macOS ajoute lui-même (`-psn_…`,
`-NSDocumentRevisionsDebugMode`) ne déclenchent rien : s'en plaindre reviendrait à crier sur
ce qu'on a soi-même demandé.

### Corrigé — une sonde de développement qui disait faux

`--update-check` annonçait « installée : 1.0.0 » quel que soit le numéro réel, puis « une
version plus récente est proposée » — ce qui était faux. Le binaire de test n'est pas un
paquet d'application : la lecture de la version retombait sur sa valeur de repli. Elle est
maintenant lue dans le paquet construit, ou la sonde dit qu'elle ne peut pas comparer. Une
sonde qui dit faux est pire qu'une sonde absente : on la croit.

---

## [1.0.2] — 2026-09-29

### Corrigé — la fenêtre du disque donnait une instruction périmée

Le fond disait « clic droit sur l'application → *Ouvrir* ». **Apple a retiré ce raccourci à
partir de macOS 15** : l'instruction envoyait chercher un bouton qui n'existe plus, exactement
au moment où l'on en a besoin — devant une boîte qui parle de logiciel malveillant, et loin du
site où se trouve l'explication. Une aide fausse à cet endroit-là est pire qu'une aide absente.

La fenêtre porte maintenant le bon geste, sous la flèche : *Réglages Système → Confidentialité
et sécurité → « Ouvrir quand même »*, avec le cas de macOS 13 et 14 en dessous. La signature
décorative qui occupait ce bas de fenêtre a été retirée pour lui faire place : entre dire son
propre nom une fois de plus et dire à quelqu'un comment ouvrir ce qu'il vient de télécharger,
le choix est vite fait.

### Le site montre les étapes au moment du clic

L'explication était sur la page ; l'obstacle, lui, arrive deux minutes plus tard dans le
Finder, quand la page a été quittée depuis longtemps. Une explication qu'il faut avoir lue par
avance n'aide personne.

Cliquer *Télécharger pour macOS* fait maintenant apparaître les trois étapes à l'écran, et les
y laisse. La commande d'installation sans avertissement est, elle, montrée en clair sous les
boutons plutôt que repliée dans une note.

---

## [1.0.1] — 2026-09-25

### Corrigé — la 1.0.0 ne démarrait pas sur les Mac Intel

Le paquet publié ne contenait **que** l'architecture Apple Silicon. Sur un Mac Intel il ne se
lançait pas du tout — pas lentement : pas du tout. La documentation promettait pourtant
« Apple Silicon comme Intel ».

La cause tient en une phrase : `swift build` ne produit que l'architecture de la machine qui
compile, et **le défaut est invisible depuis cette machine-là** — le paquet s'y lance
parfaitement. Rien dans la chaîne de vérification ne regardait ce que l'on venait de
fabriquer ; les 165 tests s'exécutaient sur la seule architecture présente et passaient tous.

Le paquet est désormais universel. `swift build --arch arm64 --arch x86_64` aurait suffi,
mais réclame `xcbuild`, qui n'arrive qu'avec Xcode : on compile donc deux fois, chacune dans
son dossier de travail, et `lipo` réunit les deux exécutables.

**Et cela se vérifie maintenant, au lieu de se supposer** : `build.sh` échoue si l'une des
deux architectures manque, `tools/make-dmg.sh` refuse de fabriquer une image à partir d'un
paquet qui ne les a pas toutes les deux, et `install.sh` refuse d'installer un paquet qui ne
contient pas l'architecture de la machine où il tourne.

### Ajouté — installer sans l'avertissement de macOS

```bash
curl -fsSL https://antoinebonpro.github.io/OpusScreen/install.sh | bash
```

Télécharge, **vérifie l'empreinte SHA-256**, installe dans *Applications* et lance. Aucun
avertissement : la marque de quarantaine qui déclenche « Apple n'a pas pu confirmer… » est
posée par les **navigateurs**, et `curl` ne la pose pas.

Dit franchement : cela **contourne** la vérification d'Apple, cela ne la satisfait pas. Ce qui
la remplace est vérifiable à l'œil — l'empreinte attendue est écrite en clair dans le script,
lisible avant d'être exécuté, et l'installation est refusée si le fichier reçu n'y correspond
pas à l'octet près. La seule façon de faire disparaître l'avertissement sans rien contourner
reste la notarisation, qui demande un compte de développeur Apple payant.

### Ajouté — un contrôle de ce qui est en ligne

`tools/verifier-publication.sh` compare ce qui est **publié** à ce qui est **écrit** :
l'empreinte épinglée dans `install.sh` contre celle du fichier réellement servi, le script
servi par le site contre celui du dépôt, les liens des deux pages contre la version en cours,
et que « dernière version » reste celle de Windows. Une publication tient par des valeurs
recopiées à plusieurs endroits ; ce qui casse quand elles divergent, c'est la confiance.

---

## [1.0.0] — 2026-09-24

Première version pour macOS. Portage intégral d'OpusScreen 3.4.0, écrit pour Windows.

### Ajouté

Toutes les fonctions de la version Windows, reconstruites sur les API de macOS :

- **Les quatre étages du moteur** — rétroéclairage physique, table de couleurs, voile
  logiciel, matrice de couleur. Luminosité de 5 à 150 %, avec la même répartition et la même
  calibration : rien n'est écrêté jusqu'à 135 %.
- **Rétroéclairage physique** par `DisplayServices` sur la dalle interne, et par DDC/CI sur
  les écrans externes — `IOAVService` sur Apple Silicon, `IOI2CSendRequest` sur Intel.
- **Onze pages de réglages**, plus de quatre-vingts réglages, vingt modes livrés.
- **Daltonisme** : trois déficiences, gravité de 0 à 100 %, intensité séparée, mode
  simulation, comparateur de couleurs confondues chiffré en ΔE, et test guidé de deux
  minutes.
- **Basse vision** : loupe plein écran cumulée avec les filtres, anneau de repérage du
  pointeur, identificateur de couleur, inversion à teintes conservées, teintes de lecture.
- **Confort** : pauses 20-20-20, rappels de clignement, volume de sortie.
- **Automatismes** : suivi solaire hors ligne (NOAA), horaires fixes, adaptation au contenu
  affiché, règles par application, suspension en plein écran.
- **Quinze raccourcis globaux** reconfigurables, et le raccourci de secours `⌃⌥⇧R`.
- **Ligne de commande** complète, avec transmission à l'instance en cours.
- **Les cinq protections anti-écran-noir**, toutes vérifiées par test.
- **VoiceOver** : chaque contrôle dessiné à la main déclare son rôle, son nom et sa valeur.
- **Une image disque pour s'installer** — on l'ouvre, on glisse l'application dans
  *Applications*, la fenêtre montre le geste. L'archive `.zip` reste publiée à côté : c'est
  elle que l'application va chercher quand elle se met à jour toute seule. Image et fond de
  fenêtre se refabriquent d'une commande, sans outil tiers ni Xcode.

### Meilleur que sur Windows

- **La matrice de couleur est réglable écran par écran.** Sur Windows,
  `MagSetFullscreenColorEffect` n'exposait qu'un effet pour tout le bureau — une limite de
  l'API que la documentation d'origine signalait comme telle. Le réglage « écran de
  référence » demeure, mais comme un choix.
- **La table de couleurs n'est plus bridée.** Le déblocage de `GdiIcmGammaRange`, qui
  demandait les droits administrateur et une réouverture de session, n'a plus d'objet.
- **Le piège de la luminosité automatique se corrige depuis l'application.** L'équivalent
  Windows — le DPST des pilotes Intel — demandait une écriture dans le registre et un
  redémarrage.

### Corrigé par rapport à la version Windows

- **6500 K est maintenant exactement neutre.** Les constantes de normalisation publiées sont
  arrondies à quatre décimales ; avec elles, 6500 K rendait 0,99996 sur le bleu au lieu de 1.
  Quatre centièmes de millième ne se voient pas à l'œil, mais ils se voient dans la table —
  deux ou trois niveaux d'écart sur 65 535 — et ils rendaient fausse la seule promesse que
  cette classe ait à tenir. La référence est désormais calculée par la formule elle-même.

### Moindre, et dit comme tel

- **L'étage « matrice de couleur » demande l'autorisation « Enregistrement de l'écran ».**
  Sans elle, la saturation, les filtres et la loupe sont indisponibles et le disent ; la
  luminosité et la température continuent de fonctionner.
- **Le pointeur n'est pas recoloré par la matrice** : macOS le dessine au-dessus de toutes
  les fenêtres. Sous la loupe, un pointeur agrandi est ajouté à l'image.
- **Le fil de secours demande l'autorisation d'accessibilité** pour répondre même quand
  l'interface est bloquée. Sans elle, un repli couvre tous les autres cas.
- **Il n'y a pas de mixeur par application sur macOS** : la fonction « tout remettre au
  maximum » se réduit au volume de sortie, et la page l'explique plutôt que d'inventer.

### Compatibilité

- **Le fichier de configuration est celui de la version Windows**, clef par clef. Une
  configuration exportée depuis un PC s'importe ici telle quelle, et inversement.
- Les codes de touche des raccourcis restent ceux de Windows dans le fichier, traduits vers
  les codes Carbon au moment de poser le raccourci.
- **Les deux versions se mettent à jour séparément**, tout en vivant dans le même dépôt. Les
  publications macOS portent l'étiquette `mac-v…`, celles de Windows `v…`, et chacune ne
  regarde que les siennes : l'application cherche la publication la plus récente qui porte un
  paquet macOS, au lieu de demander « la dernière » — qui serait celle de Windows, où elle ne
  trouverait rien et annoncerait chaque jour une erreur de réseau qui n'en est pas une.

### Vérification

Trois niveaux, parce qu'un moteur juste et une application qui fonctionne ne sont pas la
même affirmation.

- **Calcul** — sept suites, 135 tests, 5 622 assertions, en mode à blanc : elles ne touchent
  ni à l'écran, ni au son, ni à la configuration de la machine qui les exécute.
- **Réel** — 30 vérifications sur le matériel : la table de couleurs posée puis relue entrée
  par entrée, le nuanceur Metal qui compile, la passe de filtrage qui se monte et se
  démonte, le voile aux dimensions de l'écran, le sondage DDC/CI qui répond.
- **Bout en bout** — 20 vérifications sur le paquet livré, lancé et piloté comme
  l'utilisateur le fera.

Le harnais ne dépend pas de Xcode : l'application se construit et se vérifie avec les seuls
outils en ligne de commande d'Apple. Les onze pages se dessinent hors écran dans des PNG,
pour être regardées sans autorisation de capture.

### Trouvé par les tests, et corrigé

- **Une alerte écartée autrement que par un clic était enregistrée comme une décision** — et
  le dernier bouton est justement celui qui dit « ne plus jamais demander ». `Alerts.choose`
  rend désormais -1 quand aucun bouton n'a répondu.
- **Une boîte de dialogue au premier lancement bloquait toute l'application derrière elle.**
  Une copie lancée à l'ouverture de session, ou pilotée par la ligne de commande, restait
  muette sans que rien ne le dise. Plus aucune modale au démarrage : une bannière, et un
  bouton dans la page *Découvrir*.
- **Un paragraphe de quatre lignes en perdait une.** La mesure du texte et son dessin ne
  comptaient pas la même interligne — une fraction de point par ligne, assez pour faire
  disparaître la dernière.
- **6500 K n'était pas exactement neutre** (voir plus haut).

### Une croyance corrigée

La documentation affirmait, par report depuis Windows, qu'une table de couleurs survit à la
mort du processus qui l'a posée. **C'est faux sur macOS**, et le test le mesure : le serveur
de fenêtres rend la table d'origine dès que le processus disparaît, `SIGKILL` compris. Les
cinq protections restent justifiées pour le cas du processus **figé**, qui détient toujours
sa table et ses fenêtres — et la documentation dit maintenant ce qui a été constaté plutôt
que ce qui était supposé.
