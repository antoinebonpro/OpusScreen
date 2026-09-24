# Journal des versions

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).

---

## [1.0.0] — 2026-09-24

Première version pour macOS. Portage intégral d'OpusScreen 3.4.0, écrit pour Windows.

### Ajouté

Toutes les fonctions de la version Windows, reconstruites sur les API de macOS :

- **Les quatre étages du moteur** — rétroéclairage physique, table de couleurs, voile
  logiciel, matrice de couleur. Luminosité de 5 à 150 %, avec la même répartition et la même
  calibration : rien n'est écrêté jusqu'à 135 %.
- **Rétroéclairage physique** par `DisplayServices` sur la dalle interne, et par DDC/CI sur
  les écrans externes — `IOAVService` sur Apple Silicon, `IOI2CSendRequest` sur Intel.
- **Onze pages de réglages**, plus de quatre-vingts réglages, vingt modes livrés.
- **Daltonisme** : trois déficiences, gravité de 0 à 100 %, intensité séparée, mode
  simulation, comparateur de couleurs confondues chiffré en ΔE, et test guidé de deux
  minutes.
- **Basse vision** : loupe plein écran cumulée avec les filtres, anneau de repérage du
  pointeur, identificateur de couleur, inversion à teintes conservées, teintes de lecture.
- **Confort** : pauses 20-20-20, rappels de clignement, volume de sortie.
- **Automatismes** : suivi solaire hors ligne (NOAA), horaires fixes, adaptation au contenu
  affiché, règles par application, suspension en plein écran.
- **Quinze raccourcis globaux** reconfigurables, et le raccourci de secours `⌃⌥⇧R`.
- **Ligne de commande** complète, avec transmission à l'instance en cours.
- **Les cinq protections anti-écran-noir**, toutes vérifiées par test.
- **VoiceOver** : chaque contrôle dessiné à la main déclare son rôle, son nom et sa valeur.

### Meilleur que sur Windows

- **La matrice de couleur est réglable écran par écran.** Sur Windows,
  `MagSetFullscreenColorEffect` n'exposait qu'un effet pour tout le bureau — une limite de
  l'API que la documentation d'origine signalait comme telle. Le réglage « écran de
  référence » demeure, mais comme un choix.
- **La table de couleurs n'est plus bridée.** Le déblocage de `GdiIcmGammaRange`, qui
  demandait les droits administrateur et une réouverture de session, n'a plus d'objet.
- **Le piège de la luminosité automatique se corrige depuis l'application.** L'équivalent
  Windows — le DPST des pilotes Intel — demandait une écriture dans le registre et un
  redémarrage.

### Corrigé par rapport à la version Windows

- **6500 K est maintenant exactement neutre.** Les constantes de normalisation publiées sont
  arrondies à quatre décimales ; avec elles, 6500 K rendait 0,99996 sur le bleu au lieu de 1.
  Quatre centièmes de millième ne se voient pas à l'œil, mais ils se voient dans la table —
  deux ou trois niveaux d'écart sur 65 535 — et ils rendaient fausse la seule promesse que
  cette classe ait à tenir. La référence est désormais calculée par la formule elle-même.

### Moindre, et dit comme tel

- **L'étage « matrice de couleur » demande l'autorisation « Enregistrement de l'écran ».**
  Sans elle, la saturation, les filtres et la loupe sont indisponibles et le disent ; la
  luminosité et la température continuent de fonctionner.
- **Le pointeur n'est pas recoloré par la matrice** : macOS le dessine au-dessus de toutes
  les fenêtres. Sous la loupe, un pointeur agrandi est ajouté à l'image.
- **Le fil de secours demande l'autorisation d'accessibilité** pour répondre même quand
  l'interface est bloquée. Sans elle, un repli couvre tous les autres cas.
- **Il n'y a pas de mixeur par application sur macOS** : la fonction « tout remettre au
  maximum » se réduit au volume de sortie, et la page l'explique plutôt que d'inventer.

### Compatibilité

- **Le fichier de configuration est celui de la version Windows**, clef par clef. Une
  configuration exportée depuis un PC s'importe ici telle quelle, et inversement.
- Les codes de touche des raccourcis restent ceux de Windows dans le fichier, traduits vers
  les codes Carbon au moment de poser le raccourci.
- **Les deux versions se mettent à jour séparément**, tout en vivant dans le même dépôt. Les
  publications macOS portent l'étiquette `mac-v…`, celles de Windows `v…`, et chacune ne
  regarde que les siennes : l'application cherche la publication la plus récente qui porte un
  paquet macOS, au lieu de demander « la dernière » — qui serait celle de Windows, où elle ne
  trouverait rien et annoncerait chaque jour une erreur de réseau qui n'en est pas une.

### Vérification

Trois niveaux, parce qu'un moteur juste et une application qui fonctionne ne sont pas la
même affirmation.

- **Calcul** — sept suites, 135 tests, 5 622 assertions, en mode à blanc : elles ne touchent
  ni à l'écran, ni au son, ni à la configuration de la machine qui les exécute.
- **Réel** — 30 vérifications sur le matériel : la table de couleurs posée puis relue entrée
  par entrée, le nuanceur Metal qui compile, la passe de filtrage qui se monte et se
  démonte, le voile aux dimensions de l'écran, le sondage DDC/CI qui répond.
- **Bout en bout** — 20 vérifications sur le paquet livré, lancé et piloté comme
  l'utilisateur le fera.

Le harnais ne dépend pas de Xcode : l'application se construit et se vérifie avec les seuls
outils en ligne de commande d'Apple. Les onze pages se dessinent hors écran dans des PNG,
pour être regardées sans autorisation de capture.

### Trouvé par les tests, et corrigé

- **Une alerte écartée autrement que par un clic était enregistrée comme une décision** — et
  le dernier bouton est justement celui qui dit « ne plus jamais demander ». `Alerts.choose`
  rend désormais -1 quand aucun bouton n'a répondu.
- **Une boîte de dialogue au premier lancement bloquait toute l'application derrière elle.**
  Une copie lancée à l'ouverture de session, ou pilotée par la ligne de commande, restait
  muette sans que rien ne le dise. Plus aucune modale au démarrage : une bannière, et un
  bouton dans la page *Découvrir*.
- **Un paragraphe de quatre lignes en perdait une.** La mesure du texte et son dessin ne
  comptaient pas la même interligne — une fraction de point par ligne, assez pour faire
  disparaître la dernière.
- **6500 K n'était pas exactement neutre** (voir plus haut).

### Une croyance corrigée

La documentation affirmait, par report depuis Windows, qu'une table de couleurs survit à la
mort du processus qui l'a posée. **C'est faux sur macOS**, et le test le mesure : le serveur
de fenêtres rend la table d'origine dès que le processus disparaît, `SIGKILL` compris. Les
cinq protections restent justifiées pour le cas du processus **figé**, qui détient toujours
sa table et ses fenêtres — et la documentation dit maintenant ce qui a été constaté plutôt
que ce qui était supposé.
