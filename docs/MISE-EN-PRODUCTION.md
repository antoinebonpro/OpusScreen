# Mise en production

Liste de contrôle à parcourir avant de diffuser une version. Elle va du plus mécanique
au plus engageant : les premières étapes se vérifient, les dernières se décident.

---

## Étape 1 — Le code

- [ ] `build.cmd` se termine **sans avertissement**
      Un avertissement toléré aujourd'hui est un bug demain ; il n'y en a aucun
      actuellement, cet état doit être conservé.
- [ ] `tests\run-tests.cmd` affiche `Tests executes : 6 / 6` et `RESULTAT : tous les tests passent`
- [ ] Aucun fichier temporaire ni binaire dans le dépôt : `git status` est propre
- [ ] Chaque nouveau réglage est **sauvegardé et rechargé** — vérifié par l'aller-retour
      de configuration dans `SafetyTest`

## Étape 2 — Les vérifications manuelles

Parcourir les sections **A à F** de [PROTOCOLES-TESTS.md](PROTOCOLES-TESTS.md).

Les trois qui ne se négocient pas, parce qu'elles portent sur le risque d'écran noir :

- [ ] **B** — sécurité, exécutée réellement et non relue dans le code
- [ ] **C** — multi-écran, avec un branchement et un débranchement à chaud
- [ ] **D** — mise en veille et réveil

## Étape 3 — Les environnements

Au minimum une machine de chaque colonne du tableau des environnements de
[PROTOCOLES-TESTS.md](PROTOCOLES-TESTS.md#environnements-à-couvrir).

**Le cas le plus instructif reste un portable Intel** : c'est là qu'apparaît le DPST, la
cause de bug la plus fréquente et la plus trompeuse — voir [DEPANNAGE.md](DEPANNAGE.md).

## Étape 4 — La documentation

- [ ] `CHANGELOG.md` complété : ce qui est ajouté, corrigé, **et ce qui casse**
- [ ] Numéro de version cohérent entre `Program.cs` (`AssemblyVersion`), le `CHANGELOG`
      et l'étiquette git
- [ ] Toute nouvelle limite connue est écrite noir sur blanc, dans
      [SECURITE.md](SECURITE.md#ce-qui-nest-pas-couvert) ou
      [PROTOCOLES-TESTS.md](PROTOCOLES-TESTS.md#ce-qui-nest-pas-couvert-automatiquement)

## Étape 5 — Le premier lancement

À faire sur une machine **où l'application n'a jamais tourné**, ou après avoir supprimé
`%LOCALAPPDATA%\OpusScreen\`.

- [ ] La fenêtre **s'ouvre** au tout premier lancement
      Sans cela l'utilisateur lance l'exe et ne voit rien se produire. Ce défaut a
      réellement existé : `StartMinimized` valant `true` par défaut, le premier
      lancement était silencieux.
- [ ] L'écran démarre **strictement neutre** — aucun réglage surprise
- [ ] La détection de conflit apparaît si f.lux ou PangoBright tournent
- [ ] L'avertissement DPST apparaît sur une machine Intel concernée
- [ ] Quitter et relancer : les réglages sont retrouvés

## Étape 6 — La diffusion

- [ ] Étiquette git posée : `git tag -a v2.0.0 -m "…"`
- [ ] Binaire compilé depuis un dépôt propre, à partir de l'étiquette
- [ ] Empreinte publiée : `certutil -hashfile OpusScreen.exe SHA256`
- [ ] Signature Authenticode si un certificat est disponible — sans elle, SmartScreen
      avertira l'utilisateur au premier lancement

---

## Ce qu'il faut savoir avant de diffuser largement

### Ce que l'application modifie sur la machine de l'utilisateur

Transparence complète, parce qu'un outil qui touche à l'affichage doit être au-dessus
de tout soupçon :

| Élément | Portée | Réversible |
|---|---|---|
| Table de couleurs du GPU | session, jusqu'au redémarrage | oui, automatiquement |
| `%LOCALAPPDATA%\OpusScreen\settings.ini` | utilisateur | supprimer le fichier |
| `HKCU\…\Run` (si démarrage automatique) | utilisateur | case à décocher |
| `HKLM\…\ICM\GdiIcmGammaRange` | **machine, admin** | uniquement sur action explicite |
| `HKLM\…\Class\{4d36e968…}\FeatureTestControl` | **machine, admin** | bouton d'annulation prévu |

Les deux dernières lignes ne sont jamais écrites sans une confirmation explicite de
l'utilisateur, avec la clé et la valeur affichées avant l'écriture.

### Ce que l'application ne fait pas

- Aucune connexion réseau — le calcul solaire est fait sur place
- Aucune télémétrie, aucune donnée transmise
- Aucun service, aucune tâche planifiée, aucun pilote installé
- Aucun fichier hors de `%LOCALAPPDATA%\OpusScreen\`

### SmartScreen

Un binaire non signé déclenche « Windows a protégé votre ordinateur » au premier
lancement. Trois voies, par ordre de préférence :

1. Certificat de signature de code (EV pour une réputation immédiate)
2. Publier l'empreinte SHA-256 et expliquer la manœuvre dans le README
3. Laisser la réputation se construire — long, et pénible pour les premiers utilisateurs

---

## Points de vigilance connus

Ce qui a déjà causé un incident, ou en causera un si l'on n'y prend pas garde.

| Risque | Ce qui le contient | À surveiller |
|---|---|---|
| Écran noir après un plantage | fichier témoin + raccourci de secours | ne jamais retirer `RecoverFromCrash()` du début de `Main()` |
| Test silencieusement sauté | compteur `4/4` dans le script | ne pas refactoriser le lanceur sans conserver le compteur |
| Réglage impossible à atteindre | bornes dures dans `ClampBrightness` | tout nouveau réglage doit être borné dans `ClampAll()` |
| Fenêtre invisible au premier lancement | `IsFirstRun` | vérifier après toute modification du démarrage |
| Conflit avec un autre outil de gamma | `ConflictDetector` | ajouter les nouveaux concurrents à la liste connue |
| Luminosité erratique sur Intel | `IntelDpst` | ne pas conclure trop vite à un bug de l'application |

---

## Après diffusion

Ce qu'il faut demander devant un rapport de bug portant sur la luminosité, **avant**
d'ouvrir le code :

1. La sortie de l'onglet **Avancé → Diagnostics** (elle contient l'état du DPST, du
   déblocage gamma, de la matrice, et la liste des écrans)
2. Le fabricant du GPU — **Intel ⇒ suspecter le DPST en premier**
3. `tests\run-tests.cmd monitor` pendant que le symptôme se produit : cela distingue en
   quelques secondes « la table de couleurs bouge » de « quelque chose d'autre bouge »

Cette dernière mesure a permis d'établir, sur un cas réel, que la table et le
rétroéclairage étaient parfaitement stables pendant que l'écran variait visiblement —
ce qui a orienté vers le pilote plutôt que vers l'application.
