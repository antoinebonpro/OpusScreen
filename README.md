# LumaFlux

**Luminosité 5 % → 150 %, température de couleur, filtres d'accessibilité et confort visuel, pour Windows.**

Né du reverse engineering de deux applications — **PangoBright** et **f.lux** — puis étendu
avec les fonctions que les concurrents facturent.

```
5 %                    100 %                    150 %
 |──────────────────────|────────────────────────|
 └── voile logiciel     └── état normal          └── rétroéclairage physique
     (PangoBright)          (rien n'est modifié)      + courbe gamma + gain
                                                      (territoire inédit)
```

---

## Pourquoi

PangoBright ne dépasse jamais 100 % — et pour une raison structurelle : il pose un **voile
noir semi-transparent** par-dessus l'écran. Un voile retire de la lumière, il n'en ajoute pas.

f.lux, lui, reprogramme la **table de couleurs de la carte graphique**, ce qui permet de
dépasser 100 % — mais il ne s'en sert que pour la température, jamais pour la luminosité.

LumaFlux réunit les deux techniques, y ajoute le **rétroéclairage physique** et une
**matrice de couleur plein écran**, et pilote le tout depuis une seule interface.

## Ce qu'il fait

| | PangoBright | f.lux | Iris Pro 15 $ | Lunar Pro 23 $ | **LumaFlux** |
|---|:--:|:--:|:--:|:--:|:--:|
| Luminosité logicielle | 20-100 % | — | oui | oui | **5-150 %** |
| Au-delà de 100 % | — | — | — | payant | **oui** |
| Rétroéclairage physique | — | — | — | oui | **oui** |
| Température de couleur | — | oui | oui | — | **oui** |
| Suivi solaire | — | oui | oui | oui | **oui, hors ligne** |
| Adaptation au contenu | — | — | — | — | **oui** |
| Profils par application | — | — | — | payant | **oui** |
| Filtres daltonisme | — | — | — | — | **oui** |
| Pauses 20-20-20 | — | — | payant | — | **oui** |
| Ligne de commande | — | — | — | payant | **oui** |
| Prix | gratuit | gratuit | 15 $ | 23 $ | **gratuit** |

Plus de **70 réglages** répartis sur 8 pages, 13 modes livrés, 10 raccourcis globaux
reconfigurables.

## Installation

Aucune. Le binaire est autonome : il utilise le .NET Framework 4 présent sur toute
installation de Windows.

```
build.cmd          compile LumaFlux.exe
LumaFlux.exe       lance l'application (icône dans la zone de notification)
```

**Prérequis** : Windows 7 ou plus récent. Certaines fonctions demandent davantage —
voir [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#compatibilité).

## Utilisation

- **Clic gauche** sur l'icône : fenêtre de réglages
- **Clic droit** : menu rapide
- **Molette au-dessus de l'icône** : luminosité

| Raccourci | Effet |
|---|---|
| `Ctrl + Alt + ↑ / ↓` | luminosité ± 5 % |
| `Ctrl + Alt + ← / →` | température ± 200 K |
| `Ctrl + Alt + P` | suspendre / reprendre |
| `Ctrl + Alt + M` | mode suivant |
| **`Ctrl + Alt + Maj + R`** | **secours : écran normal en toutes circonstances** |

```bash
LumaFlux.exe --brightness 130
LumaFlux.exe --mode "Nuit profonde"     # les guillemets sont facultatifs
LumaFlux.exe --adaptive on
LumaFlux.exe --reset
```

## ⚠️ La règle de sécurité

Une table de couleurs modifiée **survit à la mort du processus qui l'a posée**. Si
l'application disparaît alors que l'écran est à 5 %, **l'écran reste à 5 %**.

C'est le danger central de cette catégorie d'outil. Cinq protections indépendantes y
répondent, toutes vérifiées par test automatisé — voir [docs/SECURITE.md](docs/SECURITE.md).

**À retenir : `Ctrl + Alt + Maj + R` rétablit un écran normal en toutes circonstances**,
même si l'interface est figée. Ce raccourci est servi par un thread autonome doté de sa
propre file de messages.

## Documentation

| Document | Contenu |
|---|---|
| [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md) | Analyse de PangoBright et f.lux, preuves à l'appui |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Les quatre étages du moteur, organisation du code |
| [docs/SECURITE.md](docs/SECURITE.md) | Les cinq protections anti-écran-noir |
| [docs/PROTOCOLES-TESTS.md](docs/PROTOCOLES-TESTS.md) | Ce qui est vérifié, et comment le lancer |
| [docs/MISE-EN-PRODUCTION.md](docs/MISE-EN-PRODUCTION.md) | Liste de contrôle avant diffusion |
| [docs/DEPANNAGE.md](docs/DEPANNAGE.md) | Symptômes courants, dont le piège des pilotes Intel |
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions |

## Vérification avant diffusion

```
tests\run-tests.cmd
```

Quatre suites, une centaine d'assertions. Le script refuse d'annoncer un succès si un
test n'a pas été exécuté. Détail dans [docs/PROTOCOLES-TESTS.md](docs/PROTOCOLES-TESTS.md).

## Un piège à connaître

Sur les puces **Intel** (HD, UHD, Iris, Iris Xe), le pilote fait varier la luminosité
de lui-même selon le contenu affiché (**DPST** et **LACE**). Symptôme : l'écran
« respire » en permanence et aucun réglage ne tient.

Ces mécanismes agissent **en aval** de la table de couleurs : aucune application ne peut
les compenser, et ils sont invisibles aux mesures logicielles habituelles. LumaFlux les
détecte et propose d'y remédier — voir [docs/DEPANNAGE.md](docs/DEPANNAGE.md).

## Licence et attributions

Code sous licence MIT — voir [LICENSE](LICENSE).

Ce projet **ne contient aucun code** de PangoBright ni de f.lux. L'analyse a porté sur
les tables d'import et les chaînes de leurs binaires, afin de comprendre *quelles APIs
Windows* ils emploient. Les techniques mises au jour (`SetDeviceGammaRamp`,
`SetLayeredWindowAttributes`) sont des APIs publiques et documentées de Windows.

- **PangoBright** — © Pangolin Laser Systems Inc.
- **f.lux** — © f.lux Software LLC. Les températures de ses ambiances sont reprises de
  son fichier de configuration public.
