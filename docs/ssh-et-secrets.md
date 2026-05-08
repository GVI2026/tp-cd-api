# SSH et secrets — Keypair, authentification, `appleboy/ssh-action`

---

## La keypair SSH — génération et rôle

Au démarrage du DevContainer, `setup.sh` génère automatiquement une paire de clés SSH dédiée au déploiement :

```bash
ssh-keygen -t ed25519 -f ~/.ssh/tp_cd_key -N "" -C "tp-cd-deploy"
```

Cela produit deux fichiers :
- `~/.ssh/tp_cd_key` — **clé privée** (reste sur le DevContainer, ne doit jamais être partagée)
- `~/.ssh/tp_cd_key.pub` — **clé publique** (déposée sur le serveur pour l'autoriser)

---

## Où va la clé publique ?

`setup.sh` injecte la clé publique directement dans le container ssh-target :

```bash
docker exec ssh-target sh -c "echo '$(cat ~/.ssh/tp_cd_key.pub)' \
  > /home/deployer/.ssh/authorized_keys && \
  chmod 600 /home/deployer/.ssh/authorized_keys && \
  chown deployer:deployer /home/deployer/.ssh/authorized_keys"
```

Le serveur ssh-target est configuré (dans son `Dockerfile`) pour :
- N'accepter que l'authentification par clé publique (`PubkeyAuthentication yes`)
- Refuser les mots de passe (`PasswordAuthentication no`)
- N'autoriser que l'utilisateur `deployer` (`AllowUsers deployer`)

Résultat : seul quelqu'un possédant `~/.ssh/tp_cd_key` peut se connecter en tant que `deployer`.

---

## Le fichier `.secrets` — rendre la clé accessible à `act`

Les runners `act` ont besoin de la clé privée pour se connecter au ssh-target. Elle leur est transmise via le fichier `.secrets`, qui simule les secrets GitHub Actions.

`setup.sh` crée ce fichier automatiquement :

```bash
{ printf 'SSH_PRIVATE_KEY="'; cat ~/.ssh/tp_cd_key; printf '"'; } > .secrets
chmod 600 .secrets
```

Contenu typique de `.secrets` :
```
SSH_PRIVATE_KEY="-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAA...
-----END OPENSSH PRIVATE KEY-----"
```

Le fichier `.actrc` indique à `act` de charger ce fichier à chaque run :
```
--secret-file .secrets
```

Ainsi, dans votre YAML, `${{ secrets.SSH_PRIVATE_KEY }}` est résolu par la valeur de ce fichier.

> ⚠️ `.secrets` est dans `.gitignore`. Ne le committez jamais — il contient une clé privée.

---

## `appleboy/ssh-action` — comment ça fonctionne

L'action `appleboy/ssh-action@v0.1.7` est une action GitHub qui encapsule une connexion SSH et l'exécution d'un script distant. Elle évite d'avoir à écrire la clé dans un fichier temporaire et de gérer manuellement `ssh`.

Configuration dans le YAML :

```yaml
- name: Déployer sur le serveur distant
  uses: appleboy/ssh-action@v0.1.7
  with:
    host: localhost       # adresse du serveur (via socat)
    port: 2222            # port SSH (socat → ssh-target:22)
    username: deployer    # utilisateur sur le serveur
    key: ${{ secrets.SSH_PRIVATE_KEY }}  # clé privée en clair
    script: |
      # Ces commandes s'exécutent sur le serveur ssh-target
      mkdir -p ~/app
      npm install --prefix ~/app tp-cd-api --ignore-scripts
      ...
```

Sous le capot, l'action :
1. Écrit la clé dans un fichier temporaire sécurisé
2. Lance `ssh -i <tempfile> -p 2222 deployer@localhost`
3. Exécute le `script` dans la session SSH
4. Supprime le fichier temporaire

---

## Flux réseau de la connexion SSH

```mermaid
flowchart TB
    runner["⚙️ Runner act\n--network=host"]
    socat["DevContainer\nlocalhost:2222\n(socat relay)"]
    sshd["ssh-target\nsshd :22"]
    script["Script deployer\nnpm install --prefix ~/app tp-cd-api\npm2 restart tp-cd-api"]
    verd["📦 verdaccio\nverdaccio:4873\n(cd-network)"]

    runner -->|"ssh -p 2222 deployer@localhost"| socat
    socat -->|"relay"| sshd
    sshd -->|"session SSH — keypair"| script
    script -->|"npm install\n(lit ~/.npmrc)"| verd
```

---

## Vérifier la connexion SSH manuellement

```bash
# Depuis le DevContainer
ssh -i ~/.ssh/tp_cd_key -p 2222 deployer@localhost "echo ok"

# Lister les processus pm2 sur le serveur
ssh -i ~/.ssh/tp_cd_key -p 2222 deployer@localhost "pm2 list"

# Consulter les logs de l'application déployée
ssh -i ~/.ssh/tp_cd_key -p 2222 deployer@localhost "pm2 logs tp-cd-api --lines 50"
```

> La configuration SSH locale dans `~/.ssh/config` (ajoutée par `setup.sh`) désactive la vérification de l'empreinte du serveur (`StrictHostKeyChecking no`) pour `localhost`, ce qui évite les prompts de confirmation à chaque connexion.
