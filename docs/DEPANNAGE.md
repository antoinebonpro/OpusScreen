# Dépannage

## Table des symptômes

| Symptôme | Cause la plus fréquente | Section |
|---|---|---|
| La luminosité monte et descend sans arrêt | DPST / LACE du pilote Intel | [1](#1-la-luminosité-varie-toute-seule) |
| L'écran clignote, les réglages ne tiennent pas | un autre programme écrit dans la même table | [2](#2-lécran-clignote) |
| Le boost au-dessus de 100 % ne change presque rien | Windows rabote les rampes | [3](#3-le-boost-est-sans-effet) |
| Aucun effet du tout | pilote sans support gamma, ou session distante | [4](#4-aucun-effet) |
| Saturation et filtres indisponibles | matrice plein écran absente | [5](#5-les-filtres-de-couleur-ne-font-rien) |
| Écran resté sombre après un plantage | table survivant au processus | [6](#6-lécran-est-resté-sombre) |
| Le voile apparaît sur les captures d'écran | Windows antérieur à la version 2004 | [7](#7-le-voile-apparaît-sur-les-captures) |
| Rien ne se passe au lancement | l'application est dans la zone de notification | [8](#8-rien-ne-se-passe-au-lancement) |

---

## 1. La luminosité varie toute seule

**Symptôme** : l'écran « respire » en permanence — il s'assombrit sur une page sombre,
s'éclaircit sur une page claire — et aucun réglage ne tient.

**Cause** : les puces **Intel** (HD, UHD, Iris, Iris Xe) embarquent deux mécanismes
d'économie d'énergie qui analysent le contenu affiché et ajustent l'écran d'eux-mêmes :

- **DPST** — *Display Power Saving Technology* : module le rétroéclairage selon l'image
- **LACE** — *Local Adaptive Contrast Enhancement* : retouche le contraste par zones

**Pourquoi c'est difficile à diagnostiquer** : ils agissent **en aval de la table de
couleurs** et sont invisibles aux deux mesures logicielles habituelles.

| Mesure | Ce qu'elle montre | Ce qu'elle rate |
|---|---|---|
| `GetDeviceGammaRamp` | la table que l'on a posée | le DPST, appliqué après |
| `WmiMonitorBrightness` | la consigne de rétroéclairage | la modulation du DPST |

Sur un cas réel : table figée à 26214 et rétroéclairage figé à 100 pendant 45 secondes,
alors que l'écran variait visiblement. Tout paraissait sain.

**Vérifier** : onglet *Avancé* → ligne `Economiseur pilote Intel`. Ou :

```
tests\run-tests.cmd
```

**Corriger — voie 1, recommandée** (immédiat, sans redémarrage, réversible) :

> **Intel Graphics Command Center**
> → Système → Alimentation → **Économie d'énergie de l'affichage** → *Désactiver*
> À faire pour « Sur batterie » **et** « Sur secteur » : ce sont deux réglages distincts.

**Corriger — voie 2** (définitive, survit aux mises à jour de l'interface Intel) :

```
HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\<NNNN>
   FeatureTestControl : bit 0x20 à 1 désactive le DPST
   exemple : 0x1200 → 0x1220
```

Le bouton de l'onglet *Avancé* le fait, avec droits administrateur. **Redémarrage
nécessaire.** Le même bouton propose ensuite l'opération inverse.

> Le LACE ne se désactive **pas** par le registre : il faut passer par l'Intel Graphics
> Command Center. Si l'écran respire encore après le redémarrage, c'est lui.

**Autres causes possibles** de variation automatique :

| Réglage | Où | Vérifier |
|---|---|---|
| Luminosité adaptative Windows (capteur) | `powercfg /q SCHEME_CURRENT SUB_VIDEO ADAPTBRIGHT` | doit valoir 0 |
| Luminosité selon le contenu (Windows 11) | Paramètres → Système → Affichage → Luminosité | désactiver |
| Adaptation au contenu de LumaFlux | onglet *Automatisme* | c'est voulu si activée |
| Économie d'énergie sur batterie | Paramètres → Système → Batterie | assombrit sur batterie |

---

## 2. L'écran clignote

**Cause** : Windows ne dispose que d'**une seule table de couleurs par carte graphique**.
Deux programmes qui y écrivent se remplacent mutuellement en boucle.

**Vérifier** : f.lux, PangoBright, Iris, Gammy, LightBulb, Twinkle Tray, ClickMonitorDDC
tournent-ils ? LumaFlux les détecte au démarrage et propose de les fermer.

**Corriger** : n'en garder qu'un. LumaFlux reprend les fonctions de f.lux et de
PangoBright, les faire coexister n'apporte rien.

---

## 3. Le boost est sans effet

**Cause** : depuis Windows Vista, GDI refuse ou écrête silencieusement les courbes trop
éloignées de la linéaire.

**Vérifier** : onglet *Avancé* → `Plage gamma complete`. Si « bridée par Windows », c'est
la cause.

**Corriger** : bouton *Débloquer la plage gamma complète*, qui écrit

```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM
   GdiIcmGammaRange = 256   (DWORD)
```

Droits administrateur, puis **fermeture et réouverture de session**.

Sans cela, LumaFlux ne reste pas sans rien faire : il redescend progressivement jusqu'à
une version acceptée par le pilote, et signale que l'effet est réduit.

---

## 4. Aucun effet

**Causes possibles** :

- **Bureau à distance** : la table de couleurs n'est pas transmise. Normal.
- **Machine virtuelle** : le pilote virtuel ignore souvent `SetDeviceGammaRamp`.
- **Écran exclu** : onglet *Écrans*, vérifier que l'écran est coché.
- **Application suspendue** : le bandeau d'état affiche *SUSPENDU* avec la raison —
  plein écran, règle d'application, ou pause manuelle.

**Vérifier** : onglet *Avancé* → chaque écran indique `gamma=oui` ou `gamma=non`.

**Contourner** : si le pilote ne gère pas la table, activer le **voile logiciel**
(onglet *Avancé*) — il fonctionne partout, mais ne descend pas en dessous de 100 %.

---

## 5. Les filtres de couleur ne font rien

Saturation, inversion, sépia et filtres daltonisme exigent la **matrice plein écran**
(API Magnification), qui demande **Windows 8** au minimum.

**Vérifier** : onglet *Avancé* → `Matrice plein ecran`.

**Causes d'indisponibilité** : Windows 7, Windows Server sans expérience de bureau,
étage désactivé dans l'onglet *Avancé*, ou un autre programme utilisant déjà l'effet
plein écran — il ne peut y en avoir qu'un à la fois sur le système.

---

## 6. L'écran est resté sombre

Une table de couleurs modifiée **survit à la mort du processus**. Dans l'ordre :

1. **`Ctrl + Alt + Maj + R`** — fonctionne même si l'interface est figée
2. **Fermer LumaFlux** depuis le gestionnaire des tâches — la restauration s'exécute à
   la sortie
3. **Relancer LumaFlux** — le fichier témoin déclenche la remise à neuf
4. **Changer la résolution puis la remettre** — Windows réinitialise la table
5. **Fermer et rouvrir la session Windows**
6. **Supprimer `%LOCALAPPDATA%\LumaFlux\settings.ini`**

Si cela s'est produit, c'est un défaut : voir [SECURITE.md](SECURITE.md).

---

## 7. Le voile apparaît sur les captures

Le voile est retiré des captures par `WDA_EXCLUDEFROMCAPTURE`, disponible depuis
**Windows 10 version 2004**. Sur une version antérieure il reste visible.

**Contourner** : rester au-dessus de 35 % de luminosité — au-delà de ce seuil, la table
de couleurs fait tout le travail et aucun voile n'est créé.

---

## 8. Rien ne se passe au lancement

L'application se loge dans la **zone de notification**, en bas à droite. Son icône prend
la couleur de la température réglée.

- **Clic gauche** : fenêtre de réglages
- **Clic droit** : menu rapide
- `Ctrl + Alt + L` : ouvrir les réglages

La fenêtre s'ouvre d'elle-même au **tout premier lancement**. Ensuite, le comportement
suit la case *Démarrer sans ouvrir la fenêtre* de l'onglet *Avancé*.

Si l'icône est absente : vérifier qu'elle n'est pas masquée dans le débordement de la
zone de notification, et que le processus tourne (gestionnaire des tâches).

---

## Rassembler les informations pour un rapport

1. **Onglet *Avancé* → Diagnostics** : écrans détectés, support gamma, état du
   rétroéclairage, plage gamma, matrice, DPST, état courant
2. **Fabricant du GPU** — Intel ⇒ suspecter le DPST en premier
3. **Observation en direct**, pendant que le symptôme se produit :

```
tests\run-tests.cmd monitor
```

Une mesure par seconde de la table et du rétroéclairage. Distingue en quelques secondes
« la table bouge » de « quelque chose d'autre bouge » — et cette distinction oriente tout
le reste du diagnostic.
