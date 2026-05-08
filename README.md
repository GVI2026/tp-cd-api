# tp-cd-api

API de gestion de tâches — support du TP cours-04 sur le Continuous Deployment.

## Objectifs pédagogiques

Ce dépôt sert de support à la partie pratique du cours-04. La pipeline CI est **déjà opérationnelle et verte**. Vous n'avez qu'à ajouter les trois jobs de CD manquants.

À l'issue du TP, vous devez être capables de :

- Configurer **commit-and-tag-version** pour automatiser le versioning à partir des Conventional Commits
- Publier un artefact npm vers un registre privé (Verdaccio)
- Déployer automatiquement via SSH sur un serveur cible
- Valider un déploiement avec un smoke test

## Stack technique

| Outil | Rôle |
|---|---|
| Node 24 + NestJS 11 | Framework backend |
| better-sqlite3 | Base de données SQLite |
| Swagger | Documentation de l'API |
| Jest | Tests unitaires avec couverture |
| Supertest | Tests E2E en mémoire |
| Prettier | Formatage du code |
| ESLint + SonarJS | Analyse statique |
| Trivy | Scan de vulnérabilités |
| commit-and-tag-version | Versioning automatique (Conventional Commits → SemVer) |
| Verdaccio | Registre npm privé local (port 4873) |
| SSH-target | Serveur de déploiement simulé (port 2222, app sur 3001) |
| `act` | Exécution locale des workflows GitHub Actions |

## Prérequis

### Avec DevContainer (recommandé — Windows, Linux, macOS)

- **Docker Desktop** : https://www.docker.com/products/docker-desktop
- **VS Code** avec l'extension **Dev Containers** (`ms-vscode-remote.remote-containers`)

1. Ouvrir le dossier dans VS Code
2. Accepter la suggestion *"Reopen in Container"* (ou `Ctrl+Shift+P` → *Dev Containers: Reopen in Container*)
3. Attendre la fin du `postCreateCommand` (~3 min)

Le DevContainer configure automatiquement : npm, SQLite, SSH keys, Verdaccio, SSH-target, `act`, Trivy.

### Sans DevContainer

**Pré-requis :** Node.js 24 + Docker + Docker Compose

```bash
git clone <url-du-depot> && cd tp-cd-api
npm ci
cp .env.example .env
DATABASE_URL="./dev.db" npx ts-node db/seed.ts

# Générer les clés SSH
ssh-keygen -t ed25519 -f ~/.ssh/tp_cd_key -N "" -C "tp-cd-deploy"
cp ~/.ssh/tp_cd_key.pub docker/ssh-target/authorized_keys
printf 'SSH_PRIVATE_KEY="' > .secrets && cat ~/.ssh/tp_cd_key >> .secrets && printf '"' >> .secrets && chmod 600 .secrets

# Démarrer l'infrastructure
docker compose up -d --build
```

---

## Lancer l'application

```bash
npm run start:dev
# API : http://localhost:3000
# Swagger : http://localhost:3000/api
```

## Lancer les tests

```bash
npm test           # tests unitaires
npm run test:ci    # avec couverture
npm run test:e2e   # tests E2E
```

## Lancer la CI localement

```bash
act                  # pipeline complète
act -j security      # job spécifique
```

---

## Infrastructure Docker

| Service | Port | Description |
|---|---|---|
| Verdaccio | 4873 | Registre npm privé |
| SSH-target | 2222 | Serveur de déploiement simulé |
| App déployée | 3001 | Application après déploiement (Ex 3) |

```bash
curl http://localhost:4873/-/ping
ssh -p 2222 deployer@localhost "echo ok"
```

---

## Pipeline CI (initiale — verte)

```
install → format-lint → tests → tests-e2e → build → security
```

Votre mission : ajouter `release → publish → deploy` après `security`.

---

## Endpoints

| Méthode | Route | Description |
|---|---|---|
| GET | `/health` | Smoke test |
| GET | `/tasks` | Lister les tâches |
| GET | `/tasks/:id` | Tâche par ID |
| POST | `/tasks` | Créer une tâche |
| PATCH | `/tasks/:id` | Mettre à jour |
| DELETE | `/tasks/:id` | Supprimer |

---

## Exercices

Voir [EXERCICE.md](./EXERCICE.md) pour les instructions des 3 exercices.

```bash
# Commandes utiles après le TP
git tag                                              # tags créés par semantic-release
npm view tp-cd-api --registry http://localhost:4873  # artefact publié
ssh -p 2222 deployer@localhost "pm2 list"            # processus sur le target
curl http://localhost:3001/health                    # smoke test manuel
```
