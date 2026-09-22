# Plan marketing — OpusScreen

Quatre-vingt-dix jours, aucun budget, aucune télémétrie. Le plan découle de
l'[audit](AUDIT-MARKETING.md) et se vérifie tout seul : `python tools/verifie-site.py`
échoue si le site se met à dire des choses fausses.

**Règle qui tient tout le reste.** Ce produit n'a qu'un seul capital : on peut vérifier
ce qu'il affirme. Une seule phrase invendable — un témoignage inventé, un concurrent mal
décrit, une promesse médicale — et ce capital disparaît. Aucune action de ce plan ne
demande d'exagérer quoi que ce soit.

---

## À qui l'on parle

Trois personnes, par ordre de priorité.

**Camille, 34 ans, deutéranomale.** Elle sait qu'elle « confond le vert et le rouge », n'a
jamais été mesurée, et a essayé les filtres de Windows : trop violents, abandonnés au bout
d'une heure. Ce qu'elle cherche : savoir *à quel point*, et un réglage qui ne transforme
pas son écran en néon. Ce qui la fait fuir : un logiciel qui prétend la soigner.

**Julien, 41 ans, développeur, migraineux.** Son écran est trop lumineux la nuit même au
minimum de Windows. Il a installé f.lux, veut descendre plus bas, et refuse un logiciel qui
téléphone dehors. Ce qui le convainc : du code lisible, une licence claire, aucune
connexion. Ce qui le fait fuir : un exécutable non signé sans explication.

**Sonia, 29 ans, conceptrice d'interfaces.** Elle doit vérifier qu'un graphique reste
lisible pour un daltonien. Elle utilise Color Oracle, qui simule mais ne mesure rien. Ce
qui l'intéresse : le mode simulation et le comparateur de paires confondues.

---

## Ce que l'on dit, et dans quel ordre

Une seule promesse, déclinée selon la personne :

> **On ne devine pas votre vision : on la mesure, puis on règle l'écran sur la mesure.**

| Public | Accroche | Preuve immédiate |
|---|---|---|
| Camille | « Un test de deux minutes, puis un réglage à votre mesure — pas un filtre générique. » | La démonstration en direct sur la page |
| Julien | « De 5 % à 150 %, sans compte, sans réseau, code lisible. » | Le certificat de calibration |
| Sonia | « Simulez, mesurez l'écart en Delta E, vérifiez avant de livrer. » | Le comparateur de paires |

**Trois interdits de langage**, qui valent pour toutes les publications :

1. Jamais *diagnostic*, jamais *soigner*, jamais *traiter*. On dit *mesurer*, *régler*,
   *calibrer*. En anglais : *calibration*, jamais *diagnosis*.
2. Jamais « aucun concurrent ne fait X » sans date et sans source. On écrit « non
   documenté sur leur page de fonctionnalités en septembre 2026 ».
3. Jamais de chiffre d'usage tant qu'il n'y a pas d'usage. « Projet neuf, aucun retour
   encore » est une phrase acceptable, et même attachante.

---

## Vague 1 — Jours 1 à 30 : rendre le téléchargement défendable

Rien de public. On ne lance pas un produit dont le premier obstacle est « pourquoi
devrais-je vous faire confiance ».

| # | Action | Terminée quand |
|---|---|---|
| 1 | Version anglaise du site (`/en/`) et `README.en.md`, `hreflang` réciproque | La page anglaise passe `verifie-site.py` |
| 2 | Compilation par GitHub Actions + attestation de provenance | L'attestation apparaît sur la publication |
| 3 | `SHA256SUMS.txt` dans la publication, empreinte affichée sur le site | L'empreinte du site est celle du fichier téléchargé |
| 4 | Sujets, description et aperçu social du dépôt | Le dépôt ressort dans une recherche par sujet |
| 5 | Bloc « qui écrit ça » sous le bouton : un nom, une raison, un contact | Visible sans défiler deux écrans |
| 6 | `CONTRIBUTING.md` et trois « good first issue » | Les trois issues sont ouvertes |
| 7 | Modèles d'issues, dont « Ça n'a pas démarré », avec « comment avez-vous connu OpusScreen ? » | Un modèle s'ouvre à la création d'issue |
| 8 | Fiches AlternativeTo et Framalibre, en citant aussi les manques | Les deux fiches sont en ligne |

**Ce que l'on mesure avant de passer à la suite** : le nombre de téléchargements de la
version courante, relevé au jour 30. C'est la ligne de base de tout le reste.

---

## Vague 2 — Jours 31 à 60 : les premiers vrais utilisateurs

On va là où le besoin existe déjà, en respectant les règles de chaque endroit.

| Communauté | Accueil probable | Règle à respecter | Angle |
|---|---|---|---|
| **r/ColorBlind** (anglais) | Très bon | Texte, pas de lien nu ; se présenter comme l'auteur | « J'ai construit un outil qui mesure votre axe de confusion au lieu de vous demander une étiquette. Les planches fonctionnent-elles pour vous ? » |
| **Le Crabe Info** (français) | Bon | Section logiciels, ton non commercial, répondre à tout | La plage 5–150 % et le réglage par écran |
| **r/software**, **r/opensource** | Moyen | AGPL réelle, compilation en une commande | Le logiciel libre sans compte ni réseau |
| **Colour Blind Awareness** (UK) | Lent | Courriel privé, jamais de publication publique | Proposer l'outil, demander un avis critique |
| **r/accessibility** | Moyen | Angle « vérification pour concepteurs », pas « produit » | Le mode simulation et le Delta E |
| **r/Blind**, **r/lowvision** | Prudence | **Jamais** de publication de lancement ; répondre seulement aux demandes existantes | La loupe et l'anneau de pointeur |

**Contenu de la vague** : publier l'article « Pourquoi les filtres daltoniens
sur-corrigent, et comment mesurer sa propre gravité ». Il est tiré de ce qui est déjà
codé — axes de confusion, seuil de 2,3 Delta E, méthode des escaliers — et c'est le seul
contenu du domaine que ni f.lux ni Lunar ne peuvent écrire.

**Règle de tenue** : répondre à chaque issue et à chaque commentaire sous 24 heures. Sur
un projet neuf, la réactivité est le seul substitut à la réputation.

---

## Vague 3 — Jours 61 à 90 : amplifier ce qui a pris

| # | Action | Condition d'entrée |
|---|---|---|
| 1 | Paquet **winget**, puis **Scoop** | Provenance attestée en place |
| 2 | **Show HN**, en anglais, avec l'histoire technique des quatre étages | Site anglais en ligne, disponibilité toute la journée pour répondre |
| 3 | Trois pages de comparaison | Voir ci-dessous |
| 4 | Version 3.3 tirée des retours réels, pas des idées du développeur | Au moins cinq retours reçus |
| 5 | Second article : « Ce qu'un logiciel fait vraiment à votre carte graphique » | — |

**Les trois pages de comparaison**, avec leur argument central :

1. **« OpusScreen ou f.lux »** — f.lux règle la température, pas la vision : pas de
   correction du daltonisme, pas de plage au-delà de 100 %, et il consulte votre
   localisation quand OpusScreen calcule le coucher du soleil hors ligne.
2. **« Alternative gratuite à Iris »** — même ambition de confort visuel, sans licence,
   sans compte, sans abonnement, sous AGPL.
3. **« Les filtres de couleurs de Windows suffisent-ils ? »** — Windows propose trois
   filtres et un curseur, mais rien ne dit lequel choisir ni à quelle intensité.
   OpusScreen le mesure, puis mémorise le réglage par écran.

---

## Les mots que les gens tapent

**Atteignables** — concurrence faible, intention précise :
`test daltonisme écran windows` · `mesurer son daltonisme sur ordinateur` ·
`correction daltonisme réglable windows` · `augmenter luminosité au-delà de 100 windows` ·
`luminosité différente par écran windows` · `régler luminosité sans compte ni internet` ·
`alternative gratuite à Iris` · `baisser luminosité en dessous du minimum`

**En anglais**, une fois la page `/en/` en ligne :
`lower screen brightness below minimum windows` · `free colorblind correction software` ·
`color blindness test windows` · `per-monitor brightness control windows` ·
`f.lux alternative open source` · `deuteranopia correction software`

**À éviter** — saturés, aucune chance à court terme :
`f.lux` · `filtre lumière bleue` · `logiciel gratuit luminosité` · `fatigue oculaire`

---

## Ce que l'on regarde, et quand

| Moment | Indicateur | Seuil qui déclenche une décision |
|---|---|---|
| Jour 30 | Téléchargements de référence | — (ligne de base) |
| Jour 45 | Téléchargements après r/ColorBlind | Moins de 20 : le message ne porte pas, le réécrire avant les autres communautés |
| Jour 60 | Part d'issues « ça ne démarre pas » | Plus de 30 % : le problème est SmartScreen, prioriser winget |
| Jour 75 | Retours utilisateurs reçus | Moins de 5 : ne pas faire Show HN, il est trop tôt |
| Jour 90 | Étoiles, contributeurs, paquets acceptés | Bilan et réécriture du plan |

Aucun de ces chiffres ne demande d'installer quoi que ce soit chez l'utilisateur.

---

## Les trois risques, et comment ils se désamorcent

1. **L'exécutable non signé.** C'est le premier obstacle et le plus coûteux. Réponse :
   provenance attestée par GitHub, empreinte publiée, winget, et le fait que tout se
   compile en une commande. Jamais « faites-moi confiance ».
2. **Le glissement médical.** « Mesurer la gravité » devient vite « diagnostiquer » dans
   la bouche d'un lecteur pressé, et plus vite encore en anglais. L'avertissement reste
   au-dessus du test, dans toutes les langues, et le vocabulaire est verrouillé.
3. **Un logiciel qui touche à l'affichage.** Un antivirus ou un utilisateur méfiant peut
   le prendre pour un intrus. Réponse : la liste des API employées, la preuve de
   réversibilité, le raccourci de secours mis en avant, et la restauration automatique de
   la table de couleurs au lancement suivant, même après un plantage.

---

## Validation automatique

Ce plan n'a de valeur que si le site continue de dire vrai. La commande suivante le
vérifie, et échoue sinon :

```
python tools\verifie-site.py                        (le site publié)
python tools\verifie-site.py http://localhost:8000  (avant publication)
```

Soixante vérifications : balises et données structurées, toutes les ressources et tous les
liens, l'existence de `robots.txt` et `sitemap.xml`, puis la confrontation de chaque
affirmation au code — plage de luminosité, plage de température, nombre de suites de tests,
nombre de pages, existence de chaque test cité, licence — et enfin la correspondance entre
la version affichée et la dernière publication GitHub.

À lancer avant chaque publication du site, et après chaque nouvelle version du logiciel.

---

*Plan établi à partir de l'audit du 22 septembre 2026, avec les suites `market-audit` et
`market-launch`. Il se relit tous les 90 jours : un plan qui ne change pas après trois
mois de contact avec le réel n'a pas été appliqué.*
