# Exercices — TP Cours-04 : Continuous Deployment

## Contexte

La pipeline CI de ce dépôt est **déjà opérationnelle et verte** : lint, tests unitaires, tests E2E, build et scan de sécurité fonctionnent. Votre mission est de compléter la chaîne en ajoutant les trois jobs de **Continuous Deployment** manquants dans `.github/workflows/ci.yml`.

**Infrastructure disponible dans votre DevContainer :**

- **Verdaccio** — registre npm privé : `http://localhost:4873`
- **SSH-target** — serveur de déploiement simulé : `ssh deployer@localhost -p 2222`
- L'application déployée sera accessible sur : `http://localhost:3001`

> **Perte de connexion socat ?** Si Verdaccio ou le SSH-target deviennent inaccessibles après une mise en veille du DevContainer, relancez les relais réseau :
> ```bash
> bash bin/check-relays.sh
> ```
> Voir [docs/verdaccio-et-npm.md](docs/verdaccio-et-npm.md) pour les détails.

Vérifiez que tout est opérationnel avant de commencer :

```bash
# Vérifier Verdaccio
curl http://localhost:4873/-/ping

# Vérifier le SSH-target
ssh -p 2222 deployer@localhost "echo ok"

# Vérifier que la CI de base passe
act -j security
```

---

## Exercice 1 — commit-and-tag-version (15 min)

**Objectif :** automatiser entièrement le versioning et la création de tags Git à partir des messages de commit, sans aucune intervention humaine.

### Ce que vous devez réaliser

**Étape 1 — Vérifier le script `release` dans `package.json`**

Le script est **déjà présent** dans `package.json` :

```json
"release": "commit-and-tag-version"
```

Rien à ajouter.

**Étape 2 — Ajouter le job `release` dans `.github/workflows/ci.yml`**

Le job doit respecter les contraintes suivantes :

- Dépend du job `security`
- S'exécute **uniquement sur la branche `main`** (`if: github.ref == 'refs/heads/main'`)
- Le checkout doit utiliser `fetch-depth: 0` (pour lire tout l'historique git et les tags)
- Configurer l'identité git (nécessaire pour le commit de version) :
  ```bash
  git config user.email "ci@example.com"
  git config user.name "CI"
  ```
- Lancer `npx commit-and-tag-version`

<details>
<summary>Solution</summary>

```yaml
release:
  name: Release
  runs-on: ubuntu-latest
  needs: [security]
  if: github.ref == 'refs/heads/main'

  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '24'

    - name: Configurer git user
      run: |
        git config user.email "ci@example.com"
        git config user.name "CI"

    - name: Lancer commit-and-tag-version
      run: npx commit-and-tag-version
```

</details>

**Étape 3 — Faire un commit et tester**

```bash
# Un breaking change (feat! ou BREAKING CHANGE) bumpe la version majeure
git add .
git commit -m "feat!: add CD pipeline"

# Lancer le job release
act -j release
```

### Résultat attendu

Le job `release` réussit. `commit-and-tag-version` crée un commit `chore(release): 1.0.0` et un tag `v1.0.0` **dans le runner**.

> ⚠️ **Ce commit et ce tag ne seront PAS visibles dans votre DevContainer.**
>
> Chaque job lancé par `act` s'exécute dans un **container éphémère isolé**. Git y clone votre dépôt, effectue ses opérations, puis le container est détruit. Le dépôt git de votre DevContainer n'est jamais modifié par un runner `act`.
>
> Résultat : `git tag` dans votre terminal ne montrera rien de nouveau, et `package.json` gardera sa version d'origine.
>
> → Pour comprendre pourquoi et comment faire une vraie montée de version, voir [docs/git-et-runners.md](docs/git-et-runners.md).

---

## Exercice 2 — Publier vers Verdaccio (15 min)

**Objectif :** publier l'artefact déjà compilé par le job `build` vers le registre npm local, sans recompiler.

### Ce que vous devez réaliser

Ajouter un job `publish` dans `.github/workflows/ci.yml` avec les contraintes suivantes :

- Dépend du job `release`
- S'exécute **uniquement sur la branche `main`**
- Checkout + restauration du cache `node_modules`
- **Télécharger l'artefact `build-dist`** produit par le job `build` via `actions/download-artifact@v4` → le placer dans `dist/`

  > Pourquoi ? Le job `build` a déjà compilé le TypeScript et sauvegardé le résultat comme artefact GitHub Actions. Le réutiliser ici évite de recompiler et garantit que ce qu'on publie est **exactement** ce qui a été testé et validé en amont.

- **Configurer l'authentification npm** pour Verdaccio. Verdaccio accepte les publications anonymes dans cette configuration, mais `npm publish` exige tout de même qu'un token soit défini pour la registry cible dans `.npmrc` :
  ```bash
  npm set //localhost:4873/:_authToken "dummy-token"
  ```
- **Publier** :
  ```bash
  npm publish --registry http://localhost:4873
  ```
  npm lit automatiquement la version depuis `package.json` — pas besoin de l'extraire manuellement.

<details>
<summary>Solution</summary>

```yaml
publish:
  name: Publish
  runs-on: ubuntu-latest
  needs: [release]
  if: github.ref == 'refs/heads/main'

  steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '24'

    - name: Restaurer le cache node_modules
      uses: actions/cache@v4
      with:
        path: node_modules
        key: node-modules-${{ hashFiles('package-lock.json') }}

    - name: Télécharger l'artefact build
      uses: actions/download-artifact@v4
      with:
        name: build-dist
        path: dist/

    - name: Configurer l'authentification Verdaccio
      run: npm set //localhost:4873/:_authToken "dummy-token"

    - name: Publier vers Verdaccio
      run: npm publish --registry http://localhost:4873
```

</details>

### Tester

```bash
act -j publish
```

### Résultat attendu

- Naviguer sur `http://localhost:4873` — le package `tp-cd-api` doit apparaître
- Ou vérifier en ligne de commande :
  ```bash
  npm view tp-cd-api --registry http://localhost:4873
  ```

> ⚠️ **Verdaccio refuse de publier deux fois la même version.**
>
> Si vous relancez `act -j publish` sans changer de version, vous obtiendrez une erreur `403 Forbidden`. C'est le comportement normal d'un registre npm. Voir la section [Retry et `npm unpublish`](#retry-et-npm-unpublish) ci-dessous.

---

## Exercice 3 — Déployer via SSH + Smoke Test (15 min)

**Objectif :** déployer automatiquement l'artefact sur le serveur target et valider le déploiement avec un smoke test.

### Ce que vous devez réaliser

Ajouter un job `deploy` dans `.github/workflows/ci.yml` avec les contraintes suivantes :

- Dépend du job `publish`
- S'exécute **uniquement sur la branche `main`**
- Utilise l'action **`appleboy/ssh-action@v0.1.7`** pour se connecter au SSH-target et exécuter le déploiement :
  - `host: localhost`, `port: 2222`, `username: deployer`
  - `key: ${{ secrets.SSH_PRIVATE_KEY }}` — la clé est pré-configurée dans `.secrets` par le `postCreateCommand`
  - Script exécuté **sur le serveur** :
    ```bash
    mkdir -p ~/app
    npm install --prefix ~/app tp-cd-api --ignore-scripts
    pm2 restart tp-cd-api || pm2 start ~/app/node_modules/tp-cd-api/dist/src/main.js --name tp-cd-api
    sleep 5
    curl -f http://localhost:3000/health || exit 1
    ```

  > **Pourquoi `--prefix ~/app` et pas `-g` ?** `npm install -g` installe dans un répertoire système qui peut nécessiter des droits root. `--prefix ~/app` installe dans le dossier personnel de l'utilisateur `deployer`, sans élévation de privilèges.
  >
  > **Pourquoi pas de `--registry` dans `npm install` ?** Le fichier `~/.npmrc` du serveur ssh-target pointe déjà vers `http://verdaccio:4873` (configuré dans le Dockerfile de l'image). Le serveur utilise l'adresse DNS interne Docker `verdaccio:4873`, pas `localhost:4873`.
  >
  > **Pourquoi `curl localhost:3000` côté serveur et `localhost:3001` depuis le runner ?** L'app NestJS écoute sur le port `3000` à l'intérieur du container ssh-target — c'est le health check interne. Le port `3001` sur le DevContainer/runner est relayé par socat vers le `3000` du ssh-target — c'est le smoke test externe.

- **Smoke test depuis le runner** (step séparé) :
  ```bash
  curl -f http://localhost:3001/health
  ```

<details>
<summary>Solution</summary>

```yaml
deploy:
  name: Deploy
  runs-on: ubuntu-latest
  needs: [publish]
  if: github.ref == 'refs/heads/main'

  steps:
    - name: Déployer sur le serveur distant
      uses: appleboy/ssh-action@v0.1.7
      with:
        host: localhost
        port: 2222
        username: deployer
        key: ${{ secrets.SSH_PRIVATE_KEY }}
        script: |
          mkdir -p ~/app
          npm install --prefix ~/app tp-cd-api --ignore-scripts
          pm2 restart tp-cd-api || pm2 start ~/app/node_modules/tp-cd-api/dist/src/main.js --name tp-cd-api
          sleep 5
          curl -f http://localhost:3000/health || exit 1

    - name: Smoke test
      run: curl -f http://localhost:3001/health
```

</details>

### Tester

```bash
act -j deploy
```

### Résultat attendu

```bash
# L'API répond sur le serveur target (via socat) :
curl http://localhost:3001/health
# {"status":"ok","timestamp":"2026-..."}

curl http://localhost:3001/tasks
# [{...}, {...}]
```

---

## Retry et `npm unpublish`

Lors du développement de la pipeline, il est fréquent de relancer un job après une correction. Le job `publish` échouera si la version est déjà présente dans Verdaccio (erreur `403 Forbidden`).

**Deux commandes pour nettoyer avant un retry :**

```bash
# Supprimer une version spécifique
npm unpublish tp-cd-api@0.0.1 --registry http://localhost:4873 --force

# Supprimer toutes les versions du package
npm unpublish tp-cd-api --registry http://localhost:4873 --force
```

**Quand utiliser laquelle ?**

| Situation | Commande |
|---|---|
| Vous avez publié `0.0.1` et voulez republier après une correction du job | `unpublish tp-cd-api@0.0.1` |
| Vous voulez repartir de zéro (toutes les versions) | `unpublish tp-cd-api` |
| Vous avez fait un release local (`npx commit-and-tag-version`) et voulez tester la nouvelle version | Rien à supprimer — c'est une nouvelle version |

> **Lien avec l'isolation des runners :** parce que le job `release` s'exécute dans un runner éphémère, la version dans `package.json` **ne change pas** dans votre DevContainer. Si vous relancez la pipeline complète sans faire de release local au préalable, le job `publish` essaiera toujours de publier `0.0.1` — et échouera si elle existe déjà dans Verdaccio. C'est pourquoi `npm unpublish` est votre outil de retry en phase de développement de la pipeline.
>
> → Voir [docs/git-et-runners.md](docs/git-et-runners.md) pour le workflow complet de montée de version.

---

## Exercice Bonus — Rollback automatique *(pour les plus rapides)*

**Objectif :** si le smoke test échoue après le déploiement, la pipeline doit automatiquement re-déployer la version précédente depuis Verdaccio.

Consulter le fichier [BONUS.md](./BONUS.md) pour les instructions détaillées.

---

## Vérification finale

Votre pipeline complète doit ressembler à ce DAG :

```
install → format-lint → tests → tests-e2e → build → security
                                                          ↓ (main only)
                                                        release
                                                          ↓
                                                       publish
                                                          ↓
                                                        deploy
                                                          ↓
                                                      smoke test
```

Pour tester la chaîne complète en une seule commande :

```bash
act push --eventpath <(echo '{"ref":"refs/heads/main"}')
```

---

## Pour aller plus loin — Comprendre l'infrastructure

L'environnement de ce TP fait interagir plusieurs systèmes (DevContainer, runners `act`, Verdaccio, SSH-target) avec des règles réseau et d'isolation git qui peuvent surprendre. La documentation suivante démystifie tout ça :

| Document | Contenu |
|---|---|
| [docs/architecture-overview.md](docs/architecture-overview.md) | Vue d'ensemble des 4 environnements, ports, réseau |
| [docs/git-et-runners.md](docs/git-et-runners.md) | Isolation git des runners, workflow de vraie montée de version |
| [docs/ssh-et-secrets.md](docs/ssh-et-secrets.md) | Keypair SSH, secrets `act`, `appleboy/ssh-action` |
| [docs/verdaccio-et-npm.md](docs/verdaccio-et-npm.md) | Verdaccio, relais socat, `npm unpublish`, `check-relays.sh` |
