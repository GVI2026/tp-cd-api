# Verdaccio et npm — Registre privé, socat et retry

---

## Qu'est-ce que Verdaccio ?

[Verdaccio](https://verdaccio.org/) est un registre npm privé léger. Dans ce TP, il joue le rôle d'un registre d'entreprise (Nexus, Artifactory, GitHub Packages...) où l'on publie les artefacts npm avant de les déployer.

Il tourne dans un container Docker sur le réseau `cd-network` et est accessible :
- Depuis le DevContainer ou un runner `act` : `http://localhost:4873` (via socat)
- Depuis le container ssh-target : `http://verdaccio:4873` (via le réseau Docker interne)

Interface web : `http://localhost:4873`

---

## Pourquoi deux adresses différentes pour Verdaccio ?

C'est **la subtilité réseau la plus importante** du TP.

| Qui accède ? | Adresse à utiliser | Pourquoi |
|---|---|---|
| DevContainer / runner `act` | `http://localhost:4873` | Via le relais socat du DevContainer |
| Container `ssh-target` | `http://verdaccio:4873` | Via le réseau bridge `cd-network` — DNS Docker interne |

Le fichier `~/.npmrc` du serveur ssh-target (configuré dans son Dockerfile) utilise `verdaccio:4873` :
```
registry=http://verdaccio:4873
```

C'est pourquoi la commande `npm install --prefix ~/app tp-cd-api` dans le script de déploiement **n'a pas besoin** d'un `--registry` explicite — le serveur sait déjà où chercher.

À l'inverse, dans le runner `act`, il faut spécifier `--registry http://localhost:4873` car le `.npmrc` par défaut pointe vers le registre npm public.

---

## `bin/check-relays.sh` — maintenir les connexions socat

### Pourquoi les relais peuvent s'arrêter

Les processus socat sont lancés au démarrage du DevContainer par `setup.sh`. Ils tournent en arrière-plan (`nohup socat ... &`). Dans certains cas, ils peuvent s'arrêter :
- Après une mise en veille prolongée de la machine hôte
- Après un redémarrage du DevContainer sans rebuild
- Après un `docker compose restart`

Symptômes d'un relais mort :
```bash
curl http://localhost:4873/-/ping
# curl: (7) Failed to connect to localhost port 4873

ssh -p 2222 deployer@localhost "echo ok"
# ssh: connect to host localhost port 2222: Connection refused
```

### Comment relancer les relais

```bash
bash bin/check-relays.sh
```

Ce script vérifie chaque relais socat par son numéro de port. S'il est absent, il le relance. Il vérifie aussi que Verdaccio répond effectivement après le relais.

Exemple de sortie :
```
✓ socat :4873 → verdaccio:4873 (actif)
✗ socat :2222 → ssh-target:22 (absent) → relance...
  ↳ relancé (PID 12345)
✗ socat :3001 → ssh-target:3000 (absent) → relance...
  ↳ relancé (PID 12346)

Vérification Verdaccio...
✓ Verdaccio opérationnel (http://localhost:4873)
```

---

## `npm unpublish` — nettoyer Verdaccio avant un retry

### Pourquoi c'est nécessaire

npm (et donc Verdaccio) refuse catégoriquement de publier deux fois la même version d'un package. Si le job `publish` a déjà réussi pour la version `0.0.1`, un second `act -j publish` retournera :

```
403 Forbidden - PUT http://localhost:4873/tp-cd-api
  - You cannot publish over the previously published versions: 0.0.1
```

C'est un comportement de sécurité volontaire : les versions npm sont supposées être **immuables** en production.

Mais en phase de développement de la pipeline, on a souvent besoin de republier après une correction. La solution : supprimer la version existante dans Verdaccio.

### Les deux commandes

**Supprimer une version spécifique :**
```bash
npm unpublish tp-cd-api@0.0.1 --registry http://localhost:4873 --force
```
À utiliser quand vous avez corrigé quelque chose dans le job `publish` ou `deploy` et voulez republier la même version.

**Supprimer toutes les versions du package :**
```bash
npm unpublish tp-cd-api --registry http://localhost:4873 --force
```
À utiliser pour repartir complètement de zéro (ex: après avoir fait plusieurs tests qui ont pollué le registre).

### Quand utiliser laquelle ?

| Situation | Action recommandée |
|---|---|
| Erreur dans le job `publish`, même version | `unpublish tp-cd-api@<version>` puis relancer `act -j publish` |
| Erreur dans le job `deploy`, re-test complet | `unpublish tp-cd-api@<version>` puis relancer `act -j deploy` |
| Nettoyage complet avant de recommencer le TP | `unpublish tp-cd-api` |
| Montée de version locale (`npx commit-and-tag-version`) | Rien — c'est une nouvelle version, pas de conflit |

### Lien avec l'isolation des runners

Comme expliqué dans [git-et-runners.md](git-et-runners.md), le job `release` ne bumpe pas la version dans votre DevContainer. Si vous relancez la pipeline complète sans faire de release locale, le job `publish` essaie toujours de publier `0.0.1`. Si cette version existe déjà dans Verdaccio → erreur `403`.

**Workflow de retry typique lors du développement de la pipeline :**

```bash
# 1. Nettoyer Verdaccio
npm unpublish tp-cd-api@0.0.1 --registry http://localhost:4873 --force

# 2. Corriger votre YAML

# 3. Relancer le job concerné
act -j publish
# ou
act -j deploy
```

---

## Vérifier le contenu de Verdaccio

```bash
# Lister les versions disponibles
npm view tp-cd-api --registry http://localhost:4873

# Interface web
# Ouvrir http://localhost:4873 dans le navigateur
```
