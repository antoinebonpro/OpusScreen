# Reverse engineering de PangoBright et f.lux

Ce document consigne l'analyse qui a servi de point de départ au projet, ainsi que les
preuves relevées dans les binaires.

**Méthode** : lecture des en-têtes PE, de la table d'import et des chaînes de caractères.
Aucun désassemblage, aucune copie de code. L'objectif était de déterminer *quelles APIs
Windows* chaque programme emploie — ces APIs étant publiques et documentées.

---

## 1. PangoBright — « Pangolin Screen Brightness » v2.1.0.1

**Binaire** : Delphi 32 bits, sections `CODE`/`DATA`/`BSS`/`.idata`/`.tls` (signature
Borland), signé Authenticode.
**Éditeur** : © 2010-2017 Pangolin Laser Systems Inc. — Valery Furmanov et William R. Benner, Jr.

### Le constat qui change tout

**Ce n'est pas de la luminosité.** Sa table d'import ne contient :

- aucun `SetDeviceGammaRamp`
- aucun appel DDC/CI (`dxva2.dll` absente)
- aucune API de contrôle de moniteur

PangoBright pose **une fenêtre noire semi-transparente par-dessus l'écran**.

### Preuves relevées

| Indice | Rôle déduit |
|---|---|
| Classes `FadeScrClass`, **`FadeLensScrClass`**, `FadeScrAboutClass` | La « Fade Lens » : une fenêtre-lentille par écran |
| `SetLayeredWindowAttributes` (user32) | **Le cœur du mécanisme** : opacité alpha 0→255 |
| `EnumDisplayMonitors`, `GetMonitorInfoA`, `MonitorFromPoint`, `MonitorFromRect` — présents en chaînes, absents de la table d'import | Chargement dynamique par `GetProcAddress`, typique du `Multimon.pas` de Delphi (compatibilité Windows 95) |
| `CreateBrushIndirect` + `FillRect` (gdi32) | Remplit la lentille de la couleur de fondu |
| `ChooseColorA` (comdlg32) + chaînes `"Choose fade-out color..."`, `"Custom color..."` | Choix de la teinte du voile |
| `Shell_NotifyIconA`, `TrackPopupMenu`, `CheckMenuItem` | Menu de la zone de notification |
| Chaînes `"100% (full brightness)"`, `"20% (minimum brightness)"`, `"Affect Monitor "` | Paliers du menu et sélection par écran |
| `SetTimer` + `SetWindowPos` | Se remet périodiquement au premier plan |
| `HKCU\Software\Pangolin\PangoBright`, valeur `Monitors` | Mémorise les écrans affectés |

### La formule

```
alpha = 255 × (100 − luminosité%) ÷ 100
```

À 20 % (son minimum), alpha ≈ 204 sur 255.

Styles de la fenêtre-lentille, déduits du comportement observé :
`WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_NOACTIVATE`

### La limite structurelle

> **Un voile ne peut que retirer de la lumière, jamais en ajouter.**

C'est la raison pour laquelle PangoBright plafonne à 100 % et s'arrête à 20 % : au-delà
l'écran deviendrait illisible, en deçà de 100 % il n'a rien à ajouter. C'est précisément
la limite que LumaFlux franchit, et cela impose de changer de technique.

---

## 2. f.lux

`flux-setup.exe` est un installeur **NSIS** — reconnaissable à sa section `.ndata` et à
sa table d'import minimale. Le code réel est compressé à l'intérieur. L'analyse a donc
porté sur le binaire installé, `flux.exe`.

### APIs relevées

| API importée | Rôle |
|---|---|
| **`SetDeviceGammaRamp` / `GetDeviceGammaRamp`** (gdi32) | **La vraie technique** : reprogramme la table de conversion du GPU — 3 canaux × 256 entrées × 16 bits |
| `CreateDCA("DISPLAY", …)` + `GetDeviceCaps` | Un contexte d'affichage par moniteur |
| `EnumDisplayMonitors` (user32) | Énumération des écrans |
| `SetupDiGetDeviceRegistryPropertyA`, `SetupDiEnumDeviceInfo`, `SetupDiGetClassDevsA`… | Lecture de l'**EDID** : identifie physiquement chaque écran, pour retrouver ses réglages d'une session à l'autre |
| `WcsGetDefaultColorProfile`, `GetColorDirectoryA` (mscms) | Compose avec le profil ICC actif au lieu de l'écraser |
| `WININET`, `urlmon` | Géolocalisation et mises à jour — donc connexion réseau |

### Ambiances récupérées

Le fichier `media\preset.json` de f.lux contient ses sept ambiances, en clair :

| Nom | Jour | Soirée | Nuit |
|---|---:|---:|---:|
| Recommended Colors | 6500 K | 3400 K | 1900 K |
| Reduce Eyestrain | 5900 K | 3600 K | 2500 K |
| Classic f.lux | 6500 K | 3400 K | 3400 K |
| Working Late | 6500 K | 6500 K | 2300 K |
| Far from the Equator | 6500 K | 5500 K | 1900 K |
| Cave Painting | 2700 K | 2300 K | 1500 K |
| Color Fidelity | 6500 K | 5000 K | 3400 K |

Ces valeurs sont des **données de configuration**, pas du code. LumaFlux les reprend pour
offrir un rendu familier à qui vient de f.lux.

---

## 3. Synthèse

| | PangoBright | f.lux |
|---|---|---|
| Couche d'action | fenêtre posée sur le bureau | table de couleurs du GPU |
| API centrale | `SetLayeredWindowAttributes` | `SetDeviceGammaRamp` |
| Plage | 20 → 100 % | sans objet (couleur seulement) |
| Peut dépasser 100 % | **non, par construction** | **oui, techniquement** |
| Jeux plein écran | peut clignoter, la fenêtre pouvant être masquée | traverse tout |
| Visible sur les captures d'écran | **oui** | non |
| Réseau | aucun | oui (position, mises à jour) |

### Ce que LumaFlux en retient

- **De PangoBright** : la fenêtre-lentille, seule technique qui descende sous le minimum
  matériel. Reprise pour la plage 5 → 35 % seulement, et rendue invisible aux captures
  d'écran par `WDA_EXCLUDEFROMCAPTURE`, ce que PangoBright ne fait pas.
- **De f.lux** : la table de couleurs, l'identification des écrans par EDID, les
  ambiances. Le calcul solaire, lui, est refait sur place — sans réseau.
- **Ni de l'un ni de l'autre** : le rétroéclairage physique et la matrice de couleur
  plein écran, décrits dans [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 4. Position juridique

Ce projet ne contient **aucun code** issu de PangoBright ou de f.lux, et n'est ni un
portage ni une modification de ces programmes.

L'analyse s'est limitée à la **table d'import** et aux **chaînes** des binaires, afin
d'identifier les APIs Windows employées. Ces APIs — `SetDeviceGammaRamp`,
`SetLayeredWindowAttributes`, `EnumDisplayMonitors` — sont publiques, documentées par
Microsoft, et utilisables par n'importe quel programme.

Les ambiances de f.lux sont des valeurs de configuration lisibles dans un fichier JSON
non chiffré livré avec l'application.

Marques et droits appartiennent à leurs détenteurs respectifs : Pangolin Laser Systems
Inc. et f.lux Software LLC.
