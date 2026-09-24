# Les cinq protections anti-écran-noir

## Le danger, et ce qu'il devient sur macOS

Sur Windows, une table de couleurs modifiée **survit à la mort du processus qui l'a posée**.
Si l'application plante alors que l'écran est à 5 %, l'écran reste à 5 % — et il faut alors
trouver, sur un écran presque noir, de quoi le remettre. C'est le danger central de cette
catégorie d'outil, et c'est ce qui justifie les cinq protections.

**macOS ne se comporte pas ainsi, et c'est mesuré plutôt que supposé.** Le serveur de
fenêtres rend la table d'origine dès que le processus qui l'avait posée disparaît — y
compris sur `SIGKILL`. La vérification `tools/test-app.sh` le constate à chaque exécution :
elle tue l'application avec un effet actif, et relit le point blanc.

```
  ✓ un effet est bien actif avant le plantage      (blanc : 0.3500)
  ✓ macOS rend la table à la mort du processus     (blanc : 1.0000)
```

**Le scénario « l'application meurt, l'écran reste sombre » n'existe donc pas ici.** Il
serait malhonnête de laisser croire le contraire pour donner du poids aux protections.

### Ce qui reste, et qui suffit à les justifier

| Situation | Ce qui se passe |
|---|---|
| Le processus **meurt** | macOS rend la table, les fenêtres disparaissent avec lui. Rien à faire. |
| Le processus **se fige** sans mourir | Il détient toujours sa table, son voile et son image filtrée. **Personne ne les lui reprendra.** |
| Un **redémarrage forcé** de la machine | Le témoin sur disque reste, et la session suivante repart d'un écran propre. |
| Le **rétroéclairage** poussé par DDC/CI | Il ne revient pas tout seul — le moniteur garde ce qu'on lui a dit. L'application ne le pousse jamais que vers le HAUT, jamais vers le bas. |

C'est la deuxième ligne qui compte : un processus figé est exactement le cas que le
raccourci de secours adresse, et c'est pourquoi il se termine lui-même si le fil principal
ne répond pas. Les cinq protections ci-dessous couvrent ce cas et les suivants ; elles sont
toutes vérifiées par `SafetyTest` et par la suite de vérification réelle.

---

## 1. Un fil de secours autonome

**Raccourci de panique : `⌃⌥⇧R`.** Il n'est pas reconfigurable — c'est le seul dont on
doive pouvoir se souvenir quand on ne voit plus rien.

Sur Windows, ce raccourci vivait sur un fil dédié doté de sa propre file de messages : il
répondait même si l'interface était figée. macOS distribue les raccourcis Carbon par la
boucle principale, c'est-à-dire par le fil qui peut justement être bloqué. Deux chemins sont
donc posés, et le meilleur disponible est utilisé :

1. **Un capteur d'événements sur un fil dédié**, avec sa propre boucle d'exécution.
   Équivalent exact du fil Windows. Il demande l'autorisation d'accessibilité — l'onglet
   *Raccourcis* l'explique et la propose. L'application ne lit aucune autre frappe : elle
   attend cette combinaison et laisse tout le reste passer sans le regarder.
2. **À défaut, le raccourci Carbon ordinaire.** Il couvre tous les cas sauf un : une
   interface totalement bloquée.

**Ce que la panique fait, dans l'ordre :**

```
a) les tables de couleurs de tous les écrans          ← CoreGraphics, depuis n'importe quel fil
b) la matrice de couleur et la loupe                  ← demandées au fil principal
c) les voiles et l'anneau du pointeur                 ← idem
d) si le fil principal n'a pas répondu en 3 secondes  ← le processus se termine
```

Le point (d) mérite d'être dit clairement : **un écran rendu vaut mieux qu'une application
qui tient**. Les tables sont déjà restaurées à ce moment-là ; terminer le processus fait
disparaître toutes ses fenêtres d'un coup, voile compris.

La loupe fait partie de ce dont il faut pouvoir sortir : un bureau agrandi huit fois est
aussi difficile à piloter qu'un bureau noir. L'anneau et l'étiquette de couleur, eux, ne
gênent pas et sont laissés en place.

---

## 2. Un fichier témoin

`~/Library/Application Support/OpusScreen/active.flag` est écrit dès qu'un effet est actif,
et effacé dès que tout redevient neutre.

S'il est encore là au démarrage suivant, c'est que la session précédente s'est mal terminée.
L'application remet alors toutes les tables à l'identité **avant toute autre chose** — avant
même de lire les réglages.

Puisque macOS rend déjà la table à la mort du processus, cette protection couvre ici un cas
plus étroit que sur Windows : un redémarrage forcé de la machine, ou un autre outil ayant
laissé la table sale. Elle coûte une écriture de fichier et se vérifie ; on la garde.

---

## 3. Restauration sur tous les chemins de sortie

| Chemin | Filet |
|---|---|
| Sortie normale | `TrayApp.exitCleanly` puis `applicationWillTerminate` |
| Signal fatal (`SIGSEGV`, `SIGABRT`, `SIGTERM`…) | gestionnaire installé au démarrage, avant toute modification |
| Fin du processus | `atexit` |
| Extinction de la session | `NSWorkspace.willPowerOffNotification` |
| Erreur fatale de Swift | les signaux ci-dessus la rattrapent |

Le gestionnaire de signal n'appelle qu'une chose : `CGDisplayRestoreColorSyncSettings`. Un
appel système simple, et exactement celui dont on a besoin dans un contexte où presque rien
n'est permis.

---

## 4. Bornes dures

Aucun réglage ne peut sortir de la plage, quelle qu'en soit l'origine — interface,
raccourci, ligne de commande, fichier importé, fichier abîmé.

- `SafetyGuard.clampBrightness` : jamais sous 5 %, jamais au-dessus de 150 %.
- Le voile n'est **jamais** totalement opaque : l'alpha plafonne à 250 sur 255.
- **Le plancher porte sur la TABLE PRODUITE, pas sur la consigne.** C'est le piège que la
  borne sur la consigne ne voyait pas : la luminosité est bien bornée à 5 %, mais la
  température et les trois gains de canaux la MULTIPLIENT ensuite, et ces gains descendent
  jusqu'à zéro. Les trois à zéro donnaient donc un écran strictement noir à n'importe quelle
  luminosité demandée.

Le critère retenu est la **luminance du blanc**, pas chaque canal pris à part : couper
entièrement le bleu est un réglage légitime — c'est même la réduction de lumière bleue
poussée au bout — et cela laisse encore 93 % de luminance. Couper les trois n'en laisse
aucune.

Quand le plancher est franchi, la table est remontée **proportionnellement** : la teinte
voulue est conservée, seule son intensité est relevée jusqu'au minimum lisible. Rien n'est
refusé à l'utilisateur, sauf l'écran noir.

---

## 5. Confirmation à rebours

Sous 20 %, un réglage demande confirmation, avec un compte à rebours de dix secondes. Sans
réponse, **on revient tout seul au réglage précédent**.

C'est le geste du changement de résolution, que tout le monde connaît. Et c'est la
protection la plus importante pour la personne qui vient de ne plus rien voir : elle n'a
**rien à faire** pour retrouver son écran.

La question n'est posée qu'au relâchement du curseur, jamais pendant le glissement — la
demander en continu serait intenable. Et elle se coupe dans l'onglet *Avancé*, pour qui
travaille tous les jours en dessous de 20 %.

---

## Une décision qui n'a pas été prise n'en est pas une

Une boîte modale peut se refermer sans qu'on ait cliqué : une autre fenêtre passe devant, la
session se verrouille, un ordre arrive par la ligne de commande. Si l'on traduit ce silence
en « dernier bouton », on enregistre une décision que personne n'a prise — et le dernier
bouton est justement, partout dans cette application, celui qui dit « ne plus jamais
demander ».

`Alerts.choose` rend donc **-1** quand aucun bouton n'a répondu, et chaque appelant traite ce
cas comme « on redemandera ». Aucun réglage permanent ne peut être posé par une question
qui n'a pas obtenu de réponse.

---

## Ce que les tests vérifient

`SafetyTest` couvre, entre autres :

- les bornes sur toutes les entrées possibles, ligne de commande comprise ;
- les trois gains de canaux à zéro **avec** la luminosité à 100 % — le cas qui donnait un
  écran noir ;
- que couper entièrement le bleu reste autorisé ;
- que la remontée proportionnelle **conserve la teinte** ;
- qu'une table strictement noire devient un gris neutre plutôt que de rester noire ;
- que le voile n'atteint jamais l'opacité totale, sur toute la plage 5-35 % ;
- que le profil neutre est vraiment neutre — c'est lui qui est posé quand on suspend.
