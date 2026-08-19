# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

---

## [Non publie]

### Ajoute

- **Section « Son » dans la page Confort** : volume general, et un bouton qui remet au
  maximum le volume general ET celui de chaque application du mixeur de Windows.

  Le libelle dit « Tout remettre au maximum », pas « amplifier », parce que c'est la
  seule formulation exacte. **Aller au-dela de 100 % est impossible depuis une
  application ordinaire** : la sortie audio declare sa plage en decibels et son maximum
  vaut 0 dB - mesure sur le materiel de test, plage -65,25 a 0,00 dB. Demander davantage
  ne donne pas une valeur ecretee, l'appel echoue.

  C'est la meme limite que le voile de PangoBright sur la luminosite, et pour la meme
  raison : un attenuateur retire du signal, il n'en ajoute pas. La luminosite a pu
  depasser 100 % parce qu'un AUTRE etage existait - la table de couleurs de la carte
  graphique, qui multiplie. Le son n'a pas d'equivalent accessible : amplifier
  demanderait de s'inserer dans le flux audio, donc un pilote a installer, ce que cette
  application refuse par principe.

  Ce qui reste, et qui n'est pas rien : chaque application memorise son propre volume
  dans le mixeur de Windows. Un curseur baisse une fois par megarde le reste pour
  toujours, et le mixeur est un panneau que peu de gens savent ou trouver. Un son trop
  faible vient de la bien plus souvent que du volume general.

  Quand tout est deja au maximum, le compte rendu le dit franchement plutot que
  d'annoncer un succes : laisser croire qu'une action a eu lieu enverrait chercher un
  probleme la ou il n'y en a pas.

---

## [3.0.0] — 2026-08-19

L'accessibilité cesse d'être une case cochée dans un tableau comparatif.

La version 2.2 affichait bien « filtres daltonisme : oui ». Trois filtres existaient,
figés sur une déficience complète, sans moyen de vérifier qu'ils servaient à quelque
chose — et l'aperçu de la page Couleur ne les montrait même pas. Cette version les
reprend depuis le début, et ajoute ce dont une personne malvoyante a réellement besoin.

### Ajouté

**Vision des couleurs**

- **Une page « Vision » entière**, distincte de la page Couleur. Régler une saturation
  est un goût ; régler une correction de daltonisme est un besoin.
- **Curseur de gravité, de 0 à 100 %.** La dichromatie — un type de cône totalement
  absent — est le cas rare. Le cas fréquent est l'*anomalie* : le cône existe mais
  réagit à côté, et la confusion n'est que partielle. Les trois filtres d'avant étaient
  calibrés sur la dichromatie seule et sur-corrigeaient donc la majorité des personnes
  concernées, rendant l'écran criard sans le rendre plus lisible.
- **Curseur d'intensité de la correction**, de 0 à 150 %.
- **Mode simulation**, en plus du mode correction : montre ce que perçoit la vision
  choisie. Ne sert pas la personne daltonienne, mais qui conçoit une interface, un
  graphique ou un support de cours et veut vérifier qu'il reste lisible.
- **Comparateur de couleurs confondues.** Des paires que la déficience réglée rend
  indistinguables, montrées telles qu'elles sont perçues aujourd'hui puis telles
  qu'elles le seraient après correction, avec l'écart chiffré en ΔE. Un curseur sans
  vérification n'aide personne : sans point de comparaison, impossible de savoir si l'on
  vient d'améliorer ou d'aggraver la situation.
- **Identificateur de couleur** (`Ctrl + Alt + C`) : une étiquette suit le pointeur et
  nomme en français la couleur survolée, avec sa grille de pixels agrandie, sa valeur
  hexadécimale et ses composantes. `Ctrl + Alt + Maj + C` la copie. C'est l'outil que
  réclament en premier les personnes daltoniennes, et qu'aucun concurrent ne propose.
  La lecture se fait **avant** la table de couleurs et les filtres : les réglages en
  cours ne faussent jamais la réponse.
- **Filtre « inversion à teintes conservées »** : les documents et les pages web passent
  au sombre sans que les photos virent au négatif. L'inversion classique retourne aussi
  les teintes — le rouge devient cyan — ce qui la rend inutilisable dès qu'une image est
  à l'écran.
- **Quatre modes livrés** pour le daltonisme rouge, vert et bleu, plus l'achromatopsie
  (absence totale de vision des couleurs, presque toujours accompagnée d'une photophobie
  sévère : couleur retirée, lumière baissée, contraste relevé).

**Basse vision**

- **Loupe plein écran** (`Ctrl + Alt + Z`), de 1× à 8×, qui suit le pointeur. Passe par
  la même DLL que la matrice de couleur : l'agrandissement et la correction du
  daltonisme se cumulent, ce que la loupe de Windows ne sait pas faire. Repli automatique
  sur la loupe de Windows si le système refuse.
- **Anneau de repérage autour du pointeur** (`Ctrl + Alt + H`), taille, couleur et
  opacité réglables. Perdre le pointeur de vue est le premier obstacle rapporté en basse
  vision, et un curseur simplement agrandi reste de la même couleur que ce qu'il survole.
  L'anneau est découpé en couronne : rien ne recouvre la cible, aucun clic n'est
  intercepté, et il n'apparaît ni dans les captures ni dans les partages d'écran.
- **Modes « Basse vision » et « Photophobie »**.
- **Teintes de lecture** — bleue, verte, ambre, saumon, grise. Posées par la balance des
  canaux et non par le voile : celui-ci ne sert que sous 35 % de luminosité, une teinte
  posée par lui disparaîtrait donc dès qu'on lit à un niveau normal.
- **Rappel de clignement.** Devant un écran, la fréquence de clignement chute de plus de
  moitié : c'est la première cause de sécheresse oculaire au travail. Le bandeau dure
  trois secondes, ne prend pas le focus et n'attend aucune réponse.

**Lecteurs d'écran**

- Les curseurs, interrupteurs et onglets sont entièrement **dessinés à la main** — donc
  invisibles pour un lecteur d'écran, qui ne voyait que des rectangles sans nom, sans
  rôle et sans valeur. Ils déclarent désormais ce qu'ils représentent. Une application
  dont la raison d'être est l'accessibilité ne pouvait pas rester elle-même inaccessible.
- Boutons d'accès direct aux réglages d'accessibilité de Windows (taille du texte,
  curseur, contraste élevé) : ce qui relève de Windows y reste, où il vaut pour toutes
  les applications à la fois.

**Divers**

- Cinq nouveaux raccourcis globaux, ajoutés aux configurations existantes sans écraser
  les combinaisons déjà attribuées.
- Sous-menu **Vision** dans la zone de notification : la loupe et l'identificateur de
  couleur servent justement dans les moments où l'on n'arrive plus à lire l'écran, et
  demander d'ouvrir un panneau de réglages pour y accéder n'aurait aucun sens.
- Options en ligne de commande `--vision`, `--severity`, `--magnifier`, `--beacon`
  et `--colors`.
- Une sixième suite de tests, `VisionTest`.

### Corrigé

- **Deux écrans du même modèle ne faisaient qu'un.** L'identifiant matériel était tiré
  du seul *modèle* de l'écran : deux moniteurs identiques — la configuration à deux
  écrans la plus répandue qui soit — recevaient donc exactement le même. Ils partageaient
  une unique fiche de réglages : le voile de l'un se posait sur l'autre, le profil
  indépendant du second écrasait celui du premier, et « éteindre cet écran » en éteignait
  deux. L'ambiguïté est désormais levée par la sortie graphique, et **uniquement en cas
  de collision** — un écran seul de son modèle garde l'identifiant qu'il avait, et ses
  réglages avec.

- **Le réglage du rétroéclairage physique d'un écran s'appliquait à tous.** La consigne
  était globale alors qu'elle était émise depuis une boucle *par écran* : sur deux
  écrans, le dernier traité imposait sa luminosité matérielle aux autres, et un décalage
  propre à un écran s'appliquait en réalité à son voisin. Les consignes sont désormais
  nominatives. Au passage, le réglage WMI est réservé à la dalle interne d'un portable —
  la seule que cette interface sache piloter — au lieu d'être tenté pour le compte d'un
  écran externe.

- **L'aperçu de la page Couleur ignorait purement et simplement les filtres pour
  daltoniens.** Il recopiait à la main la saturation, l'inversion et le sépia, et ne
  traitait rien d'autre : l'image restait inchangée alors que l'écran, lui, changeait —
  exactement pour les réglages que l'on a le plus besoin de comparer avant de les
  appliquer. L'aperçu passe maintenant par la matrice du moteur, sans réécriture.

- **Les avertissements « écrêtage » et « Windows rabote les rampes » disparaissaient une
  fois sur deux avec deux écrans.** Ils décrivent une configuration, pas un écran, mais
  étaient réécrits à chaque écran parcouru : le dernier effaçait le diagnostic du
  premier. Ils sont maintenant cumulés sur la passe entière, et remis à zéro avant.

- **Un écran débranché laissait derrière lui son dernier état affiché**, ce qui suffisait
  à faire croire qu'un effet restait actif alors que plus rien n'était posé.

- **Le nom des écrans venait du pilote** — « Generic PnP Monitor » la plupart du temps.
  Il vient maintenant de l'EDID, complété par la connectique (HDMI, DisplayPort, dalle
  interne), pour que l'écran désigné dans la fenêtre soit celui que l'on reconnaît
  derrière la machine. L'identifiant technique, qui n'apprenait rien à personne et
  confondait justement les écrans identiques, ne s'affiche plus.

### Modifié

- **L'icône de l'application est dérivée de `assets/logo.png`.** Sous 48 pixels, seul le
  motif central est repris : réduit en entier, un logo large devient une ligne illisible
  dans la barre des tâches. Le logo entier est par ailleurs embarqué en pleine résolution
  et affiché dans la fenêtre de réglages.

- Un **écran de référence** peut être désigné pour la saturation et les filtres.
  `MagSetFullscreenColorEffect` n'expose qu'un effet pour le bureau entier — c'est une
  contrainte de l'API, pas un choix. Plutôt que de laisser un écran arbitraire décider
  pour les autres, on le nomme, et l'interface l'explique.

- La loupe plein écran est annulée par le raccourci de secours, à la fermeture et sur
  exception, au même titre que la table de couleurs et la matrice.

### Vérification

`tests\run-tests.cmd` — six suites, `Tests executes : 6 / 6`, aucun échec.

`VisionTest` a attrapé deux défauts pendant l'écriture de cette version. Les paires de
couleurs « confondues » du comparateur étaient d'abord écrites à la main d'après le sens
commun — rouge/vert, rose/gris. Mesurées, elles se révélaient parfaitement distinctes une
fois simulées : elles différaient surtout par la **clarté**, que la déficience ne touche
pas. Le comparateur montrait donc des couleurs que la personne distingue déjà, et
concluait à l'inutilité d'une correction qui, elle, fonctionnait. Les paires sont
maintenant calculées à partir de la matrice de simulation, et l'écart calibré par
dichotomie pour rester sous le seuil de perception.

---

## [2.2.0] — 2026-08-15

La luminosité ne disparaît plus dès qu'une vidéo passe en plein écran.

### Corrigé

- **Un film en plein écran ramenait l'écran à 100 %.** Toute fenêtre couvrant un écran
  entier déclenchait la suspension de *tous* les étages, boost compris : régler 130 %
  pour un film sombre, puis le lancer, annulait le réglage — et le rétablissait à la
  sortie du plein écran, ce qui rendait la cause difficile à voir.

  Les quatre étages ne gênent pourtant pas de la même façon. Le voile est une fenêtre
  posée par-dessus l'écran, que le plein écran supporte mal ; la table de couleurs est
  appliquée par la carte graphique en sortie et le traverse sans dommage. Or c'est elle,
  avec le rétroéclairage, qui porte tout le boost — et le voile n'intervient même pas
  au-dessus de 35 % de luminosité. La suspension ne concerne donc plus que le voile.

### Modifié

- **« Suspendre en plein écran » devient « En plein écran », à trois choix** :
  *ne rien changer*, *retirer le voile seulement* (nouveau réglage par défaut),
  *suspendre tous les effets* — l'ancien comportement, conservé pour qui veut des
  couleurs strictement d'origine en jeu.

  Les configurations existantes sont reprises : la case décochée était un refus
  explicite de toute suspension et devient *ne rien changer* ; la case cochée était le
  réglage par défaut, jamais un choix visant le voile en particulier, et devient
  *retirer le voile seulement*.

- Une suspension posée pour une autre raison — pause manuelle, pause oculaire, règle
  d'application — n'est plus écrasée par le passage en plein écran, ni levée à sa sortie.

### Vérification

- `EngineTest` : au-dessus de 100 %, le plan de luminosité est identique avec et sans
  voile ; en dessous du plancher gamma, retirer le voile assombrit malgré tout autant
  que la table de couleurs le permet.
- `SafetyTest` : réglage par défaut, reprise des deux anciennes valeurs, aller-retour
  de la configuration.

---

## [2.1.0] — 2026-08-15

OpusScreen s'épingle à la barre des tâches et au menu Démarrer.

### Ajouté

**Icône d'application**
L'exécutable n'en portait aucune : épinglé, il aurait affiché l'icône générique de
Windows. L'icône est dessinée par code, taille par taille de 16 à 256 pixels — une
grande image réduite donne un 16×16 flou dans la barre des tâches. Elle est embarquée
en ressource Win32 pour le shell, et en ressource managée pour la fenêtre.

**Raccourci et épinglage**
- Raccourci déposé dans le menu Démarrer, sa cible corrigée si l'exécutable a déménagé
- *Avancé → Système → Épingler OpusScreen à la barre des tâches* prépare le raccourci et
  conduit l'utilisateur jusqu'à lui

**Liste de tâches**
Clic droit sur l'icône épinglée : réglages, suspension, pause pour les yeux, modes
Confort, Nuit profonde et Plein soleil, retour à un écran normal. Chaque entrée passe
par le pilotage en ligne de commande, qui existait déjà.

**`--show`**
Ouvre la fenêtre de réglages, que l'application tourne ou non.

### Modifié

- **LumaFlux s'appelle désormais OpusScreen.** Le nom change partout : exécutable,
  fenêtre, icône de la zone de notification, aide en ligne de commande, documentation.
  Rien n'est perdu au passage — au premier lancement, la configuration est reprise
  depuis `%LOCALAPPDATA%\LumaFlux`, l'entrée de démarrage automatique est réécrite avec
  le nouveau chemin, et le raccourci du menu Démarrer laissé par LumaFlux, dont la cible
  n'existe plus, est effacé.
- **Un second lancement n'affiche plus « OpusScreen est déjà en cours d'exécution ».**
  Une application épinglée est relancée à chaque clic sur son icône : répondre par un
  refus là où l'utilisateur attend sa fenêtre n'avait pas de sens. Le nouveau processus
  transmet la demande à l'instance en cours et s'efface.
- La fenêtre de réglages apparaît dans la barre des tâches, sous l'icône de
  l'application.

### Vérification

- Cinquième suite de tests : icône complète, raccourci relu à l'identique, liste de
  tâches acceptée par le shell.

---

## [2.0.0] — 2026-08-15

Version d'extension : l'application passe d'un réglage de luminosité et de température à
un outil complet de confort visuel, avec plus de 70 réglages.

### Ajouté

**Un quatrième étage — la matrice de couleur plein écran**
Une table de couleurs traite chaque canal indépendamment ; elle ne peut donc pas produire
de saturation, d'inversion ni de filtre pour daltoniens. `MagSetFullscreenColorEffect`
applique une matrice 5×5 au niveau du compositeur et mélange les canaux.

- Saturation réglable de 0 à 200 %
- Filtres : niveaux de gris, inversion, sépia
- **Filtres d'assistance pour daltoniens** : protanopie, deutéranopie, tritanopie

**Automatismes**
- Adaptation de la luminosité au **contenu affiché**, avec plancher, plafond, réactivité
  et intervalle réglables
- **Profils par application** : chaque logiciel peut recevoir son propre mode
- Suspension automatique en plein écran, limite du boost sur batterie
- Planification étendue : horaires fixes en plus du suivi solaire, luminosité variable
  selon l'heure

**Confort visuel**
- Rappels de pause **20-20-20**, avec assombrissement optionnel et suivi du temps d'écran

**Réglages fins**
- Contraste, courbe gamma, balance manuelle des trois canaux
- 13 modes livrés, modes personnalisés enregistrables
- Réglages **par écran** : profil indépendant, décalage, écran éteint (BlackOut)

**Pilotage**
- 10 raccourcis globaux entièrement reconfigurables
- Molette de la souris au-dessus de l'icône
- **Ligne de commande** : `--brightness`, `--temp`, `--mode`, `--adaptive`, `--pause`,
  `--resume`, `--break`, `--reset`, `--minimized`
- Import et export de la configuration

**Interface**
- Refonte en 8 pages, pour que l'ajout de 70 réglages ne pénalise pas le geste quotidien
- Jetons de thème centralisés, contrastes **vérifiés par test** (13,4:1 / 5,6:1 / 6,0:1)
- Contraste élevé de Windows détecté et respecté
- Icônes tracées au vecteur, aucun emoji
- Transitions en fondu entre deux réglages

**Diagnostic**
- Détection du **DPST et du LACE** des pilotes Intel, avec explication et correction
- Page de diagnostics complète dans l'onglet *Avancé*

### Corrigé

- **Daltonisation : trois erreurs de calcul.** Ordre de multiplication inversé
  (`Shift × D` au lieu de `D × Shift`), indice d'identité erroné dans le produit
  matriciel, et diagonale de redistribution manquante. Conséquence : les gris viraient.
  Après correction, ils ressortent exactement inchangés — vérifié par test.
- **La fenêtre ne s'ouvrait pas au premier lancement.** `StartMinimized` valant `true`
  par défaut, un premier lancement était totalement silencieux.
- **`--mode "Nuit profonde"` sans effet.** Les guillemets étaient perdus lors de la
  transmission à l'instance en cours. La correspondance accepte désormais un nom avec
  ou sans guillemets.
- **Raccourcis absents après une remise à zéro.** Les valeurs par défaut n'étaient
  posées qu'au chargement d'un fichier existant.
- **Un test silencieusement sauté.** Le lanceur factorisé avec `call :label` n'exécutait
  que 3 suites sur 4 tout en annonçant un succès complet. Réécrit à plat, avec un
  compteur `4/4` qui refuse d'annoncer un succès incomplet.
- Textes explicatifs tronqués, en-tête masqué par le badge d'état, mise en page figée
  à la construction alors que la largeur n'était pas encore connue.

### Sécurité

- La restauration d'urgence remet aussi la **matrice de couleur** à l'identité : un
  filtre inversé rend l'écran aussi inutilisable qu'un écran noir.
- Le voile est retiré des captures d'écran (`WDA_EXCLUDEFROMCAPTURE`) — l'analyse de
  contenu ne peut donc pas se mesurer elle-même et partir en oscillation.

---

## [1.0.0] — 2026-08-15

Première version, issue du reverse engineering de PangoBright et f.lux.

### Ajouté

- **Luminosité de 5 % à 150 %** par trois étages combinés : rétroéclairage physique
  (DDC/CI et WMI), table de couleurs, voile logiciel
- Température de couleur de 1200 K à 6500 K, avec les sept ambiances de f.lux
- Suivi solaire calculé sur place (algorithme NOAA), sans aucune connexion réseau
- Multi-écran avec identification par EDID
- **Cinq protections contre l'écran noir**, dont le raccourci de secours
  `Ctrl + Alt + Maj + R` servi par un thread autonome
- Détection des applications concurrentes écrivant dans la même table de couleurs
- Déblocage de la plage gamma bridée par Windows

### Notes

- Aucun code de PangoBright ni de f.lux n'est repris. Voir
  [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md).
- Calibration : à 150 %, +52 % de luminance sur les tons moyens, **sans aucun écrêtage
  jusqu'à 135 %**.
