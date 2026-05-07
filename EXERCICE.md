# Exercices — TP Cours-04 : Continuous Deployment

## Contexte

La pipeline CI de ce dépôt est **déjà opérationnelle et verte** : lint, tests unitaires, tests E2E, build et scan de sécurité fonctionnent. Votre mission est de compléter la chaîne en ajoutant les trois jobs de **Continuous Deployment** manquants dans `.github/workflows/ci.yml`.

**Infrastructure disponible dans votre DevContainer :**

- **Verdaccio** — registre npm privé : `http://localhost:4873`
- **SSH-target** — serveur de déploiement simulé : `ssh deployer@localhost -p 2222`
- L'application déployée sera accessible sur : `http://localhost:3001`

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

## Exercice 1 — Semantic Release (15 min)

**Objectif :** automatiser entièrement le versioning et la création de tags Git à partir des messages de commit, sans aucune intervention humaine.

### Ce que vous devez réaliser

**Étape 1 — Créer la configuration Semantic Release**

Créer un fichier `.releaserc.json` à la racine du projet. Ce fichier doit configurer semantic-release avec les plugins suivants, dans cet ordre :

- `@semantic-release/commit-analyzer` — analyse les commits pour déterminer le bump de version
- `@semantic-release/release-notes-generator` — génère les notes de release
- `@semantic-release/changelog` — met à jour `CHANGELOG.md`
- `@semantic-release/npm` — bumpe la version dans `package.json`
- `@semantic-release/git` — crée le tag Git et pousse les changements

**Étape 2 — Ajouter le job `semantic-release` dans `.github/workflows/ci.yml`**

Le job doit respecter les contraintes suivantes :

- Dépend du job `security`
- S'exécute **uniquement sur la branche `main`** (`if: github.ref == 'refs/heads/main'`)
- Le checkout doit utiliser `fetch-depth: 0` (semantic-release a besoin de tout l'historique git)
- **Contrainte locale (act) :** semantic-release tente de pousser ses tags vers un remote git. Comme le TP tourne entièrement en local sans GitHub, vous devez reconfigurer le remote pour pointer vers le workspace local d'act. Ajoutez ces deux commandes **avant** d'appeler semantic-release :
  ```bash
  git remote set-url origin "${GITHUB_WORKSPACE}"
  git config receive.denyCurrentBranch updateInstead
  ```
- Lancer `npx semantic-release`

**Étape 3 — Faire un commit et tester**

```bash
# Faire un commit au format Conventional Commits
git add .
git commit -m "feat: add semantic-release and publish pipeline"

# Lancer le job semantic-release
act -j semantic-release
```

### Résultat attendu

- Le tag `v1.0.0` est créé dans votre dépôt local (`git tag`)
- `CHANGELOG.md` est généré à la racine
- La version dans `package.json` est passée de `0.0.0` à `1.0.0`

---

## Exercice 2 — Publier vers Verdaccio (15 min)

**Objectif :** packager l'artefact construit une seule fois et le stocker dans le registre npm local.

### Ce que vous devez réaliser

Ajouter un job `publish` dans `.github/workflows/ci.yml` avec les contraintes suivantes :

- Dépend du job `semantic-release`
- S'exécute **uniquement sur la branche `main`**
- Récupère la version courante depuis `package.json` :
  ```bash
  VERSION=$(node -p "require('./package.json').version")
  ```
- Configure npm pour pointer vers Verdaccio :
  ```bash
  npm config set registry http://localhost:4873
  ```
- Publie l'artefact :
  ```bash
  npm publish --registry http://localhost:4873
  ```

> **Indice :** Verdaccio est configuré pour accepter les publications sans authentification. Pas besoin de token.

### Tester

```bash
act -j publish
```

### Résultat attendu

- Naviguer sur `http://localhost:4873` — le package `tp-cd-api` version `1.0.0` doit apparaître
- Ou vérifier en ligne de commande :
  ```bash
  npm view tp-cd-api --registry http://localhost:4873
  ```

---

## Exercice 3 — Déployer via SSH + Smoke Test (15 min)

**Objectif :** déployer automatiquement l'artefact sur le serveur target et valider le déploiement avec un smoke test.

### Ce que vous devez réaliser

Ajouter un job `deploy` dans `.github/workflows/ci.yml` avec les contraintes suivantes :

- Dépend du job `publish`
- S'exécute **uniquement sur la branche `main`**
- Lit la version depuis `package.json` (même technique qu'en Ex 2)
- Se connecte au SSH-target et exécute le déploiement en une commande SSH :
  ```bash
  ssh -i <clé_privée> -p 2222 -o StrictHostKeyChecking=no deployer@localhost \
    "npm install -g tp-cd-api@<VERSION> --registry http://verdaccio:4873 \
     && pm2 delete tp-cd-api || true \
     && pm2 start $(npm root -g)/tp-cd-api/dist/main.js --name tp-cd-api \
     && pm2 save"
  ```
- **La clé SSH privée** est disponible dans le secret `SSH_PRIVATE_KEY` (pré-configuré dans `.secrets` par le `postCreateCommand`). Vous devez l'écrire dans un fichier temporaire avant d'utiliser ssh :
  ```bash
  echo "${{ secrets.SSH_PRIVATE_KEY }}" > /tmp/deploy_key
  chmod 600 /tmp/deploy_key
  ```
- **Smoke test :** après le déploiement, vérifier que l'application répond :
  ```bash
  curl -f http://localhost:3001/health
  ```
  `curl -f` fait échouer la commande (et donc le step) si le code HTTP n'est pas 2xx.

### Tester

```bash
act -j deploy
```

### Résultat attendu

```bash
# L'API répond sur le serveur target :
curl http://localhost:3001/health
# {"status":"ok","timestamp":"2026-..."}

curl http://localhost:3001/tasks
# [{...}, {...}]
```

---

## Exercice Bonus — Rollback automatique *(pour les plus rapides)*

**Objectif :** si le smoke test échoue après le déploiement, la pipeline doit automatiquement re-déployer la version précédente depuis Verdaccio.

Consulter le fichier `BONUS.md` pour les instructions détaillées.

---

## Vérification finale

Votre pipeline complète doit ressembler à ce DAG :

```
install → format-lint → tests → tests-e2e → build → security
                                                          ↓ (main only)
                                                  semantic-release
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
