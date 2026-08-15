# Sécurité : ne jamais rester coincé avec un écran noir

## Le danger

Une table de couleurs modifiée est **détenue par le pilote graphique, pas par le
processus qui l'a écrite**. Elle survit donc à sa mort.

> Si OpusScreen disparaît alors que l'écran est réglé à 5 %, **l'écran reste à 5 %**.
> Après un plantage, l'utilisateur se retrouve devant un écran quasi noir, sans
> application pour le remettre en état.

Le même raisonnement vaut pour la matrice de couleur : un filtre d'inversion laissé en
place rend l'écran tout aussi inutilisable.

C'est le risque central de cette catégorie d'outil. Il est traité par cinq protections
**indépendantes** : chacune couvre un scénario que les autres ne couvrent pas.

---

## Protection 1 — Le raccourci de secours

**`Ctrl + Alt + Maj + R` rétablit un écran normal en toutes circonstances.**

Ce raccourci n'est pas servi par l'interface. Il vit sur **son propre thread**, doté de
sa propre file de messages :

```csharp
RegisterHotKey(IntPtr.Zero, PanicHotkeyId, mods, VK_R);
while (_running && GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) { … }
```

`RegisterHotKey` avec un `hwnd` nul dépose `WM_HOTKEY` directement dans la file du thread
appelant : ce thread n'a besoin d'aucune fenêtre et ne dépend en rien de l'interface.

> **Si l'interface se fige, la panique répond quand même.**

L'ordre des opérations de restauration compte :

1. **Le voile d'abord** — `SetLayeredWindowAttributes` fonctionne d'un thread à l'autre,
   donc cela marche même si le thread propriétaire de la fenêtre est bloqué. C'est aussi
   ce qui masque le plus physiquement l'écran.
2. **Puis la matrice de couleur** — un filtre inversé est aussi gênant qu'un écran noir.
3. **Puis les tables de couleurs**, écran par écran.

Chaque étape est isolée dans son propre `try` : un échec n'empêche jamais les suivantes.

**Vérifié** : depuis 25 % / 2500 K, écart mesuré **60944 → 0**.

---

## Protection 2 — Le fichier témoin

Un fichier `active.flag` est créé dès que l'écran est réellement modifié, et supprimé
quand il redevient neutre.

S'il est **encore présent au démarrage**, c'est que la session précédente s'est mal
terminée : l'écran est probablement resté modifié. OpusScreen le remet à neuf **avant toute
autre chose**, avant même de charger les réglages.

```csharp
SafetyGuard.RecoverFromCrash();   // première instruction utile de Main()
SafetyGuard.StartGuardThread();
```

C'est la seule protection qui couvre un **arrêt brutal** (coupure de courant, `Kill`,
écran bleu), où aucun code de sortie n'a pu s'exécuter.

**Vérifié** : témoin posé + écran à 15 %/2000 K → `RecoverFromCrash()` → écart **0**,
témoin effacé.

---

## Protection 3 — Restauration sur tous les chemins de sortie

| Chemin | Gestionnaire |
|---|---|
| Fermeture normale | `TrayApp.ExitCleanly()` |
| Exception non gérée | `AppDomain.UnhandledException` |
| Exception d'interface | `Application.ThreadException` |
| Fin de processus | `AppDomain.ProcessExit` |
| Arrêt / fermeture de session Windows | `SystemEvents.SessionEnding` |

Tous appellent `SafetyGuard.EmergencyRestore()`. Sur exception fatale, la priorité
absolue est de rendre l'écran lisible — avant même d'informer l'utilisateur.

---

## Protection 4 — Bornes dures

Aucune valeur ne peut sortir de sa plage, quelle que soit son origine : interface,
fichier de réglages corrompu, ligne de commande, import de configuration.

```csharp
public static double ClampBrightness(double value)
{
    if (double.IsNaN(value)) return 100.0;
    if (value < 5.0) return 5.0;
    if (value > 150.0) return 150.0;
    return value;
}
```

- Luminosité effective : **jamais sous 5 %**
- Voile : **jamais opaque** (alpha plafonné à 250 sur 255)
- `NaN` ramené à une valeur sûre plutôt que propagé

**Vérifié** : `-999 → 5`, `9999 → 150`, `NaN → 100`, contraste `9999 → 150`,
saturation `-50 → 0`, gain `1e9 → 150`.

---

## Protection 5 — Confirmation à rebours

Sous 20 % de luminosité, une boîte de dialogue apparaît avec un compte à rebours de
10 secondes. **Sans réponse, le réglage précédent revient tout seul.**

C'est le comportement que Windows applique au changement de résolution, et pour la même
raison : **c'est la seule protection qui fonctionne quand l'utilisateur ne voit plus
rien du tout**. Il n'a rien à trouver ni à cliquer — il lui suffit d'attendre.

Déclenchée au **relâchement** du curseur seulement : la demander pendant le glissement
serait intenable.

---

## Ce qui est vérifié automatiquement

`tests/SafetyTest.cs`, lancé par `tests\run-tests.cmd` :

| Scénario | Attendu | Obtenu |
|---|---|---|
| Pire cas : 5 %, 1200 K, inversion, saturation nulle | écran effectivement extrême | écart 65535 ✓ |
| Restauration d'urgence | table **et** matrice remises à l'identité | écart 0 ✓ |
| Récupération après plantage | témoin détecté, tout remis à neuf | écart 0 ✓ |
| Absence de témoin | aucune action | ✓ |
| Six valeurs aberrantes | toutes ramenées dans la plage | ✓ |
| Réglages par défaut | 10 raccourcis présents, profil neutre | ✓ |
| Aller-retour de configuration | tout conservé, aucun doublon | ✓ |
| Contrastes du thème | ≥ 4,5:1 partout | 13,4 / 5,6 / 6,0 / 14,5 ✓ |

---

## Ce qui n'est pas couvert

Par honnêteté, les limites connues :

- **Coupure de courant pendant l'écriture de la rampe.** La fenêtre est de quelques
  millisecondes ; le fichier témoin traite le redémarrage suivant.
- **Un autre programme qui écrit dans la même table.** OpusScreen détecte les plus
  courants au démarrage, mais ne peut pas les empêcher d'agir ensuite.
- **Le DPST et le LACE des pilotes Intel** agissent en aval de tout ce que OpusScreen
  contrôle. Ils sont détectés et signalés, mais ne peuvent pas être compensés —
  voir [DEPANNAGE.md](DEPANNAGE.md).
- **Un pilote graphique qui ignore `SetDeviceGammaRamp`.** Rare, mais possible en machine
  virtuelle ou en bureau à distance. L'application le détecte en relisant la rampe et
  le signale dans l'onglet *Avancé*.

---

## En cas de problème réel

Dans l'ordre, du plus simple au plus radical :

1. **`Ctrl + Alt + Maj + R`** — fonctionne même si l'interface est figée.
2. **Fermer OpusScreen** depuis le gestionnaire des tâches : la restauration s'exécute
   à la sortie du processus.
3. **Relancer OpusScreen** : le fichier témoin déclenche la remise à neuf.
4. **Changer la résolution d'écran puis la remettre** : Windows réinitialise la table
   de couleurs au passage.
5. **Fermer la session Windows et la rouvrir** : la table est réinitialisée.
6. **Supprimer `%LOCALAPPDATA%\OpusScreen\settings.ini`** : tout revient par défaut.
