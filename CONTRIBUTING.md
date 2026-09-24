# Contribuer à OpusScreen

Le projet est écrit en français, code et commentaires compris. Les échanges en anglais
sont les bienvenus, mais le code reste commenté en français : c'est ce qui le rend lisible
pour les personnes à qui il s'adresse d'abord.

## Compiler, en une commande

Rien à installer : le compilateur C# livré avec le .NET Framework 4 est déjà sur toute
machine Windows.

```
build.cmd
```

## Vérifier, avant de proposer quoi que ce soit

```
tests\run-tests.cmd
```

Huit suites, dont un testeur « singe » qui clique au hasard. Le script refuse d'annoncer
un succès si une suite n'a pas tourné : un test qui ne s'exécute pas est pire qu'un test
absent, parce qu'il donne une assurance fausse.

Autres commandes utiles :

| Commande | Ce qu'elle fait |
|---|---|
| `tests\run-tests.cmd singe` | Le singe avec la vraie souris. Bougez la souris ou appuyez sur Échap pour l'arrêter. |
| `tests\run-tests.cmd planches` | Dessine les planches du test de daltonisme dans une image, pour les juger à l'œil. |
| `tests\run-tests.cmd captures` | Reprend les captures du site depuis la vraie fenêtre. |
| `python tools\verifie-site.py` | Confronte ce que le site affirme à ce que dit le code. |

## Ce qui est attendu d'une proposition

**Un test qui échoue avant, et qui passe après.** Pour une correction comme pour une
fonctionnalité. Si le comportement ne peut pas être tenu par un test, dites-le dans la
proposition et expliquez pourquoi.

**Un commentaire qui dit *pourquoi*, pas *quoi*.** Le code dit déjà ce qu'il fait. Ce qui
se perd, c'est la raison : la contrainte rencontrée, la solution écartée, le piège évité.
Regardez les commentaires existants — ils racontent souvent une erreur qui a coûté cher.

**Une seule idée par proposition.** Une correction et un changement d'interface dans le
même lot ne se relisent pas.

**Aucune dépendance nouvelle.** L'application tient dans un fichier et s'appuie seulement
sur ce que Windows fournit. C'est une contrainte, et c'est surtout une promesse faite aux
personnes qui téléchargent un exécutable non signé : il n'y a rien d'autre dedans.

## Les garde-fous qu'on ne franchit pas

Ces règles sont tenues par des tests. Si un changement les fait échouer, c'est le
changement qu'il faut revoir, pas le test.

- **Aucune combinaison de réglages ne descend sous 5 % de luminance.** L'écran doit rester
  lisible, quoi qu'on règle.
- **L'écran redevient normal après un plantage.** Une table de couleurs modifiée survit à
  la mort du processus : c'est pour cela qu'un témoin est écrit sur le disque.
- **Rien ne sort de la machine.** Aucune télémétrie, aucun compte. Le seul appel réseau
  est la lecture quotidienne du numéro de la dernière version chez GitHub
  (`src/Updater.cs`), désactivable : n'en ajoutez pas d'autre.
- **Chaque contrôle dessiné à la main s'annonce** avec son rôle, son nom et son état : une
  application d'accessibilité ne peut pas être elle-même inaccessible.
- **Le vocabulaire du daltonisme reste celui d'un réglage**, jamais celui d'un diagnostic.
  On mesure, on règle, on calibre. On ne soigne pas.

## Par où commencer

Les issues marquées `good first issue` sont choisies pour être abordables sans connaître
tout le projet. Si aucune ne vous parle, ouvrez une issue avant d'écrire du code : cela
évite d'écrire beaucoup pour rien.

## Signaler un problème

Trois modèles existent : « Ça n'a pas démarré », « Un problème dans l'application » et
« Le test ou la correction du daltonisme ». Le dernier est le plus précieux — le test est
vérifié par le calcul sur des yeux simulés, mais un œil réel reste le seul juge.
