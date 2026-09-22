# Audit marketing — OpusScreen

**Site** : https://antoinebonpro.github.io/OpusScreen/
**Dépôt** : https://github.com/antoinebonpro/OpusScreen
**Date** : 22 septembre 2026
**Type** : logiciel libre, gratuit, distribué par GitHub Releases
**Note globale : 59/100 — grade C**

> Méthode : cinq analyses parallèles (contenu, conversion, concurrence, SEO, marque et
> croissance), selon la grille de la suite `market-audit`. Le produit étant gratuit, les
> estimations de chiffre d'affaires de la grille d'origine n'ont aucun sens ici : elles
> sont remplacées par des mesures réellement disponibles — téléchargements par version,
> trafic du dépôt, issues ouvertes.

---

## Résumé

OpusScreen est un produit meilleur que sa présentation, et une présentation meilleure que
sa distribution. Le logiciel couvre un créneau que personne n'occupe — mesurer le
daltonisme plutôt que le deviner, descendre à 5 % et monter à 150 % — mais il est écrit en
français pour un public mondial, il n'a aucune preuve extérieure, et il demande à un
inconnu de lancer un exécutable non signé.

**La plus grande force** : tout ce que le site affirme est vérifiable, et l'est
maintenant automatiquement (`python tools/verifie-site.py`). Le certificat de calibration
— chaque garantie associée à la suite de tests qui la tient — est un argument que presque
aucun logiciel gratuit ne peut produire.

**La plus grande faiblesse** : la croissance, notée 24/100. Zéro étoile, zéro paquet
(winget, Scoop), aucune page en anglais, aucun canal amorcé. Le marché anglophone de la
correction du daltonisme est dix à vingt fois plus large que le marché francophone.

**Les trois actions qui déplacent le plus l'aiguille** : une version anglaise du site et
du README ; une attestation de provenance de build, qui répond enfin à « pourquoi
ferais-je confiance à cet exécutable » ; et une publication sur winget, qui emprunte la
confiance de Microsoft au lieu de la demander.

---

## Notes par domaine

| Domaine | Note | Poids | Constat principal |
|---|---|---|---|
| Contenu et message | 72/100 | 25 % | Texte honnête et prouvé, mais le titre ne dit ni la plateforme, ni la gratuité, ni la différence |
| Conversion | 62/100 | 20 % | L'obstacle réel — SmartScreen — était enfoui dans les questions, sous 250 lignes |
| SEO et découvrabilité | 62/100 | 20 % | Ni canonique, ni carte Twitter, ni données structurées, ni sitemap ; logo de 1,17 Mo |
| Positionnement | 72/100 | 15 % | Créneau réellement vide, mais notoriété nulle et plateforme unique |
| Marque et confiance | 62/100 | 10 % | Aucune personne derrière le logiciel, aucune empreinte publiée sur le site |
| Croissance | 24/100 | 10 % | Tout en français, aucun paquet, aucune boucle amorcée |
| **Total pondéré** | **59/100** | | |

---

## Ce qui a déjà été corrigé

Ces points sont sortis de l'audit et sont **appliqués** — la vérification automatique les
tient désormais :

1. **Le voile de démonstration éteignait le bouton de téléchargement.** Baisser la
   luminosité de la page assombrissait la seule action qu'elle propose.
2. **L'avertissement SmartScreen remonté sous le bouton**, au lieu d'attendre la FAQ.
3. **Un mot pour les visiteurs sur téléphone** : le logiciel est pour Windows, autant le
   dire avant le téléchargement d'un fichier inutilisable.
4. **Le logo pesait 1,17 Mo pour un affichage de 30 pixels** — désormais 8,6 Ko, soit
   environ 73 % du poids de la page en moins.
5. **Données structurées** (logiciel + questions), **canonique**, **carte Twitter**,
   **image de partage absolue** en 1200 × 630, `robots.txt`, `sitemap.xml`, `404.html`.
6. **Termes cliniques visibles** : deutéranopie, protanopie, tritanopie n'existaient que
   dans le code ; ce sont pourtant les mots que l'on tape dans un moteur.
7. **Deux affirmations invérifiables retirées du README** : « l'outil que réclament en
   premier les personnes daltoniennes » et « qu'aucun concurrent ne propose » sont
   devenues une comparaison datée et vérifiable.
8. **« Né du reverse engineering de f.lux » reformulé.** La méthode réelle — lecture des
   en-têtes, de la table d'import et des chaînes, sans désassemblage ni copie de code —
   est maintenant dite dans la phrase elle-même. La formule courte aurait suffi à faire
   fermer l'onglet sur Hacker News.
9. **Une contradiction interne** : le pied de page promettait « aucune ressource
   extérieure » alors que la page interroge GitHub pour le numéro de version. C'est
   désormais écrit.
10. **Accessibilité** : `aria-pressed` sur les boutons de déficience, `aria-live` sur les
    valeurs des curseurs.

---

## Ce qui reste, par ordre d'impact

### Cette semaine

1. **Version anglaise** du site (`/en/`) et `README.en.md`, avec `hreflang` réciproque.
   C'est le seul changement qui multiplie le public atteignable.
2. **Attestation de provenance** : compiler l'exécutable par GitHub Actions et publier
   l'attestation. « Ce fichier a été compilé par GitHub depuis le commit abc1234, pas
   envoyé depuis mon poste » est la seule réponse solide à l'exécutable non signé.
3. **`SHA256SUMS.txt` dans chaque publication**, et l'empreinte affichée sur le site avec
   la commande de vérification.
4. **Sujets et description du dépôt** : `topics` est vide aujourd'hui, donc le dépôt
   n'apparaît dans aucune liste thématique de GitHub.
5. **Aperçu social du dépôt** : sans image, tout lien partagé affiche un avatar générique.

### Ce mois-ci

6. **Paquet winget**, puis Scoop. Le canal emprunte la confiance de Microsoft et contourne
   légitimement SmartScreen.
7. **Un bloc « qui écrit ça »** sous le bouton : un nom, une raison d'exister, un moyen de
   contact. Un inconnu nommé n'est plus tout à fait un inconnu.
8. **Trois pages de comparaison** (voir le plan).
9. **`CONTRIBUTING.md` et trois « good first issue »** : une contribution extérieure est le
   signal de vie le plus crédible pour un projet libre.
10. **Modèles d'issues**, dont « Ça n'a pas démarré », avec la question « comment avez-vous
    connu OpusScreen ? » — la seule mesure d'acquisition possible sans télémétrie.

### Ce trimestre

11. **Deux articles de fond** qui n'existent nulle part ailleurs : pourquoi les filtres
    daltoniens sur-corrigent, et ce qu'un logiciel fait réellement à votre carte graphique.
12. **Version anglaise de l'interface**, si les retours la réclament.
13. **Présence sur les annuaires** : AlternativeTo, Framalibre, Softpedia.

---

## Mesurer sans télémétrie

Le produit ne collecte rien, et le site n'a aucun traqueur. Ce qui reste est public, et
suffit :

| Indicateur | Où | Rythme |
|---|---|---|
| Téléchargements par version | API des publications GitHub | Avant et après chaque action |
| Vues et visiteurs du dépôt | GitHub → Insights → Traffic (14 jours glissants) | Archivage hebdomadaire |
| Provenance des visites | Même écran, section « Referring sites » | Hebdomadaire |
| Étoiles, forks, issues | Page du dépôt | Continu |
| Part d'issues « ça ne démarre pas » | Étiquettes des issues | Mensuel |

La question « comment avez-vous connu OpusScreen ? », posée dans les modèles d'issues,
remplace l'attribution publicitaire qu'on ne veut pas installer.

---

## Concurrence

| Critère | OpusScreen | f.lux | Iris | Dimmer | PangoBright | Windows |
|---|---|---|---|---|---|---|
| Prix | Gratuit, AGPL | Gratuit | Payant | Gratuit | Gratuit | Inclus |
| Sous 20 % | 5 % | oui | oui | oui | non (plancher 20 %) | non |
| Au-delà de 100 % | 150 % | non | non documenté | non | non | non |
| Daltonisme réglable | oui, 3 types | non documenté | non documenté | non | non | oui |
| Test de mesure | **oui** | non | non | non | non | non |
| Par écran | oui | non documenté | oui | oui | oui | non |
| Sans réseau | oui | localisation | compte | oui | oui | télémétrie |
| Français | natif | non | non | non | non | oui |

Deux angles défendables, et un seul à la fois :

> **Mesurer avant de corriger.** Les autres proposent un filtre daltonien ; OpusScreen
> mesure d'abord votre vision, puis règle la correction sur ce qu'il a mesuré.

> **Toute la plage, d'un seul outil.** De 5 % la nuit à 150 % en plein soleil, là où
> Windows s'arrête et où les autres utilitaires ne savent que descendre.

*Réserve : les tarifs et l'absence de certaines fonctions chez les concurrents ont été
relevés sur leurs pages officielles en septembre 2026. Une fonction non documentée n'est
pas une fonction absente — les comparaisons publiées doivent dire « non documenté ».*

---

*Audit conduit avec la suite `market-audit`, adaptée à un produit gratuit. Le plan d'action
se trouve dans [PLAN-MARKETING.md](PLAN-MARKETING.md).*
