# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

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
