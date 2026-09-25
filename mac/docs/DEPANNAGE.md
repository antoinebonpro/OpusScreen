# Dépannage

## macOS refuse d'ouvrir le fichier téléchargé

> « Apple n'a pas pu confirmer que « OpusScreen-1.0.0.dmg » ne contenait pas de logiciel
> malveillant susceptible d'endommager votre Mac ou de porter atteinte à votre vie privée. »

**C'est la première chose que rencontre quiconque télécharge l'application, et ce n'est pas
un défaut du fichier.** macOS le dit d'ailleurs mal : il n'a rien trouvé, il n'a *rien pu
vérifier*. Le paquet n'est pas **notarié** — la notarisation consiste à envoyer le binaire à
Apple, qui l'analyse et y appose un tampon. Elle passe par un compte de développeur payant,
quatre-vingt-dix-neuf euros par an, et c'est la seule façon de faire disparaître ce message
pour tout le monde.

**Ce qu'il faut faire**, selon la version de macOS :

| Version | Le geste |
|---|---|
| **macOS 15 et suivants** (dont 26) | Fermez la boîte. **Réglages Système → Confidentialité et sécurité**, descendez jusqu'à la section *Sécurité* : une ligne cite le fichier bloqué. Cliquez **« Ouvrir quand même »**, puis confirmez par Touch ID ou mot de passe. |
| **macOS 13 et 14** | Clic droit sur le fichier → *Ouvrir*, puis *Ouvrir* dans la boîte qui suit. |
| **N'importe laquelle, au terminal** | `xattr -d com.apple.quarantine ~/Downloads/OpusScreen-1.0.0.dmg` |

Le clic droit → *Ouvrir* **ne suffit plus depuis macOS 15** : Apple a retiré ce raccourci
pour les logiciels non notariés. Une documentation qui le recommande encore — la nôtre l'a
fait — envoie chercher un bouton qui n'existe plus.

**Le geste peut être à refaire une seconde fois**, pour l'application elle-même après
l'avoir glissée dans *Applications* : l'image disque et ce qu'elle contient sont deux
fichiers distincts aux yeux de macOS.

**Pour vérifier que le fichier est bien celui qui a été publié**, avant de passer outre :

```bash
shasum -a 256 ~/Downloads/OpusScreen-1.0.0.dmg
```

L'empreinte doit correspondre à celle publiée sur la
[page de la version](https://github.com/antoinebonpro/OpusScreen/releases/tag/mac-v1.0.0).
Si elle diffère, n'ouvrez pas le fichier.

**Ou n'en passez pas par là du tout** : `./build.sh` compile votre propre paquet en une
commande, sans Xcode. Un binaire construit sur place n'est jamais mis en quarantaine, parce
qu'il n'est jamais passé par le réseau.

---

## L'écran « respire » et aucun réglage ne tient

**C'est le piège le plus fréquent, et l'application n'y est pour rien.**

macOS peut régler la luminosité de l'écran tout seul, d'après le capteur de lumière de la
pièce. Ce réglage agit **après** la table de couleurs : aucune application ne peut le
compenser, et il n'apparaît dans aucune mesure logicielle. Le symptôme est toujours le même
— l'écran monte et descend en permanence, et la luminosité demandée ne tient pas, surtout
au-dessus de 100 % où OpusScreen demande justement au rétroéclairage de monter au maximum.

**True Tone** produit le même effet sur la température : il réchauffe ou refroidit la dalle
d'après la lumière ambiante, et se bat avec le réglage de température.

**Ce qu'il faut faire.** Page *Avancé* → *Arrêter la luminosité automatique*. Le même bouton
la rétablit si vous changez d'avis. Sinon : Réglages Système → Moniteurs → décocher
« Régler automatiquement la luminosité » et « True Tone ».

La page *Avancé* affiche l'état réel, écran par écran, dans ses diagnostics.

---

## Les filtres et la loupe ne font rien

L'étage ④ — saturation, filtres daltonisme, inversion, loupe — a besoin de lire l'image
affichée. macOS demande pour cela l'autorisation **« Enregistrement de l'écran »**.

Rien n'est enregistré et rien ne sort de la machine : l'image est lue, transformée et
reposée à l'écran, image par image. Mais l'autorisation est bien celle-là, et macOS ne la
présente pas autrement.

**Ce qu'il faut faire.** Page *Découvrir* → *Accorder l'autorisation*. Si macOS a déjà posé
la question une fois, il ne la reposera pas : le bouton ouvre alors Réglages Système →
Confidentialité et sécurité → Enregistrement de l'écran, où il faut cocher OpusScreen.

**Après l'avoir cochée, relancez l'application** : macOS ne rend l'autorisation effective
qu'au lancement suivant.

> Si vous avez construit l'application vous-même, l'autorisation est liée à l'empreinte du
> binaire. Une reconstruction la remet à zéro, et il faut la réaccorder. C'est le prix d'une
> signature locale plutôt que d'un certificat de développeur.

La luminosité et la température, elles, fonctionnent sans cette autorisation. L'application
le dit et continue.

---

## Le raccourci de secours ne répond pas quand tout est bloqué

`⌃⌥⇧R` a deux chemins. Sans l'autorisation d'accessibilité, il passe par la boucle
d'événements ordinaire — ce qui suffit dans tous les cas sauf un : une interface totalement
bloquée.

**Ce qu'il faut faire.** Page *Raccourcis* → *Accorder l'autorisation d'accessibilité*. Un
fil autonome écoute alors en permanence et répond même dans ce cas. L'application ne lit
aucune autre frappe : elle attend cette combinaison et laisse tout le reste passer.

La page *Raccourcis* affiche lequel des deux chemins est actif.

---

## L'écran est resté sombre après un plantage

Il ne devrait pas : un fichier témoin est écrit dès qu'un effet est actif, et l'application
remet les tables à l'identité au démarrage suivant s'il est encore là.

**Si l'application ne se relance pas**, depuis le Terminal :

```bash
/Applications/OpusScreen.app/Contents/MacOS/OpusScreen --reset
```

**Si elle est introuvable**, macOS sait rendre l'écran tout seul :

```bash
osascript -e 'tell application "System Events" to key code 53'   # ne fait rien d'utile ici
```

La vraie solution universelle : **ouvrir puis refermer la session**, ou changer de
résolution dans Réglages Système → Moniteurs. Les deux reposent la table d'origine.

---

## L'icône n'est pas dans la barre des menus

Elle y est, mais la barre est pleine — c'est vite le cas sur un portable à encoche, qui
masque les icônes situées sous elle.

**Ce qu'il faut faire.** Maintenez ⌘ et **faites glisser** l'icône vers la gauche. Elle y
reste ensuite. Aucune application ne peut faire ce geste à votre place.

Si vous préférez retrouver l'application autrement : page *Découvrir* → *Montrer aussi une
icône dans le Dock*.

---

## Le rétroéclairage d'un écran externe ne bouge pas

Le DDC/CI n'est pas universel. Beaucoup d'écrans le déclarent sans le servir, certains
câbles le perdent, et les concentrateurs USB-C le coupent souvent.

La page *Écrans* affiche, sous chaque écran, ce que son matériel sait réellement faire :
« DDC/CI », « dalle interne » ou « aucun réglage matériel ». C'est le résultat d'une
**vérification**, pas d'une supposition : l'écran a été interrogé et a répondu.

Quand le matériel ne répond pas, les trois autres étages travaillent seuls. La plage 5-150 %
reste entière ; seul le gain en photons réels disparaît au-dessus de 100 %.

---

## Deux écrans identiques partagent leurs réglages

Ils ne devraient pas. L'identifiant d'un écran est construit sur constructeur, modèle et
numéro de série — mais deux moniteurs du même modèle rendent souvent un numéro de série nul,
et c'est justement la configuration à deux écrans la plus répandue.

Un rattrapage ajoute alors le numéro d'unité, puis la position. Si le problème persiste
malgré cela, page *Écrans* → *Redétecter les écrans*.

---

## L'écran clignote

Deux programmes écrivent dans la même table de couleurs et se remplacent en boucle.

Page *Avancé* → *Vérifier maintenant*. L'application repère f.lux, Lunar, Iris, Gammy,
MonitorControl — **et deux fonctions du système que l'on oublie** :

- **Night Shift**, qui écrit exactement la même table ;
- **les filtres de couleur d'accessibilité**, qui posent leur propre matrice par-dessus la
  nôtre.

Elle propose de les arrêter, et sait le faire.

---

## Les couleurs ne correspondent pas à l'aperçu

L'aperçu de la page *Couleur* passe par exactement le même calcul que l'écran — c'est la
même fonction, pas une réécriture. S'ils diffèrent, c'est qu'un troisième acteur intervient :
Night Shift, les filtres de couleur de macOS, ou un profil ColorSync inhabituel.

Les deux premiers sont détectés (voir ci-dessus). Pour le troisième : Réglages Système →
Moniteurs → Profil de couleur.

---

## Le test de vision dit « aucune déficience » alors que je suis daltonien

Les planches peuvent passer à côté d'une anomalie légère : un chiffre assez effacé pour
tromper une anomalie légère le serait aussi pour une vision normale. C'est une limite
physique, pas un défaut de calibration — et c'est pourquoi le test **mesure** au lieu de se
fier aux seules planches quand elles ne tranchent pas.

Si le résultat vous paraît faux, le réglage à la main reste possible : page *Daltonisme* →
*Réglage fin*. Descendez la gravité jusqu'à ce que les paires du comparateur se séparent
tout juste. C'est le réglage juste.

Entre rouge et vert, à gravité modérée, le test annonce d'ailleurs lui-même sa faible
confiance : les deux axes de confusion sont voisins, et les séparer demande un appareil de
cabinet.
