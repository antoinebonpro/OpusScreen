# Protocoles de vérification

## Lancer les tests

```
tests\run-tests.cmd
```

Cinq suites, une centaine d'assertions. Code de sortie **0** si tout passe, **1** sinon.

```
tests\run-tests.cmd monitor
```

Observation continue de la table de couleurs et du rétroéclairage, une mesure par
seconde. Sert à diagnostiquer un écran qui varie sans raison apparente.

### Une règle du script

Le script compte les tests **réellement exécutés** et refuse d'annoncer un succès si le
compte n'y est pas :

```
Tests executes : 4 / 4
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

### D. Intégration système

- [ ] Mise en veille puis réveil → les réglages sont reposés (Windows réinitialise la
      table au réveil)
- [ ] Verrouiller puis déverrouiller la session → idem
- [ ] Changer la résolution → les réglages sont reposés
- [ ] Lancer un jeu en plein écran → suspension automatique, couleurs d'origine
- [ ] Quitter le jeu → reprise automatique

### E. Interface

- [ ] Parcourir les 8 pages **au clavier seul** (Tab, flèches, Espace) : tout est
      atteignable et le focus reste visible
- [ ] `Ctrl + 1` à `Ctrl + 8` ouvrent les pages correspondantes
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
