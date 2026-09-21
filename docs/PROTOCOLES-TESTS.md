# Protocoles de vérification

## Lancer les tests

```
tests\run-tests.cmd
```

Huit suites : six sur le moteur et les règles, deux sur l'interface elle-même
(dont 3000 gestes au hasard). Code de sortie **0** si tout passe, **1** sinon.

```
tests
un-tests.cmd singe [n]
tests
un-tests.cmd singe-messages [n] [graine]
```

Le testeur « singe » (voir la suite 8). `singe` emprunte la **vraie** souris et le vrai
clavier pendant `n` gestes (400 par défaut) ; bouger la souris ou appuyer sur Échap
l'arrête. `singe-messages` explore sans la souris, avec une graine nouvelle à chaque
lancement, ou celle donnée pour rejouer un défaut à l'identique.

```
tests\run-tests.cmd monitor
```

Observation continue de la table de couleurs et du rétroéclairage, une mesure par
seconde. Sert à diagnostiquer un écran qui varie sans raison apparente.

### Une règle du script

Le script compte les tests **réellement exécutés** et refuse d'annoncer un succès si le
compte n'y est pas :

```
Tests executes : 8 / 8
Echecs         : 0
RESULTAT : tous les tests passent
```

Cette vérification n'est pas décorative. Une première version du script, factorisée avec
`call :label`, sautait silencieusement `MatrixTest` tout en affichant « tous les tests
passent ». **Un test qui ne s'exécute pas est pire qu'un test absent : il donne une
assurance fausse.** Le script a été réécrit à plat, et le compteur ajouté.

---

## Ce que chaque suite vérifie

### 1. EngineTest — le moteur

| Vérification | Pourquoi |
|---|---|
| Table du plan de luminosité de 5 à 150 % | rend visible la répartition entre les trois étages |
| **Monotonie stricte** sur toute la course | une rupture ferait « sauter » l'écran à un endroit du curseur |
| Aucun écrêtage sous 135 % | c'est l'argument principal du boost : monter sans perdre de détail |
| Rampes croissantes, noir restant noir | une rampe non monotone produit des artefacts de couleur |
| 100 % / 6500 K identique à la rampe neutre | l'état de repos ne doit rien modifier — écart mesuré : 3/65535 |
| Bleu décroissant quand la température baisse | vérifie la courbe de corps noir |
| 6500 K exactement neutre | sinon l'application teinte l'écran en permanence |
| Lever et coucher du soleil à Paris | valide l'algorithme NOAA sur trois dates dont les deux solstices |
| Bornes de sécurité | valeurs négatives, énormes, `NaN` |

**Référence externe** : 21 juin 2026 à Paris → lever 05:47, coucher 21:58. Valeurs
astronomiques réelles, obtenues au chiffre près.

### 2. MatrixTest — la matrice de couleur

| Vérification | Pourquoi |
|---|---|
| Matrice identité neutre | point de départ de toute composition |
| Saturation 0 → les trois canaux convergent | définition des niveaux de gris |
| Luminance Rec. 709 exacte | `0.2126 R + 0.7152 G + 0.0722 B` |
| Saturation 1 → aucun changement | l'état neutre ne doit rien coûter |
| Inversion = `1 − entrée` | exactitude, pas approximation |
| Sépia : R > V > B | la teinte doit bien être chaude |
| **Filtres daltonisme : le gris ne dérive pas** | sinon toute l'interface serait teintée |
| Rouge et vert restent distincts | c'est la raison d'être du filtre |
| Rampe étendue : contraste, courbe, balance | croissance préservée malgré la composition |

**Ce test a attrapé trois bugs réels** dans la daltonisation : ordre de multiplication
inversé, indice d'identité erroné, diagonale de redistribution manquante. Le symptôme
était un gris qui virait — invisible à l'œil sur une capture, évident sur un chiffre.

### 3. SafetyTest — la sécurité

Détaillé dans [SECURITE.md](SECURITE.md). Couvre la restauration d'urgence, la
récupération après plantage, les bornes, l'aller-retour de configuration et les
contrastes du thème.

### 4. DpstTest — le pilote Intel

Détecte le DPST et le LACE, et vérifie le calcul du bit de désactivation sans rien
écrire dans le registre. Voir [DEPANNAGE.md](DEPANNAGE.md).

### 5. TaskbarTest — présence dans la barre des tâches

Vérifie que `assets/OpusScreen.ico` fournit chaque taille demandée par Windows selon la
mise à l'échelle de l'écran (16 à 128), que `OpusScreen.exe` porte bien cette icône en
ressource Win32, qu'un raccourci s'écrit et se relit à l'identique, et que le shell
accepte la liste de tâches.

Le raccourci de test est écrit dans le dossier temporaire, puis supprimé : rien n'est
déposé dans le menu Démarrer. La liste de tâches publiée sous l'identité du programme
de test est retirée dans la foulée.

### 6. VisionTest — accessibilité et identification des écrans

Deux sujets réunis par une même propriété : ils sont **invisibles à l'usage courant**.
Une correction de daltonisme mal calibrée ressemble à une correction bien calibrée pour
qui n'est pas daltonien, et un identifiant d'écran dupliqué ne se manifeste qu'avec deux
écrans du même modèle sous la main. Ce sont exactement les règles qui doivent être
tenues par un test plutôt que par l'œil.

| Vérification | Pourquoi |
|---|---|
| Gravité 0 → matrice identité, dans les deux modes | descendre le curseur à zéro doit rendre l'écran **exact**, pas « presque » |
| **Le gris ne dérive jamais**, à toute gravité et toute intensité | un gris qui vire colore toute l'interface de Windows, et le filtre devient intenable au bout d'une heure |
| Intensité 0 → aucune correction | l'interrupteur doit vraiment éteindre |
| Les paires proposées sont **indistinguables avant** correction | sinon le comparateur démontre l'inverse de ce qu'il prétend |
| Les 4 paires gagnent en écart **après** correction | c'est la seule preuve que le filtre sert à quelque chose |
| La simulation **rapproche** les paires | une simulation qui n'efface rien ne simule rien |
| Inversion à teintes conservées : blanc↔noir, rouge reste rouge | c'est toute la différence avec l'inversion classique |
| L'inversion appliquée deux fois rend la couleur d'origine | involution : aucune dérive à l'usage |
| Détection de l'état neutre | l'étage ne doit pas s'armer pour rien |
| Noms de couleurs justes, rouge ≠ vert | l'identificateur est un outil de confiance : celui qui l'interroge **ne peut pas vérifier la réponse** |
| Aller-retour d'un profil, y compris les champs 3.0 | un fichier ancien reste lisible et reproduit l'ancien comportement |
| **Tout contrôle peint à la main déclare un rôle** | un contrôle entièrement dessiné est, par défaut, un rectangle sans nom ni rôle pour Windows |
| Tout contrôle atteignable au Tab répond à une touche | sinon la tabulation s'arrête sur un cul-de-sac |
| **Deux écrans du même modèle reçoivent deux identifiants** | sans cela ils partagent une seule fiche de réglages |
| Sans collision, aucun identifiant ne change | la correction ne doit pas faire perdre les réglages déjà mémorisés |

La règle sur les contrôles est vérifiée par **réflexion sur tout l'assemblage** : le
test énumère les classes dérivant directement de `Control` et refuse celles qui ne
déclarent rien. Ajouter un contrôle peint à la main sans l'annoncer fait donc échouer la
suite — c'est ce qui transforme la mention « compatible lecteurs d'écran » du README en
promesse tenue plutôt qu'en affirmation.

**Ce test a attrapé quatre bugs réels.** Les paires de couleurs « confondues » étaient
d'abord écrites à la main d'après le sens commun — rouge/vert, rose/gris. Mesurées, elles
se révélaient parfaitement distinctes une fois simulées : elles différaient surtout par la
**clarté**, que la déficience ne touche pas. Le comparateur montrait donc des couleurs que
la personne distingue déjà et concluait à l'inutilité d'une correction qui, elle,
fonctionnait. Les paires sont désormais calculées à partir de la matrice de simulation
elle-même. Second bug : elles étaient construites à gravité maximale puis montrées à
quelqu'un réglé sur une anomalie modérée — donc parfaitement distinctes de nouveau.

Les deux autres portent sur l'interface elle-même. La bande de teintes de lecture était
atteignable au Tab et ne répondait à **aucune** touche : un cul-de-sac au clavier, dans la
page qui parle d'accessibilité. Et deux contrôles purement décoratifs — l'aperçu des
couleurs et le comparateur — recevaient le focus sans avoir la moindre action, parce que
`TabStop` vaut vrai par défaut sur un `Control`.

### 7. UiTest — l'interface, geste par geste

Tourne sur la vraie fenêtre de réglages, en **mode à blanc** (`DisplayController.DryRun`,
`SystemVolume.DryRun`, dossier de réglages temporaire) avec **trois écrans fictifs** :
aucun réglage de la machine n'est touché, et le multi-écran se teste sur un poste qui
n'a qu'un écran. Les gestes sont de vrais messages Windows (clic, double-clic, glisser,
molette), pas des appels de méthode : ils passent par la capture de la souris et la
remontée de la molette, là où les défauts se cachaient.

| Vérification | Défaut qu'elle tient fermé |
|---|---|
| Un rafraîchissement ne reconstruit pas les cartes d'écran | La page Écrans détruisait ses cartes à chaque réglage et toutes les 20 s : le curseur disparaissait sous la souris |
| Glisser le curseur d'un écran va jusqu'au bout | Le glisser s'arrêtait au premier mouvement |
| Cliquer en bas de la page Écrans ne la fait pas sauter | Le focus perdu faisait défiler la page jusqu'en bas |
| « Lier tous les écrans » relie vraiment chaque écran | Un écran passé une fois en profil indépendant ignorait ensuite le réglage général |
| Copier un écran sur les autres ; tout synchroniser | Fonctions ajoutées |
| La molette sur un curseur survolé fait défiler la page, sans changer la valeur | Faire défiler changeait luminosité, température, gravité… au passage |
| La molette sur une liste fermée ne change pas le choix | Faire défiler après avoir choisi un filtre changeait le filtre |
| Capture perdue en plein glisser : le curseur s'arrête | Il restait « accroché » à la souris |
| Deux clics rapides sur un interrupteur = deux bascules | Le second clic était avalé comme double-clic |
| Redisposer une page défilée ne la décale pas | Le contenu « tombait » de toute la hauteur défilée |
| Les dix onglets tiennent dans la colonne, Ctrl + 1…0 les ouvre | |
| Onglet Daltonisme : liste, tuiles, interrupteur, gravité | |
| Rafraîchir une page ne modifie aucun réglage | |

### 8. MonkeyTest — le testeur « singe »

Clique, glisse, fait tourner la molette, tape, change d'onglet, redimensionne et
rafraîchit **au hasard**, puis vérifie après **chaque** geste :

1. aucune exception dans l'interface ;
2. une et une seule page affichée ;
3. tous les réglages dans leurs bornes, plancher de sécurité tenu sur chaque écran ;
4. une molette sur un contrôle non choisi ne modifie aucun réglage ;
5. un clic sur un contrôle entièrement visible ne fait pas défiler la page ;
6. le haut du contenu reste à sa place (la page ne « tombe » pas) ;
7. le contrôle qui a le focus n'a pas été détruit ;
8. une carte par écran, ni plus ni moins ;
9. les réglages se relisent à l'identique.

Les pages Avancé et Raccourcis sont écartées (registre, raccourcis globaux), ainsi que
les boutons qui ouvrent d'autres applications ; une sentinelle ferme toute boîte de
dialogue qui s'ouvre malgré tout. En cas de défaut, le rapport donne les huit derniers
gestes et la graine qui permet de le rejouer.

Contrôle d'efficacité : lancé sur le code d'avant ces corrections, le singe trouve en
1 350 gestes les quatre défauts signalés à l'usage - la page qui tombe, la molette qui
change les réglages, le saut de défilement, et un interrupteur détruit entre les deux
clics d'un double-clic. Il a aussi trouvé seul un défaut que personne n'avait vu :
éteindre un écran juste après avoir réglé son curseur faisait sauter la page.

---

## Vérifications manuelles

Ce que l'automatisation ne peut pas juger. À faire avant toute diffusion.

### A. Le geste quotidien

- [ ] Ouvrir la fenêtre, glisser le curseur de luminosité de 5 à 150 % : **aucun
      à-coup**, aucune rupture visible au passage des 35 % (bascule du voile) ni des
      100 % (bascule vers le boost)
- [ ] Le fondu entre deux modes est doux, sans saut
- [ ] Le curseur reste fluide pendant le glissement, même avec le rétroéclairage actif

### B. Sécurité — à faire réellement, pas seulement en lisant le code

- [ ] Régler 5 %, puis presser `Ctrl + Alt + Maj + R` → l'écran redevient normal
- [ ] Régler 5 %, tuer le processus depuis le gestionnaire des tâches, relancer →
      l'écran est remis à neuf au démarrage
- [ ] Descendre sous 20 % et **ne rien faire** → le réglage précédent revient après 10 s
- [ ] Appliquer le filtre d'inversion, puis la panique → les couleurs reviennent

### C. Multi-écran

- [ ] Brancher un second écran pendant que l'application tourne → il apparaît dans la
      liste et reçoit les réglages
- [ ] Débrancher un écran → aucune erreur, le voile correspondant disparaît
- [ ] Décocher un écran → il redevient strictement normal, l'autre garde ses réglages
- [ ] « Écran éteint » sur l'un → l'autre reste utilisable
- [ ] **Deux écrans du même modèle** : chacun apparaît séparément et garde ses propres
      réglages — c'est le cas que la version 2.1 ne distinguait pas
- [ ] Monter un écran au-dessus de 100 % → **seul cet écran** voit son rétroéclairage
      physique changer
- [ ] Changer l'« écran de référence » des filtres → la correction daltonisme suit bien
      les réglages de couleur de l'écran désigné

### D. Intégration système

- [ ] Mise en veille puis réveil → les réglages sont reposés (Windows réinitialise la
      table au réveil)
- [ ] Verrouiller puis déverrouiller la session → idem
- [ ] Changer la résolution → les réglages sont reposés
- [ ] Lancer un jeu en plein écran → suspension automatique, couleurs d'origine
- [ ] Quitter le jeu → reprise automatique

### E. Interface

- [ ] Parcourir les 10 pages **au clavier seul** (Tab, flèches, Espace) : tout est
      atteignable et le focus reste visible
- [ ] `Ctrl + 1` à `Ctrl + 9` ouvrent les pages correspondantes
- [ ] Le **narrateur de Windows** annonce le nom, le rôle et la valeur des curseurs et
      des interrupteurs de la page Vision
- [ ] Activer le contraste élevé de Windows → l'interface reste lisible
- [ ] Redimensionner la fenêtre → aucun texte tronqué, aucun chevauchement

### F. Ligne de commande

- [ ] `--mode "Nuit profonde"` **et** `--mode Nuit profonde` donnent le même résultat
- [ ] Une commande envoyée à une instance déjà lancée prend effet en moins de 2 s
- [ ] `--help` s'affiche sans lancer l'application

---

## Environnements à couvrir

| Configuration | Ce qu'elle valide |
|---|---|
| Portable Intel | rétroéclairage WMI, **détection DPST/LACE** |
| Écran externe DDC/CI | rétroéclairage matériel réel |
| Deux écrans de résolutions différentes | positionnement du voile, réglages par écran |
| Écran à mise à l'échelle (125 %, 150 %) | conscience du DPI — le voile doit couvrir tout |
| Machine sans droits administrateur | repli propre sur le déblocage gamma |
| Windows 7 ou 8 | absence de matrice de couleur et de barre de titre sombre |

---

## Ce qui n'est pas couvert automatiquement

À dire franchement plutôt qu'à laisser croire :

- **Le rendu visuel réel.** Aucun test ne juge si 150 % « paraît » plus lumineux. Les
  chiffres mesurent la luminance calculée, pas la perception.
- **Le comportement des pilotes tiers.** Chaque pilote graphique traite
  `SetDeviceGammaRamp` à sa façon.
- **Les interactions à long terme.** Fuites de handles, dérive mémoire sur plusieurs
  jours : non instrumentés.
- **Les écrans HDR.** Non testés ; le comportement de la table de couleurs y diffère.
