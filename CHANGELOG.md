# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

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
