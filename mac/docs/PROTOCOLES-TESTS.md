# Ce qui est vérifié, et comment le lancer

```bash
./run-tests.sh          # les sept suites de calcul, en mode à blanc
./run-tests.sh live     # + la vérification RÉELLE, sur le matériel
./run-tests.sh app      # + le test de bout en bout de la vraie application
./run-tests.sh all      # tout
```

Trois niveaux, et chacun répond à une question différente.

| Niveau | Ce qu'il vérifie | Compte |
|---|---|---|
| **calcul** | le moteur est-il juste ? | 7 suites, 135 tests, 5 622 assertions |
| **réel** | le système accepte-t-il ce qu'on lui demande ? | 30 tests sur le matériel |
| **bout en bout** | l'application livrée fonctionne-t-elle ? | 20 vérifications |

Le script refuse d'annoncer un succès si une suite n'a rien exécuté : une suite silencieuse
est le pire des résultats, parce qu'elle ressemble à un succès.

### Le niveau « calcul » ne touche à rien

`DisplayController.dryRun` et `SystemVolume.dryRun` sont posés avant le premier test. Les
sept suites ne touchent ni à la table de couleurs, ni au voile, ni au rétroéclairage, ni au
son de la machine qui les exécute. Les réglages sont écrits dans un dossier temporaire,
jamais dans la configuration réelle.

### Le niveau « réel » touche, et rend

`LiveTest` lève le mode à blanc : c'est tout son objet. Une table de couleurs parfaitement
calculée que le système refuse de poser ne sert à rien, et le calcul ne le dira jamais.

Chaque vérification rend ce qu'elle a emprunté, y compris si elle échoue — c'est à cela que
servent les `defer`, et le lanceur restaure une dernière fois en sortant. Une suite de tests
qui laisse l'écran sombre serait une belle démonstration du problème qu'elle est censée
prévenir.

Quand une vérification dépend d'une autorisation ou d'un matériel absent, elle le **dit** et
n'échoue pas :

```
NON VERIFIABLE SUR CETTE MACHINE :
  · fil de secours autonome — autorisation d'accessibilite absente (repli actif)
  Ce ne sont pas des echecs : c'est ce que le materiel ou les
  autorisations de cette machine ne permettent pas de constater.
```

Un test rouge parce qu'un moniteur ne parle pas DDC/CI serait un test qui ment.

---

## Pourquoi un harnais maison

XCTest n'est pas livré avec les outils en ligne de commande d'Apple : il faudrait Xcode. Or
cette application se construit et se vérifie avec les seuls outils du système — c'était déjà
le parti pris de la version Windows, dont les suites étaient compilées directement par le
compilateur livré avec le .NET Framework.

`Harness.swift` tient en deux cents lignes et porte **les noms de XCTest**, à dessein : le
jour où Xcode est installé, les mêmes fichiers de test se compilent tels quels contre le
vrai cadre, sans qu'une seule ligne change.

La découverte des tests passe par le moteur Objective-C, comme le fait XCTest : toute
méthode dont le nom commence par `test` est exécutée. C'est ce qui garantit qu'aucun test ne
peut être oublié par distraction dans une liste tenue à la main.

---

## Les sept suites

### `EngineTest` — le moteur de luminosité (14 tests)

Le plan à trois étages, et la table qu'il produit.

- Le plan est neutre à 100 %, et ne touche pas au rétroéclairage.
- **Rien n'est écrêté jusqu'à 135 %** — vérifié pour chaque point de la plage.
- Le voile n'entre en jeu que sous 35 %, et la table reste au plancher.
- Sans voile autorisé, la table descend au maximum de ce qu'elle permet.
- **Le tableau de calibration** de la documentation, point par point.
- La luminance croît strictement avec la consigne, de 40 à 150 %.
- La table est monotone — une table qui redescend produit des bandes visibles.
- Une température neutre ne modifie rien ; une température chaude ne touche pas au rouge.

### `MatrixTest` — la matrice 5×5 (13 tests)

Deux propriétés comptent plus que les autres :

- **Un gris reste gris**, pour les trois filtres, en correction comme en simulation. Un
  filtre qui teinte l'interface se fait désactiver dans la minute.
- **À gravité nulle ou intensité nulle, la matrice est EXACTEMENT l'identité.** Descendre un
  curseur à zéro doit rendre l'écran d'origine, pas « presque » l'écran d'origine.

Plus : l'inversion à teintes conservées inverse bien la clarté **et** conserve la teinte, la
simulation écrase bien l'axe de confusion, l'effet croît avec la gravité.

Et un test qui vaut pour lui-même : **la conversion vers le nuanceur Metal** est comparée à
`ColorMatrixEffect.transform`, couleur par couleur. Le pixel est un vecteur ligne d'un côté,
colonne de l'autre ; une transposition oubliée rend des couleurs plausibles et fausses, et
aucun regard ne rattrape cela.

### `VisionTest` — vision et couleurs (14 tests)

Le cœur du comparateur :

- **Les paires montrées sont réellement confondues** par la vision simulée — mesuré, pas
  affirmé.
- Elles restent confondues **à la gravité réglée**, pas seulement à 100 %.
- **La correction augmente l'écart pour TOUTES les paires montrées.** C'est la promesse de
  la page Daltonisme, et elle est vérifiée plutôt que supposée.
- La direction de confusion est normée, et c'est bien elle que la simulation écrase le plus
  — comparée à une direction perpendiculaire.
- Les noms de couleurs, et le suffixe de clarté qui ne se cumule pas avec un nom qui en
  porte déjà un.

### `ExamTest` — le test guidé (22 tests)

Le point de cette suite : **faire passer le test à des observateurs simulés dont on connaît
exactement la vision**, et vérifier que la mesure les retrouve. C'est possible parce que
tout ce qui décide vit dans `VisionExam`, sans dépendre d'un clic.

- L'escalier adaptatif converge sur un observateur simulé, pour les trois axes et trois
  gravités, à 25 points près.
- Il conclut en deux essais quand la déficience est totale, au lieu d'en gaspiller vingt-deux.
- Le seuil croît avec la gravité, et l'opération inverse retrouve la gravité.
- Les planches sont **reproductibles** pour une graine donnée — une planche qui se redessine
  différemment à chaque rafraîchissement est inutilisable.
- Chaque planche ciblée **s'efface pour son axe et reste lisible pour les deux autres** :
  une planche qui s'efface pour tout le monde n'accuse personne.
- Les planches de contrôle sont lisibles avec n'importe quelle vision.
- Une planche de contrôle ratée **effondre la confiance** : le test dit qu'il ne sait pas
  plutôt que d'annoncer un diagnostic tiré de réponses au hasard.
- Une vision normale n'est jamais déclarée daltonienne.

### `SafetyTest` — les protections (12 tests)

Voir [SECURITE.md](SECURITE.md). En résumé : les bornes sur toutes les entrées possibles,
les trois gains de canaux à zéro, la remontée proportionnelle qui conserve la teinte, le
voile jamais opaque, le témoin de plantage.

### `SettingsTest` — la persistance (21 tests)

- Aller-retour complet sur le profil, la configuration, les réglages d'écran, les raccourcis.
- **Les formats anciens se relisent** : un profil d'avant la version 3.0, une fiche d'écran
  d'avant le verrou.
- **La clef `startWithWindows` est comprise** — c'est ce qui permet à un fichier venu d'un
  PC de garder ce réglage.
- Les nombres n'utilisent jamais de séparateur local : un fichier écrit en France se relit
  aux États-Unis.
- Une action de raccourci ajoutée après coup **apparaît chez les gens qui ont déjà un
  fichier**, sans être dupliquée.
- Un écran en profil indépendant **suit quand même** les commandes générales ; un écran
  verrouillé ne suit jamais, même quand les écrans sont liés.
- Un fichier illisible retombe sur les valeurs par défaut sans rien casser.

### `SystemTest` — système et interface (37 tests)

- La température : neutre à 6500 K, monotone, bornée.
- L'horloge solaire : heures plausibles à Paris au solstice, **nuit polaire signalée plutôt
  qu'inventée**, intervalles qui passent par minuit.
- La planification : la nuit est plus chaude que le jour, la luminosité peut suivre l'heure.
- L'adaptation au contenu : une page blanche fait baisser, une scène sombre fait monter, et
  les bornes tiennent même quand on leur demande n'importe quoi.
- La mise à jour : comparaison de versions, lecture d'une publication GitHub, et **le rejet
  d'une publication qui ne contient que le paquet Windows**.
- La ligne de commande : un nom de mode à espaces, avec ou sans guillemets, qui s'arrête à
  l'option suivante.
- **Chaque raccourci par défaut est traduisible** en code de touche macOS — un raccourci
  documenté qui ne fonctionne pas serait pire que pas de raccourci.
- **Les rapports de contraste du thème**, onze couples vérifiés contre 4,5:1 ou 3:1 selon
  qu'il s'agit de texte ou d'un trait qui identifie un composant. Une application dont
  l'argument principal est l'accessibilité ne peut pas se permettre du texte à 3:1.
- Les modes livrés sont tous dans les bornes, et le mode « Normal » est vraiment neutre.

---

## `LiveTest` — la vérification réelle (30 tests)

Elle pose, lit, et compare.

- **Les écrans** : détectés, identifiants uniques et stables d'un appel à l'autre.
- **La table de couleurs** : posée à 40 %, relue, comparée entrée par entrée — puis rendue,
  et la restauration est vérifiée elle aussi.
- **Le plancher de sécurité sur du vrai matériel** : les trois gains à zéro ne rendent pas
  l'écran noir.
- **La restauration d'urgence depuis un autre fil** — c'est toute la valeur du raccourci de
  secours.
- **Ce que macOS fait d'une table dont le propriétaire meurt.** Un processus fils pose une
  table à 30 % et meurt sans rien rendre ; le test constate que le système l'a rendue. C'est
  la différence la plus importante avec Windows, et elle est mesurée plutôt que recopiée. Si
  ce test venait à échouer un jour, ce ne serait pas un défaut de l'application : ce serait
  macOS qui se met à se comporter comme Windows, et [SECURITE.md](SECURITE.md) serait à
  réécrire.
- **Le nuanceur Metal compile** — la seule chose qui puisse échouer silencieusement sur une
  machine donnée.
- **La passe de filtrage se monte et se démonte**, et une matrice identité n'arme rien :
  l'étage le plus coûteux ne s'arme que lorsqu'il sert.
- **Le voile** couvre exactement son écran, et disparaît quand il ne sert plus.
- **L'ordre d'empilement** des quatre surfaces, jusqu'au-dessus de la barre des menus.
- **L'anneau du pointeur**, l'**identificateur de couleur** qui lit un vrai pixel, la
  **mesure de contenu** qui rend une luminance plausible.
- **Le sondage du rétroéclairage répond**, et son verdict est l'un des trois attendus — pas
  une supposition.
- **Les raccourcis s'enregistrent et se rendent** : une combinaison laissée derrière soi
  resterait volée à tout le système.
- **Le paquet construit est bien formé** : binaire exécutable, icône, ressources,
  `LSUIElement`, et l'intitulé sans lequel macOS refuserait l'autorisation.

---

## `tools/test-app.sh` — de bout en bout (20 vérifications)

Le dernier chemin qu'aucune suite Swift n'emprunte : le paquet construit, lancé comme
l'utilisateur le lancera, recevant des ordres comme il en recevra.

Le script sauvegarde la configuration existante et la remet en partant. Il assombrit
réellement l'écran pendant quelques secondes.

```
  ✓ l'écran a été assombri sur ordre  (blanc : 1.0000 → 0.4000)
  ✓ l'écran a été réchauffé  (bleu 0.1121 < rouge 0.4000)
  ✓ l'ordre a été transmis sans lancer de seconde instance
  ✓ macOS rend la table à la mort du processus  (blanc : 1.0000)
  ✓ le témoin de plantage a survécu au SIGKILL
  ✓ au relancement, l'application reprend la main  (blanc : 0.3500)
```

C'est ce test qui a trouvé le défaut le plus intéressant du portage : au premier lancement,
une boîte de dialogue proposait de ranger l'application dans `/Applications` — et cette
boîte **bloquait toute l'application derrière elle**. Une copie lancée à l'ouverture de
session, ou pilotée par la ligne de commande, restait muette, et rien ne disait pourquoi.
La question se pose désormais depuis la page *Découvrir*, quand quelqu'un regarde.

---

## La sonde de mise au point

En plus des suites, le binaire de test sait **montrer** :

```bash
swift run OpusScreenTests --probe            # noms de couleurs, mesures de texte
swift run OpusScreenTests --render           # dessine les 11 pages dans des PNG
swift run OpusScreenTests --render --tall    # pages entières, sans défilement
swift run OpusScreenTests --gamma            # le point blanc réellement affiché
swift run OpusScreenTests --update-check     # ce que GitHub répond, aujourd'hui
```

`--update-check` pose au vrai serveur la question que l'application pose chaque jour, et
montre la réponse sans rien télécharger. Les tests vérifient la *lecture* d'une réponse
écrite à la main ; ils ne peuvent pas dire si la publication existe, si le nom du paquet
est le bon, ni si la ligne macOS a bien été séparée de celle de Windows. Cette sonde le
dit.

`--render` dessine l'interface **hors écran**, par `cacheDisplay(in:to:)`. Une interface
entièrement peinte à la main ne se vérifie pas en lisant le code : il faut la regarder. La
dessiner hors écran permet de le faire depuis un terminal, sans autorisation de capture, y
compris sur une machine de construction qui n'a pas d'écran du tout.

C'est ce qui a mis au jour le défaut de mesure de texte corrigé dans `Draw` : un paragraphe
de quatre lignes perdait la quatrième, parce que la mesure et le dessin ne comptaient pas la
même interligne.
